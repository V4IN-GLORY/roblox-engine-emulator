"""Runs one Luau file in ree and prints whether it worked, as JSON.

  python validator/validate.py path/to/Code.luau [--context server|client] [--ree target/release/ree.exe]

The file is the body of a script: it's wrapped as `return function(Context) ... end` and run for 1 second of game time, then
ree's coverage pass (`--fire-handlers`, docs/engine.md "Coverage pass") joins a player with a character and calls once every
handler the code connected or set that nothing called.
Output: {"ok": bool, "errors": [...], "unemulated": [...], "stubbed": [...], "coverage": {...}, "warnings": [...]}. ok is false
when the code raised anywhere (spawned threads, event handlers and the coverage pass's calls included). unemulated lists the
APIs ree reached but doesn't emulate yet: a run that touched one can't be trusted, so ok is null there. stubbed lists the
methods that answered a default of the type Roblox returns (tier 3): the run still counts. coverage says what the pass did:
the errors among `errors` that it raised (`errors`), the handlers its player's join and character ran (`real`) and the ones it
called with arguments of their parameter types (`fired`). warnings are luau-lsp's static diagnostics (`line:col: kind: text`),
which never change ok.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORT_TYPE = re.compile(r"^(\s*)export\s+type", re.M)
ROW_FILE = "Row.luau"
DIAGNOSTIC = re.compile(r"^" + re.escape(ROW_FILE) + r"\((\d+),(\d+)\): (.*)$")
EXTERN_TYPE = re.compile(r"^declare extern type (\w+) extends (\w+)", re.M)
# (luau-lsp knows no place: a child a script finds by name, `game.Players` or `workspace.Map`, is a key the type does not have)
CHILD_LOOKUP = re.compile(r"^TypeError: Key '[^']*' not found in external type '(\w+)'$")


def _runs(command: list[str]) -> bool:
	try:
		return subprocess.run(command + ["--version"], capture_output=True, timeout=30).returncode == 0
	except (OSError, subprocess.TimeoutExpired):
		return False


def find_luau_lsp() -> str | None:
	"""LUAU_LSP, else luau-lsp on PATH, else the newest one Rokit installed (its shim only runs inside a project that lists it)."""
	candidates = [os.environ.get("LUAU_LSP"), shutil.which("luau-lsp")]
	installed = glob.glob(os.path.join(os.path.expanduser("~"), ".rokit", "tool-storage", "johnnymorganz", "luau-lsp", "*", "luau-lsp*"))
	versions = lambda path: [int(part) for part in re.findall(r"\d+", os.path.basename(os.path.dirname(path)))]
	candidates += sorted(installed, key=versions, reverse=True)
	return next((path for path in candidates if path and _runs([path])), None)


def find_definitions() -> str | None:
	"""LUAU_LSP_DEFINITIONS, else the Roblox definitions the luau-lsp editor extension keeps (game-script security first)."""
	if os.environ.get("LUAU_LSP_DEFINITIONS"):
		return os.environ["LUAU_LSP_DEFINITIONS"]
	home = os.path.expanduser("~")
	configs = [os.environ.get("APPDATA"), os.path.join(home, ".config"), os.path.join(home, "Library", "Application Support")]
	editors = ["Code", "Code - Insiders", "Cursor", "VSCodium"]
	found = []
	for config in filter(None, configs):
		for editor in editors:
			found += glob.glob(os.path.join(config, editor, "User", "globalStorage", "johnnymorganz.luau-lsp", "globalTypes*.d.luau"))
	found.sort(key=lambda path: not path.endswith("globalTypes.None.d.luau"))
	return found[0] if found else None


def instance_classes(definitions: str) -> set[str]:
	"""The definitions' classes that are Instances (the rest, Vector3 and the like, have no children)."""
	with open(definitions, encoding="utf-8") as definitionsFile:
		parents = dict(EXTERN_TYPE.findall(definitionsFile.read()))
	classes = {"Instance"}
	for name in parents:
		chain, current = [], name
		while current in parents and current not in classes:
			chain.append(current)
			current = parents[current]
		if current in classes:
			classes.update(chain)
	return classes


def static_warnings(code: str) -> list[str]:
	"""luau-lsp analyze's diagnostics for the row, as `line:col: kind: text` (no file path), but an Instance's child lookups."""
	luau_lsp, definitions = find_luau_lsp(), find_definitions()
	if not luau_lsp or not definitions:
		return ["luau-lsp: not run (set LUAU_LSP and LUAU_LSP_DEFINITIONS)"]
	instances = instance_classes(definitions)
	with tempfile.TemporaryDirectory() as folder:
		with open(os.path.join(folder, ROW_FILE), "w", encoding="utf-8") as rowFile:
			rowFile.write(code)
		result = subprocess.run([luau_lsp, "analyze", f"--definitions=@roblox={definitions}", ROW_FILE], cwd=folder,
			capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
	warnings, kept = [], False
	for line in (result.stdout + result.stderr).splitlines():
		diagnostic = DIAGNOSTIC.match(line)
		if diagnostic:
			lookup = CHILD_LOOKUP.match(diagnostic[3])
			kept = not (lookup and lookup[1] in instances)
			if kept:
				warnings.append(f"{diagnostic[1]}:{diagnostic[2]}: {diagnostic[3]}")
		elif kept and line.strip() and not line.startswith("["):
			warnings[-1] += "\n" + line.replace(folder, "")
	return warnings


def validate(code: str, context: str, ree: str, warnings: bool = True) -> dict:
	with tempfile.TemporaryDirectory() as folder:
		harness = os.path.join(folder, "Block.luau")
		with open(harness, "w", encoding="utf-8") as harnessFile:
			harnessFile.write(f"return function(Context)\n{EXPORT_TYPE.sub(r'\1type', code)}\nend\n")
		result = subprocess.run([ree, "run", "--harness", harness, "--seconds", "1", "--script-timeout", "2", "--mode", "play", "--run-context", context, "--fire-handlers"],
			capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
	stdout = result.stdout
	try:
		summary = json.loads(stdout[stdout.index("{"):])
	except ValueError:
		return {"ok": None, "errors": [f"ree didn't run: {(result.stderr or stdout)[-400:]}"], "unemulated": [], "stubbed": [], "warnings": []}
	output = summary.get("output") or []
	errors = [line["message"] for line in output if line.get("kind") == "error"]
	unemulated = [line["message"].split(" is not emulated")[0] for line in output if line.get("kind") == "missing"]
	stubbed = [line["message"].split(" is not emulated")[0] for line in output if line.get("kind") == "stubbed"]
	passed = summary.get("coverage") or {}
	coverage = {
		"errors": [line["message"] for line in output if line.get("kind") == "error" and line.get("coverage")],
		"real": passed.get("real", []),
		"fired": passed.get("fired", []),
	}
	ok = None if unemulated else not errors
	return {"ok": ok, "errors": errors, "unemulated": unemulated, "stubbed": stubbed, "coverage": coverage,
		"warnings": static_warnings(code) if warnings else []}


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("file")
	parser.add_argument("--context", choices=["server", "client"], default="server")
	parser.add_argument("--ree", default=os.path.join(ROOT, "target", "release", "ree.exe"))
	args = parser.parse_args()
	sys.stdout.reconfigure(encoding="utf-8")
	print(json.dumps(validate(open(args.file, encoding="utf-8").read(), args.context, args.ree), indent=1))

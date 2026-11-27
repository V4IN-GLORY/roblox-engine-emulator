"""Runs Luau in ree and prints whether it worked, as JSON.

  python validator/validate.py path/to/Code.luau [--context server|client] [--ree target/release/ree.exe]
  python validator/validate.py --batch rows.jsonl [--out results.jsonl] [--context server|client] [--chunk 256] [--workers N]

The file is the body of a script: it's wrapped as `return function(Context) ... end` and run for 1 second of game time, then
ree's coverage pass (`--fire-handlers`, docs/engine.md "Coverage pass") joins a player with a character and calls once every
handler the code connected or set that nothing called. Code that uses Parallel Luau (ConnectParallel, task.desynchronize,
SharedTable, script:GetActor(), ...) runs instead as a Script (a LocalScript on a client) inside an Actor, as it must in
Roblox; `--actor` forces that for any code.
Output: {"ok": bool, "errors": [...], "unemulated": [...], "stubbed": [...], "coverage": {...}, "warnings": [...], "actor": bool}.
ok is false when the code raised anywhere (spawned threads, event handlers and the coverage pass's calls included).
unemulated lists the APIs ree reached but doesn't emulate yet: a run that touched one can't be trusted, so ok is null there.
stubbed lists the methods that answered a default of the type Roblox returns (tier 3): the run still counts. coverage says
what the pass did: the errors among `errors` that it raised (`errors`), the handlers its player's join and character ran
(`real`) and the ones it called with arguments of their parameter types (`fired`). warnings are luau-lsp's static
diagnostics (`line:col: kind: text`), which never change ok.

--batch reads JSON lines `{"id": ..., "code": "...", "context": "server"|"client"}` (context optional) and writes one result
line per row, with its id, in input order. Each chunk of rows is one `ree run --batch` process (the rows run side by side,
sharing compiled code and API data) and one luau-lsp call.
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
DIAGNOSTIC = re.compile(r"^(\w+)\.luau\((\d+),(\d+)\): (.*)$")
EXTERN_TYPE = re.compile(r"^declare extern type (\w+) extends (\w+)", re.M)
# (luau-lsp knows no place: a child a script finds by name, `game.Players` or `workspace.Map`, is a key the type does not have)
CHILD_LOOKUP = re.compile(r"^TypeError: Key '[^']*' not found in external type '(\w+)'$")
# Parallel Luau: what only runs (or only means anything) in a script under an Actor
PARALLEL = re.compile(r"ConnectParallel|BindTo\w*Parallel|BindToMessage|task\.(?:de)?synchronize|SharedTable|GetActor\s*\(|:SendMessage\s*\(")
RUN_ARGUMENTS = ["--seconds", "1", "--script-timeout", "2", "--mode", "play", "--fire-handlers"]
# (the batch's own cap per row, as the single run's subprocess timeout is)
ROW_WALL_SECONDS = "60"


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


def static_warnings(codes: list[str]) -> list[list[str]]:
	"""luau-lsp analyze's diagnostics for each code, as `line:col: kind: text` (no file path), but an Instance's child lookups.
	One luau-lsp call for all of them: it loads the definitions once."""
	luau_lsp, definitions = find_luau_lsp(), find_definitions()
	if not luau_lsp or not definitions:
		return [["luau-lsp: not run (set LUAU_LSP and LUAU_LSP_DEFINITIONS)"] for _ in codes]
	instances = instance_classes(definitions)
	warnings: list[list[str]] = [[] for _ in codes]
	with tempfile.TemporaryDirectory() as folder:
		files = []
		for index, code in enumerate(codes):
			files.append(f"Row{index}.luau")
			with open(os.path.join(folder, files[-1]), "w", encoding="utf-8") as rowFile:
				rowFile.write(code)
		result = subprocess.run([luau_lsp, "analyze", f"--definitions=@roblox={definitions}", *files], cwd=folder,
			capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120 + 2 * len(codes))
		kept = None
		for line in (result.stdout + result.stderr).splitlines():
			diagnostic = DIAGNOSTIC.match(line)
			if diagnostic and diagnostic[1].startswith("Row"):
				lookup = CHILD_LOOKUP.match(diagnostic[4])
				kept = None if lookup and lookup[1] in instances else warnings[int(diagnostic[1][3:])]
				if kept is not None:
					kept.append(f"{diagnostic[2]}:{diagnostic[3]}: {diagnostic[4]}")
			elif kept is not None and line.strip() and not line.startswith("["):
				kept[-1] += "\n" + line.replace(folder, "")
	return warnings


def long_string(text: str) -> str:
	"""text as a Luau long string whose brackets it doesn't contain."""
	level = 0
	while f"]{'=' * level}]" in text:
		level += 1
	return f"[{'=' * level}[\n{text}]{'=' * level}]"


def harness(code: str, context: str, actor: bool) -> str:
	"""The run's harness: the code as its body, or (actor) a harness that places the code as a script inside an Actor."""
	code = EXPORT_TYPE.sub(r"\1type", code)
	if not actor:
		return f"return function(Context)\n{code}\nend\n"
	# (a server Script runs under ServerScriptService; a client's LocalScript under its PlayerScripts)
	if context == "server":
		kind, parent = "Script", 'game:GetService("ServerScriptService")'
	else:
		kind, parent = "LocalScript", 'game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")'
	return (f"return function(Context)\n\tlocal Actor = Instance.new(\"Actor\")\n\tlocal Row = Instance.new(\"{kind}\")\n"
		f"\tRow.Name = \"Row\"\n\tRow.Source = {long_string(code)}\n\tRow.Parent = Actor\n\tActor.Parent = {parent}\nend\n")


def uses_actor(code: str, force: bool) -> bool:
	return force or bool(PARALLEL.search(code))


def result_of(summary: dict | None, failure: str, actor: bool) -> dict:
	"""A row's result from ree's run summary (None: ree didn't run, and failure says why)."""
	if summary is None:
		return {"ok": None, "errors": [f"ree didn't run: {failure[-400:]}"], "unemulated": [], "stubbed": [], "coverage": {},
			"warnings": [], "actor": actor}
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
	return {"ok": ok, "errors": errors, "unemulated": unemulated, "stubbed": stubbed, "coverage": coverage, "warnings": [],
		"actor": actor}


def validate(code: str, context: str, ree: str, warnings: bool = True, actor: bool = False) -> dict:
	inActor = uses_actor(code, actor)
	with tempfile.TemporaryDirectory() as folder:
		path = os.path.join(folder, "Block.luau")
		with open(path, "w", encoding="utf-8") as harnessFile:
			harnessFile.write(harness(code, context, inActor))
		result = subprocess.run([ree, "run", "--harness", path, *RUN_ARGUMENTS, "--run-context", context],
			capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
	stdout = result.stdout
	try:
		summary = json.loads(stdout[stdout.index("{"):])
	except ValueError:
		summary = None
	row = result_of(summary, result.stderr or stdout, inActor)
	if warnings and summary is not None:
		row["warnings"] = static_warnings([code])[0]
	return row


def validate_chunk(rows: list[dict], ree: str, workers: int | None, warnings: bool, actor: bool) -> list[dict]:
	"""One `ree run --batch` process (and one luau-lsp call) for rows ({"code", "context"}); their results in order."""
	with tempfile.TemporaryDirectory() as folder:
		jobs, inActor = [], []
		for index, row in enumerate(rows):
			inActor.append(uses_actor(row["code"], actor))
			path = os.path.join(folder, f"Row{index}.luau")
			with open(path, "w", encoding="utf-8") as harnessFile:
				harnessFile.write(harness(row["code"], row["context"], inActor[-1]))
			jobs.append({"id": str(index), "args": ["--harness", path, *RUN_ARGUMENTS, "--run-context", row["context"],
				"--max-wall-seconds", ROW_WALL_SECONDS]})
		spec = os.path.join(folder, "jobs.json")
		with open(spec, "w", encoding="utf-8") as specFile:
			json.dump({"workers": workers, "jobs": jobs} if workers else {"jobs": jobs}, specFile)
		result = subprocess.run([ree, "run", "--batch", spec], capture_output=True, text=True, encoding="utf-8", errors="replace",
			timeout=600 + 60 * len(rows))
	stdout = result.stdout
	try:
		answers = {entry["id"]: entry for entry in json.loads(stdout[stdout.index("{"):])["results"] if entry}
	except (ValueError, KeyError, TypeError):
		answers = {}
	results = []
	for index in range(len(rows)):
		entry = answers.get(str(index)) or {}
		failure = entry.get("error") or result.stderr or stdout or "no result"
		results.append(result_of(entry.get("summary"), failure, inActor[index]))
	if warnings:
		for row, found in zip(results, static_warnings([row["code"] for row in rows])):
			row["warnings"] = found
	return results


def validate_batch(source, out, context: str, ree: str, chunk: int, workers: int | None, warnings: bool, actor: bool) -> None:
	"""Reads rows (JSON lines) from source and writes each one's result line to out, a chunk at a time."""
	pending: list[dict] = []

	def flush() -> None:
		for row, result in zip(pending, validate_chunk(pending, ree, workers, warnings, actor)):
			out.write(json.dumps({"id": row["id"], **result}) + "\n")
		out.flush()
		pending.clear()

	for number, line in enumerate(source, 1):
		if not line.strip():
			continue
		row = json.loads(line)
		pending.append({"id": row.get("id", number), "code": row["code"], "context": row.get("context") or context})
		if len(pending) >= chunk:
			flush()
	if pending:
		flush()


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("file", nargs="?")
	parser.add_argument("--batch", help="JSON lines of {id, code, context}")
	parser.add_argument("--out", help="where --batch writes its result lines (default: stdout)")
	parser.add_argument("--context", choices=["server", "client"], default="server")
	parser.add_argument("--ree", default=os.path.join(ROOT, "target", "release", "ree.exe"))
	parser.add_argument("--chunk", type=int, default=256, help="rows per ree process")
	parser.add_argument("--workers", type=int, help="rows a ree process runs at once (default: one per CPU)")
	parser.add_argument("--no-warnings", action="store_true", help="skip luau-lsp")
	parser.add_argument("--actor", action="store_true", help="run every row as a script inside an Actor")
	args = parser.parse_args()
	sys.stdout.reconfigure(encoding="utf-8")
	if args.batch:
		with open(args.batch, encoding="utf-8") as source:
			out = open(args.out, "w", encoding="utf-8") if args.out else sys.stdout
			try:
				validate_batch(source, out, args.context, args.ree, max(1, args.chunk), args.workers, not args.no_warnings, args.actor)
			finally:
				if out is not sys.stdout:
					out.close()
	elif args.file:
		with open(args.file, encoding="utf-8") as codeFile:
			print(json.dumps(validate(codeFile.read(), args.context, args.ree, not args.no_warnings, args.actor), indent=1))
	else:
		parser.error("a file or --batch is required")

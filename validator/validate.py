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
# Which side code runs on, by what it uses (--context auto): each match weighs for its side, and the request's words break a tie
CLIENT_SIGNS = re.compile(r"\bLocalPlayer\b|UserInputService|ContextActionService|GuiService|HapticService|VRService|:GetMouse\s*\(|RenderStepped|"
	r"BindToRenderStep|\bPlayerGui\b|:FireServer\s*\(|:InvokeServer\s*\(|OnClientEvent|OnClientInvoke|:SetCore\s*\(|:SetCoreGuiEnabled\s*\(|"
	r"CurrentCamera|PlayerScripts")
SERVER_SIGNS = re.compile(r"OnServerEvent|OnServerInvoke|:FireClient\s*\(|:FireAllClients\s*\(|DataStoreService|MessagingService|MemoryStoreService|"
	r"ServerScriptService|ServerStorage|:LoadCharacter\s*\(|AwardBadge|ProcessReceipt|:(?:Get|Post|Request)Async\s*\(|TeleportAsync|BanAsync|"
	r":SetNetworkOwner\s*\(")
CLIENT_WORDS = re.compile(r"\blocal ?script\b|\bclient[- ]side\b|\bon the client\b|StarterPlayerScripts|StarterGui|StarterCharacterScripts", re.I)
SERVER_WORDS = re.compile(r"\bserver[- ]side\b|\bserver script\b|\bon the server\b|ServerScriptService|\bScript in\b", re.I)
# A module's answer: the code ends returning a table it built, whose functions that take no arguments the run calls
MODULE_RETURN = re.compile(r"^return\s+([A-Za-z_]\w*)\s*$")
MISSING_MEMBER = re.compile(r"^(?:.*?:\d+: )?(.+?) is not a valid member of (\w+) \"[^\"]*\"$")
# (a run's verdict is settled long before a thousand lines: the cap ends a script that errors in a loop, whose millions of lines
# a batch process can't print)
RUN_ARGUMENTS = ["--seconds", "1", "--script-timeout", "2", "--mode", "play", "--fire-handlers", "--max-output-lines", "1000"]
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


def harness(code: str, context: str, actor: bool) -> tuple[str, int]:
	"""The run's harness, and how many lines it puts before the code's first: the code as its body (a vararg function, as a
	script's chunk is), or (actor) a harness that places the code as a script inside an Actor."""
	code = EXPORT_TYPE.sub(r"\1type", code)
	if not actor:
		calls = module_calls(code)
		if not calls:
			return f"return function(Context, ...)\n{code}\nend\n", 1
		# (each in a thread of its own, so one that errors or waits doesn't keep the others from running)
		spawned = "".join(f"\ttask.spawn(function() Module{call}() end)\n" for call in calls)
		return f"return function(Context, ...)\n\tlocal Module = (function(...)\n{code}\nend)(...)\n{spawned}end\n", 2
	# (a server Script runs under ServerScriptService; a client's LocalScript under its PlayerScripts)
	if context == "server":
		kind, parent = "Script", 'game:GetService("ServerScriptService")'
	else:
		kind, parent = "LocalScript", 'game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")'
	return (f"return function(Context)\n\tlocal Actor = Instance.new(\"Actor\")\n\tlocal Row = Instance.new(\"{kind}\")\n"
		f"\tRow.Name = \"Row\"\n\tRow.Source = {long_string(code)}\n\tRow.Parent = Actor\n\tActor.Parent = {parent}\nend\n"), 0


def uses_actor(code: str, force: bool) -> bool:
	return force or bool(PARALLEL.search(code))


def detect_context(code: str, hint: str = "") -> str:
	"""client or server, by the APIs the code uses (a client's LocalPlayer, UserInputService, FireServer ...; a server's
	DataStores, OnServerEvent, FireClient ...), then the request's words (a LocalScript, a server script); server when neither says."""
	client, server = len(CLIENT_SIGNS.findall(code)), len(SERVER_SIGNS.findall(code))
	if client == server:
		client, server = len(CLIENT_WORDS.findall(hint)), len(SERVER_WORDS.findall(hint))
	return "client" if client > server else "server"


def module_calls(code: str) -> list[str]:
	"""For code that ends returning a table it built (a ModuleScript), how to call that table's functions that take no
	arguments (`M.Init()`, `M:Start()`): a run that only loads the module never runs them."""
	lines = [line for line in code.strip().splitlines() if line.strip() and not line.strip().startswith("--")]
	returned = MODULE_RETURN.match(lines[-1].strip()) if lines else None
	if not returned:
		return []
	name = re.escape(returned[1])
	return [f"{separator}{method}" for separator, method in re.findall(rf"^\s*function\s+{name}([.:])(\w+)\s*\(\s*\)", code, re.M)]


# Services a place keeps its own instances in: a name looked up under one is a child the code expects. Under any other service
# (UserInputService.MouseDelta) a name that is no member is the code's mistake.
CONTAINER_SERVICES = {"Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterGui",
	"StarterPack", "StarterPlayer", "Lighting", "SoundService", "Teams", "Players", "Chat", "TextChatService", "MaterialService"}
HARNESS_FOLDER = "RURFixtures"
REQUIRE_UNRESOLVED = re.compile(r"Could not resolve require path")
UNKNOWN_GLOBAL = re.compile(r"^(\d+):\d+: TypeError: Unknown global '(\w+)'")
ERROR_LINE = re.compile(r"^\S.*?:(\d+): ")

_CLASSES: tuple[dict[str, set[str]], set[str]] | None = None


def class_data() -> tuple[dict[str, set[str]], set[str]]:
	"""Each class's member names (its superclasses' too, lower-cased) and the services, from the API data the engine compiles in."""
	global _CLASSES
	if _CLASSES is None:
		classes = {}
		for name in ("reflection.json", "docs-supplement.json"):
			with open(os.path.join(ROOT, "data", name), encoding="utf-8") as dataFile:
				for entry in json.load(dataFile)["classes"]:
					classes.setdefault(entry["name"], entry)
		own = {name: {member["name"].lower() for kind in ("properties", "methods", "events", "callbacks") for member in entry.get(kind) or []}
			for name, entry in classes.items()}
		members = {}
		for name in classes:
			found, current = set(), name
			while current in classes:
				found |= own[current]
				current = classes[current].get("superclass")
			members[name] = found
		services = {name for name, entry in classes.items() if isinstance(entry.get("permits"), dict) and "GetService" in entry["permits"]}
		_CLASSES = (members, services)
	return _CLASSES


def _near(word: str, other: str) -> bool:
	"""A typo of it: one edit apart, two for a name over six letters."""
	allowed = 2 if len(other) > 6 else 1
	if abs(len(word) - len(other)) > allowed:
		return False
	previous = list(range(len(other) + 1))
	for row, letter in enumerate(word, 1):
		current = [row]
		for column, wanted in enumerate(other, 1):
			current.append(min(previous[column] + 1, current[column - 1] + 1, previous[column - 1] + (letter != wanted)))
		previous = current
	return previous[-1] <= allowed


def environment_error(message: str) -> bool:
	"""An error that comes from the place the code expects rather than the code: a child it looks up by name that an empty
	place lacks (`workspace.Map`, `ReplicatedStorage.Remotes`, `script.Parent.Handle`). A name that is, or is a typo of, one of
	the class's members (`part.Positon`), a name under a service that holds no instances of the place's
	(`UserInputService.MouseDelta`) and a service the side lacks (`game.ServerScriptService` on a client) are the code's."""
	first = ERROR_LINE.sub("", message.splitlines()[0] if message else "")
	# (the run's own folder: code that expects `script.Parent` to be a part, a tool or a GUI finds the harness's; a module path
	# the place would hold)
	if HARNESS_FOLDER in first or REQUIRE_UNRESOLVED.search(first):
		return True
	missing = MISSING_MEMBER.match(first)
	if not missing:
		return False
	members, services = class_data()
	key, owner = missing[1], missing[2]
	if owner == "DataModel":
		return key not in services
	if owner in services and owner not in CONTAINER_SERVICES:
		return False
	known = members.get(owner, set())
	lowered = key.lower()
	return lowered not in known and not (len(lowered) >= 4 and any(_near(lowered, member) for member in known))


def verdict(row: dict, code: str, offset: int) -> str:
	"""One word for a row: ok; untrusted (it reached an API ree doesn't emulate); environment (only children of a place it
	expects are missing); snippet (besides those, only lines using a global the code never defines fail: a fragment of a
	longer script); error (anything else: the code is wrong). Snippets need luau-lsp's warnings."""
	if row["unemulated"]:
		return "untrusted"
	if not row["errors"]:
		return "ok"
	lines = code.splitlines()
	names = {unknown[2] for unknown in map(UNKNOWN_GLOBAL.match, row["warnings"]) if unknown}
	kinds = set()
	for error in row["errors"]:
		if error in row["environment"]:
			kinds.add("environment")
			continue
		at = ERROR_LINE.match(error)
		if not at:
			# (an engine call's error names no line: in a fragment it's most likely an undefined global passed in, `FireClient(player)`)
			kinds.add("snippet" if names else "error")
			continue
		index = int(at[1]) - 1 - offset
		text = lines[index] if 0 <= index < len(lines) else ""
		kinds.add("snippet" if any(re.search(rf"\b{name}\b", text) for name in names) else "error")
	if "error" in kinds:
		return "error"
	return "snippet" if "snippet" in kinds else "environment"


def result_of(summary: dict | None, failure: str, actor: bool) -> dict:
	"""A row's result from ree's run summary (None: ree didn't run, and failure says why)."""
	if summary is None:
		return {"ok": None, "errors": [f"ree didn't run: {failure[-400:]}"], "environment": [], "unemulated": [], "stubbed": [],
			"coverage": {}, "warnings": [], "actor": actor, "verdict": "untrusted"}
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
	environment = [error for error in errors if environment_error(error)]
	return {"ok": ok, "errors": errors, "environment": environment, "unemulated": unemulated, "stubbed": stubbed,
		"coverage": coverage, "warnings": [], "actor": actor}


def validate(code: str, context: str, ree: str, warnings: bool = True, actor: bool = False, hint: str = "") -> dict:
	if context == "auto":
		context = detect_context(code, hint)
	inActor = uses_actor(code, actor)
	with tempfile.TemporaryDirectory() as folder:
		path = os.path.join(folder, "Block.luau")
		text, offset = harness(code, context, inActor)
		with open(path, "w", encoding="utf-8") as harnessFile:
			harnessFile.write(text)
		result = subprocess.run([ree, "run", "--harness", path, *RUN_ARGUMENTS, "--run-context", context],
			capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
	stdout = result.stdout
	try:
		summary = json.loads(stdout[stdout.index("{"):])
	except ValueError:
		summary = None
	row = {"context": context, **result_of(summary, result.stderr or stdout, inActor)}
	if summary is not None:
		if warnings:
			row["warnings"] = static_warnings([code])[0]
		row["verdict"] = verdict(row, code, offset)
	return row


def validate_chunk(rows: list[dict], ree: str, workers: int | None, warnings: bool, actor: bool) -> list[dict]:
	"""One `ree run --batch` process (and one luau-lsp call) for rows ({"code", "context"}); their results in order."""
	with tempfile.TemporaryDirectory() as folder:
		jobs, inActor, offsets = [], [], []
		for index, row in enumerate(rows):
			inActor.append(uses_actor(row["code"], actor))
			path = os.path.join(folder, f"Row{index}.luau")
			text, offset = harness(row["code"], row["context"], inActor[-1])
			offsets.append(offset)
			with open(path, "w", encoding="utf-8") as harnessFile:
				harnessFile.write(text)
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
	# (a process that died with a row takes the chunk's unanswered rows with it: they run again, half at a time, until only
	# the row that kills it is left)
	if len(rows) > 1 and len(answers) < len(rows):
		half = len(rows) // 2
		return validate_chunk(rows[:half], ree, workers, warnings, actor) + validate_chunk(rows[half:], ree, workers, warnings, actor)
	results = []
	for index in range(len(rows)):
		entry = answers.get(str(index)) or {}
		failure = entry.get("error") or result.stderr or stdout or "no result"
		results.append({"context": rows[index]["context"], **result_of(entry.get("summary"), failure, inActor[index])})
	if warnings:
		for row, found in zip(results, static_warnings([row["code"] for row in rows])):
			row["warnings"] = found
	for result, row, offset in zip(results, rows, offsets):
		result.setdefault("verdict", verdict(result, row["code"], offset))
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
		rowContext = row.get("context") or context
		if rowContext == "auto":
			rowContext = detect_context(row["code"], row.get("hint") or "")
		pending.append({"id": row.get("id", number), "code": row["code"], "context": rowContext})
		if len(pending) >= chunk:
			flush()
	if pending:
		flush()


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("file", nargs="?")
	parser.add_argument("--batch", help="JSON lines of {id, code, context}")
	parser.add_argument("--out", help="where --batch writes its result lines (default: stdout)")
	parser.add_argument("--context", choices=["auto", "server", "client"], default="auto",
		help="auto: by the APIs the code uses, then a row's hint (extract.py)")
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

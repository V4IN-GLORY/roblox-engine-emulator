"""Runs Luau in ree and prints whether it worked, as JSON.

  python validator/validate.py path/to/Code.luau [--context auto|server|client] [--ree target/release/ree.exe]
  python validator/validate.py --batch rows.jsonl [--out results.jsonl] [--context auto|server|client] [--chunk 256] [--workers N]

The code runs for 1 second of game time as scripts (each fenced block of a row, and a module and the code after it, is one,
on the side its APIs say: plan), with stand-ins for the children of the place it expects (`--stand-ins`) and the Luau syntax
the dataset uses (LUAU_FLAGS); then ree's coverage pass (`--fire-handlers`, docs/engine.md "Coverage pass") joins a player
with a character and calls once every handler the code connected or set that nothing called. Code that uses Parallel Luau
(ConnectParallel, task.desynchronize, SharedTable, script:GetActor(), ...) runs as a Script (a LocalScript on a client)
inside an Actor, as it must in Roblox; `--actor` forces that.

Output: {"context", "ok", "verdict", "pass", "errors", "environment", "unemulated", "stubbed", "stand_ins", "coverage",
"warnings", "actor"}. verdict and pass: finish. ok is false when the code raised anywhere (spawned threads, handlers and the
coverage pass included), null when it reached an API ree doesn't emulate. environment: the errors that are the empty
place's. stubbed: methods that answered a default of the type Roblox returns (the run still counts). warnings: luau-lsp's
static diagnostics (`line:col: kind: text`), which never change ok.

--batch reads JSON lines (extract.py's rows: {"id", "code" or "blocks", "earlier"?, "hint"?, "context"?}) and writes one
result line per row, with its id, in input order: each chunk is one `ree run --batch` process and one luau-lsp call.
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
TOP_RETURN = re.compile(r"^return\b")
STATEMENT_CLOSER = re.compile(r"^(?:[})\]]|end\b)")
MISSING_MEMBER = re.compile(r"^(?:.*?:\d+: )?(.+?) is not a valid member of (\w+) \"([^\"]*)\"$")
REQUIRE_INVALID = "Attempted to call require with invalid argument(s)."
# Luau syntax the VM has behind flags that Roblox's live 0.748 client leaves off, which the dataset's code uses (`if local x =
# f() then`, `while local`): rows are judged as the Luau they're written in, so the run turns them on
LUAU_FLAGS = ["LuauExperimentalIfLocalSyntax=true", "LuauExperimentalWhileLocalSyntax=true"]
PARSE_ERROR = re.compile(r"Expected |Incomplete statement|Malformed|Unexpected ")
# (a run's verdict is settled long before a thousand lines: the cap ends a script that errors in a loop, whose millions of lines
# a batch process can't print; a stand-in for each child the place would hold lets the code go on past it)
RUN_ARGUMENTS = ["--seconds", "1", "--script-timeout", "2", "--mode", "play", "--fire-handlers", "--max-output-lines", "1000", "--stand-ins",
	*[argument for flag in LUAU_FLAGS for argument in ("--luau-flag", flag)]]
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


def scripts(lines: list[str]) -> list[tuple[int, int]]:
	"""The scripts code holds, as (first, last + 1) line ranges: a top-level `return` (a ModuleScript's last line) followed by
	more code ends one and starts another (an answer's module, then the script that uses it)."""
	ranges, start = [], 0
	for index, line in enumerate(lines):
		if index < start or not TOP_RETURN.match(line):
			continue
		# (the return statement runs on through indented lines and its closers, `return {` ... `}`: the next script starts at the
		# first top-level line after it that is code)
		after = next((later for later in range(index + 1, len(lines)) if lines[later].strip() and not lines[later][0].isspace()
			and not lines[later].startswith("--") and not STATEMENT_CLOSER.match(lines[later])), None)
		if after is not None:
			ranges.append((start, after))
			start = after
	ranges.append((start, len(lines)))
	return ranges


def harness(code: str, context: str, actor: bool, ranges: list[tuple[int, int]] | None = None) -> tuple[str, list[int]]:
	"""The run's harness, and for each of its lines the code's line it holds (-1 for its own): each script the code holds
	(scripts) runs in a function of its own (a vararg one, as a script's chunk is) in a thread of its own, so one that errors or
	waits doesn't keep the next from running, and a module's no-argument functions are called after it loads (module_calls).
	One script alone is the harness's body. With actor, a harness that places the code as a script inside an Actor."""
	code = EXPORT_TYPE.sub(r"\1type", code)
	lines = code.split("\n")
	if actor:
		# (a server Script runs under ServerScriptService; a client's LocalScript under its PlayerScripts)
		if context == "server":
			kind, parent = "Script", 'game:GetService("ServerScriptService")'
		else:
			kind, parent = "LocalScript", 'game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts")'
		text = (f"return function(Context)\n\tlocal Actor = Instance.new(\"Actor\")\n\tlocal Row = Instance.new(\"{kind}\")\n"
			f"\tRow.Name = \"Row\"\n\tRow.Source = {long_string(code)}\n\tRow.Parent = Actor\n\tActor.Parent = {parent}\nend\n")
		return text, list(range(len(lines)))
	out, where = ["return function(Context, ...)"], [-1]

	def own(line: str) -> None:
		out.append(line)
		where.append(-1)

	ranges = ranges or scripts(lines)
	for first, last in ranges:
		body = "\n".join(lines[first:last])
		calls = module_calls(body)
		alone = len(ranges) == 1 and not calls
		if not alone:
			own("task.spawn(function(...)" if not calls else "do local Module = (function(...)")
		out.extend(lines[first:last])
		where.extend(range(first, last))
		if not alone:
			own("end, ...)" if not calls else "end)(...)")
			for call in calls:
				own(f"task.spawn(function() Module{call}() end)")
			if calls:
				own("end")
	own("end")
	return "\n".join(out) + "\n", where


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


def environment_error(message: str, stand_ins: list[str] = ()) -> bool:
	"""An error that comes from the place the code expects rather than the code: a child it looks up by name that an empty
	place lacks (`workspace.Map`, `ReplicatedStorage.Remotes`, `script.Parent.Handle`), and a real member the code uses on a
	stand-in (`--stand-ins`) whose class ree guessed wrong (`Remotes.Buy:InvokeServer()` on a RemoteEvent). A name that is, or
	is a typo of, one of the class's members (`part.Positon`), a name under a service that holds no instances of the place's
	(`UserInputService.MouseDelta`) and a service the side lacks (`game.ServerScriptService` on a client) are the code's."""
	first = ERROR_LINE.sub("", message.splitlines()[0] if message else "")
	# (the run's own folder: code that expects `script.Parent` to be a part, a tool or a GUI finds the harness's; a module path
	# the place would hold; a module the place would hold that a stand-in folder stands for)
	if HARNESS_FOLDER in first or REQUIRE_UNRESOLVED.search(first) or (stand_ins and REQUIRE_INVALID in first):
		return True
	missing = MISSING_MEMBER.match(first)
	if not missing:
		return False
	members, services = class_data()
	key, owner, path = missing[1], missing[2], missing[3]
	if path in stand_ins:
		# (any member's name, a callback's too, is a wrong guess at the stand-in's class; a near miss of one is a typo)
		lowered = key.lower()
		return lowered in ALL_MEMBERS() or not (len(lowered) >= 4 and any(_near(lowered, member) for member in ALL_MEMBERS()))
	if owner == "DataModel":
		return key not in services
	if owner in services and owner not in CONTAINER_SERVICES:
		return False
	known = members.get(owner, set())
	lowered = key.lower()
	return lowered not in known and not (len(lowered) >= 4 and any(_near(lowered, member) for member in known))


_ALL_MEMBERS: set[str] | None = None


def ALL_MEMBERS() -> set[str]:
	"""Every class's member names, lower-cased."""
	global _ALL_MEMBERS
	if _ALL_MEMBERS is None:
		_ALL_MEMBERS = set().union(*class_data()[0].values())
	return _ALL_MEMBERS


def defined_in(name: str, earlier: str) -> bool:
	"""Whether the conversation's earlier code gives `name` a meaning: a local, a function, an assignment, a loop variable or a
	function's parameter (an answer that changes a handler's body uses its `player`)."""
	word = re.escape(name)
	return bool(re.search(rf"\blocal\s+(?:function\s+)?[\w\s,]*?\b{word}\b|\bfunction\s+{word}\b|^\s*{word}\s*=|\bfor\s+[\w\s,]*?\b{word}\b|"
		rf"\bfunction\b[^(\n]*\([^)]*\b{word}\b", earlier, re.M))


def context_of(job: dict, index: int) -> str:
	"""The code a script at the job's line `index` builds on: the conversation's earlier code and the answer's other scripts."""
	own = next((number for number, (first, last) in enumerate(job["ranges"]) if first <= index < last), -1)
	return "\n".join([job["earlier"], *job["others"], *(text for number, text in enumerate(job["scripts"]) if number != own)])


def finish(row: dict, job: dict, where: list[int]) -> dict:
	"""A row's verdict and pass, from its errors and luau-lsp's warnings. luau-lsp's syntax errors go when ree compiled the
	code: its Luau (and its flags, LUAU_FLAGS) are newer than luau-lsp's.

	verdict: ok; untrusted (it reached an API ree doesn't emulate); environment (only what the place would hold is missing);
	context (besides those, only lines using names the conversation's earlier code defines fail: the answer is a change to that
	code, fine where it goes); snippet (only lines using a global nothing defines fail: a fragment meant to be pasted into code
	the row doesn't have); error (anything else: the code is wrong). pass: ok, environment or context. Snippets and context need
	luau-lsp's warnings."""
	compiled = not any(PARSE_ERROR.search(error) for error in row["errors"])
	names = {unknown[2] for unknown in map(UNKNOWN_GLOBAL.match, row["warnings"]) if unknown}
	if compiled:
		row["warnings"] = [warning for warning in row["warnings"] if not re.match(r"^\d+:\d+: SyntaxError", warning)]
	lines = job["code"].split("\n")
	kinds = set()
	for error in row["errors"]:
		if error in row["environment"]:
			kinds.add("environment")
			continue
		at = ERROR_LINE.match(error)
		line = int(at[1]) - 1 if at else -1
		index = where[line] if 0 <= line < len(where) else -1
		text = lines[index] if 0 <= index < len(lines) else ""
		# (an engine call's error names no line: in a fragment it's most likely an undefined global passed in, `FireClient(player)`)
		used = [name for name in names if not at or re.search(rf"\b{re.escape(name)}\b", text)]
		if not used:
			kinds.add("error")
		elif all(defined_in(name, context_of(job, index)) for name in used):
			kinds.add("context")
		else:
			kinds.add("snippet")
	if row["unemulated"]:
		row["verdict"] = "untrusted"
	elif not row["errors"]:
		row["verdict"] = "ok"
	else:
		row["verdict"] = next(kind for kind in ("error", "snippet", "context", "environment") if kind in kinds)
	row["pass"] = row["verdict"] in ("ok", "environment", "context")
	return row


def result_of(summary: dict | None, failure: str, actor: bool) -> dict:
	"""A row's result from ree's run summary (None: ree didn't run, and failure says why)."""
	if summary is None:
		return {"ok": None, "errors": [f"ree didn't run: {failure[-400:]}"], "environment": [], "unemulated": [], "stubbed": [],
			"stand_ins": [], "coverage": {}, "warnings": [], "actor": actor, "verdict": "untrusted", "pass": False}
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
	standIns = summary.get("standIns") or []
	environment = [error for error in errors if environment_error(error, standIns)]
	return {"ok": ok, "errors": errors, "environment": environment, "unemulated": unemulated, "stubbed": stubbed,
		"stand_ins": standIns, "coverage": coverage, "warnings": [], "actor": actor}


def side_of(code: str) -> str | None:
	"""client or server by the APIs the code uses alone; None when it doesn't say."""
	client, server = len(CLIENT_SIGNS.findall(code)), len(SERVER_SIGNS.findall(code))
	return None if client == server else "client" if client > server else "server"


def plan(row: dict, context: str) -> list[dict]:
	"""The ree runs a row takes: each script its code holds (a fenced block, or a module and the code after it: scripts) runs
	on its own side, so an answer's server Script and its LocalScript each run where they belong; the scripts of a side share
	one run. A script whose APIs don't say takes the answer's side (detect_context), then the given one."""
	blocks = row.get("blocks") or [row["code"]]
	answer = "\n".join(blocks)
	overall = row.get("context") or context
	if overall == "auto":
		overall = detect_context(answer, row.get("hint") or "")
	found = []
	for block in blocks:
		lines = block.split("\n")
		for first, last in scripts(lines):
			text = "\n".join(lines[first:last])
			if text.strip():
				found.append(((row.get("context") or context) != "auto" and overall or side_of(text) or overall, text))
	jobs: dict[str, list[str]] = {}
	for side, text in found:
		jobs.setdefault(side, []).append(text)
	planned = []
	for side, texts in jobs.items():
		ranges, at = [], 0
		for text in texts:
			count = text.count("\n") + 1
			ranges.append((at, at + count))
			at += count
		others = [text for otherSide, text in found if otherSide != side]
		planned.append({"context": side, "code": "\n".join(texts), "ranges": ranges, "scripts": texts, "others": others,
			"earlier": row.get("earlier") or ""})
	return planned


WORST = ["error", "snippet", "untrusted", "context", "environment", "ok"]


def merge(results: list[dict]) -> dict:
	"""One row's result from its runs' (plan): every list joined, the worst verdict, a pass only when each run passed."""
	if len(results) == 1:
		return results[0]
	merged = {"context": "+".join(result["context"] for result in results)}
	oks = [result["ok"] for result in results]
	merged["ok"] = None if None in oks else all(oks)
	for key in ("errors", "environment", "unemulated", "stubbed", "stand_ins", "warnings"):
		merged[key] = [item for result in results for item in result.get(key, [])]
	merged["coverage"] = {key: [item for result in results for item in (result.get("coverage") or {}).get(key, [])] for key in ("errors", "real", "fired")}
	merged["actor"] = any(result["actor"] for result in results)
	merged["verdict"] = min((result["verdict"] for result in results), key=WORST.index)
	merged["pass"] = all(result["pass"] for result in results)
	return merged


def run_jobs(jobs: list[dict], ree: str, workers: int | None, warnings: bool, actor: bool) -> list[dict]:
	"""One `ree run --batch` process (and one luau-lsp call) for jobs (plan); their results in order."""
	with tempfile.TemporaryDirectory() as folder:
		specs, inActor, made = [], [], []
		for index, job in enumerate(jobs):
			inActor.append(uses_actor(job["code"], actor))
			path = os.path.join(folder, f"Row{index}.luau")
			text, where = harness(job["code"], job["context"], inActor[-1], job["ranges"])
			made.append((text, where))
			with open(path, "w", encoding="utf-8") as harnessFile:
				harnessFile.write(text)
			specs.append({"id": str(index), "args": ["--harness", path, *RUN_ARGUMENTS, "--run-context", job["context"],
				"--max-wall-seconds", ROW_WALL_SECONDS]})
		spec = os.path.join(folder, "jobs.json")
		with open(spec, "w", encoding="utf-8") as specFile:
			json.dump({"workers": workers, "jobs": specs} if workers else {"jobs": specs}, specFile)
		result = subprocess.run([ree, "run", "--batch", spec], capture_output=True, text=True, encoding="utf-8", errors="replace",
			timeout=600 + 60 * len(jobs))
	stdout = result.stdout
	try:
		answers = {entry["id"]: entry for entry in json.loads(stdout[stdout.index("{"):])["results"] if entry}
	except (ValueError, KeyError, TypeError):
		answers = {}
	# (a process that died with a job takes the chunk's unanswered jobs with it: they run again, half at a time, until only
	# the job that kills it is left)
	if len(jobs) > 1 and len(answers) < len(jobs):
		half = len(jobs) // 2
		return run_jobs(jobs[:half], ree, workers, warnings, actor) + run_jobs(jobs[half:], ree, workers, warnings, actor)
	results = []
	for index, job in enumerate(jobs):
		entry = answers.get(str(index)) or {}
		failure = entry.get("error") or result.stderr or stdout or "no result"
		results.append({"context": job["context"], **result_of(entry.get("summary"), failure, inActor[index])})
	if warnings:
		# (luau-lsp reads what ree runs, each script in its function, and its lines are mapped back: a module and the script
		# after it are two scripts, not one file with code after a return)
		analyzed = [job["code"] if inActor[index] else made[index][0] for index, job in enumerate(jobs)]
		for index, found in enumerate(static_warnings(analyzed)):
			where = list(range(jobs[index]["code"].count("\n") + 1)) if inActor[index] else made[index][1]
			results[index]["warnings"] = remap(found, where)
	for result, job, (_, where) in zip(results, jobs, made):
		if "verdict" not in result:
			finish(result, job, where)
	return results


def remap(warnings: list[str], where: list[int]) -> list[str]:
	"""Warnings at harness lines, as at the code's lines (those at the harness's own lines dropped)."""
	mapped = []
	for warning in warnings:
		at = re.match(r"^(\d+):(\d+): (.*)$", warning, re.S)
		line = int(at[1]) - 1 if at else -1
		if at and 0 <= line < len(where) and where[line] >= 0:
			mapped.append(f"{where[line] + 1}:{at[2]}: {at[3]}")
	return mapped


def validate_rows(rows: list[dict], context: str, ree: str, workers: int | None = None, warnings: bool = True, actor: bool = False) -> list[dict]:
	"""Each row's result ({"code" or "blocks", "context"?, "hint"?, "earlier"?}), in order."""
	planned = [plan(row, context) for row in rows]
	flat = [job for jobs in planned for job in jobs]
	results = iter(run_jobs(flat, ree, workers, warnings, actor)) if flat else iter([])
	return [merge([next(results) for _ in jobs]) for jobs in planned]


def validate(code: str, context: str, ree: str, warnings: bool = True, actor: bool = False, hint: str = "") -> dict:
	return validate_rows([{"code": code, "hint": hint}], context, ree, None, warnings, actor)[0]


def validate_batch(source, out, context: str, ree: str, chunk: int, workers: int | None, warnings: bool, actor: bool) -> None:
	"""Reads rows (JSON lines) from source and writes each one's result line to out, a chunk at a time."""
	pending: list[dict] = []

	def flush() -> None:
		for row, result in zip(pending, validate_rows(pending, context, ree, workers, warnings, actor)):
			out.write(json.dumps({"id": row["id"], **result}) + "\n")
		out.flush()
		pending.clear()

	for number, line in enumerate(source, 1):
		if not line.strip():
			continue
		row = json.loads(line)
		row.setdefault("id", number)
		pending.append(row)
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

"""Runs one Luau file in ree and prints whether it worked, as JSON.

  python validator/validate.py path/to/Code.luau [--context server|client] [--ree target/release/ree.exe]

The file is the body of a script: it's wrapped as `return function(Context) ... end` and run for 1 second of game time.
Output: {"ok": bool, "errors": [...], "unemulated": [...]}. ok is false when the code raised anywhere (spawned threads and
event handlers included). unemulated lists the APIs ree reached but doesn't emulate yet: a run that touched one can't be
trusted, so ok is null there.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPORT_TYPE = re.compile(r"^(\s*)export\s+type", re.M)


def validate(code: str, context: str, ree: str) -> dict:
	with tempfile.TemporaryDirectory() as folder:
		harness = os.path.join(folder, "Block.luau")
		with open(harness, "w", encoding="utf-8") as harnessFile:
			harnessFile.write(f"return function(Context)\n{EXPORT_TYPE.sub(r'\1type', code)}\nend\n")
		result = subprocess.run([ree, "run", "--harness", harness, "--seconds", "1", "--script-timeout", "2", "--mode", "play", "--run-context", context],
			capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
	stdout = result.stdout
	try:
		summary = json.loads(stdout[stdout.index("{"):])
	except ValueError:
		return {"ok": None, "errors": [f"ree didn't run: {(result.stderr or stdout)[-400:]}"], "unemulated": []}
	output = summary.get("output") or []
	errors = [line["message"] for line in output if line.get("kind") == "error"]
	unemulated = [line["message"].split(" is not emulated")[0] for line in output if line.get("kind") == "missing"]
	ok = None if unemulated else not errors
	return {"ok": ok, "errors": errors, "unemulated": unemulated}


if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("file")
	parser.add_argument("--context", choices=["server", "client"], default="server")
	parser.add_argument("--ree", default=os.path.join(ROOT, "target", "release", "ree.exe"))
	args = parser.parse_args()
	sys.stdout.reconfigure(encoding="utf-8")
	print(json.dumps(validate(open(args.file, encoding="utf-8").read(), args.context, args.ree), indent=1))

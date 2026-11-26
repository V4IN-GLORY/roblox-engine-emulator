"""Lists every API ree still doesn't emulate, per run context, optionally filtered to some classes.

  python validator/probe/gaps.py [--classes Humanoid,ContextActionService] [--ree target/release/ree.exe]

Calls every script-callable function in the API dump with arguments built from its parameter types (StubProbe.luau,
regenerate with make_probe.py) and collects ree's `... is not emulated` lines: `missing` ones, and `stubbed` ones (a
method that answered a default of its return type, marked "(stubbed)"). A package is done when its classes print nothing
here (in the contexts Roblox allows them in).
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

parser = argparse.ArgumentParser()
parser.add_argument("--classes", default="")
parser.add_argument("--ree", default=os.path.join(ROOT, "target", "release", "ree.exe"))
args = parser.parse_args()
sys.stdout.reconfigure(encoding="utf-8")
wanted = {name for name in args.classes.split(",") if name}
if not os.path.exists(os.path.join(HERE, "StubProbe.luau")):
	subprocess.run([sys.executable, os.path.join(HERE, "make_probe.py")], check=True)
for context in ("server", "client"):
	result = subprocess.run([args.ree, "run", "--harness", os.path.join(HERE, "StubProbe.luau"), "--seconds", "1", "--script-timeout", "600", "--mode", "play", "--run-context", context],
		capture_output=True, text=True, encoding="utf-8", errors="replace")
	summary = json.loads(result.stdout[result.stdout.index("{"):])
	missing = sorted({line["message"].split(" is not emulated")[0] + ("" if line["kind"] == "missing" else " (stubbed)") for line in summary.get("output") or [] if line.get("kind") in ("missing", "stubbed")})
	missing = [member for member in missing if not wanted or member.split(".")[0] in wanted]
	print(f"{context}: {len(missing)} unemulated")
	for member in missing:
		print(f"  {member}")

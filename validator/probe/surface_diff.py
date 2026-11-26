"""Runs SurfaceProbe in ree and diffs it against the Roblox capture (validator/probe/expected/surface_<context>.txt).

  python validator/probe/surface_diff.py [--ree target/release/ree.exe] [--list <kind>] [--grep <text>]

Prints, per context, how many probe lines match Roblox and which kinds of line differ. --list prints the differing
lines of one kind (C class reach, E enums, V values, "M r" reads, "M w" writes, "M c0" calls with no args, "M cw" calls
with a wrong-typed first arg) as Roblox/ree pairs. A new capture comes from a Studio playtest (surface.luau pack/unpack).
"""
import argparse
import collections
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def line_key(line: str) -> str:
	words = line.split(" ")
	return " ".join(words[:3]) if words[0] in ("M", "V") else " ".join(words[:2])


def line_kind(key: str) -> str:
	words = key.split(" ")
	return f"M {words[2]}" if words[0] == "M" else words[0]


def lines_by_key(lines: list[str]) -> dict[str, str]:
	return {line_key(line): line for line in lines if line and not line.startswith("#") and line != "{}"}


def unpublished_only_messages() -> list[str]:
	with open(os.path.join(HERE, "expected", "unpublished.txt"), encoding="utf-8") as file:
		return [line.strip() for line in file if line.strip() and not line.startswith("#")]


def ree_lines(ree: str, harness: str, context: str) -> list[str]:
	result = subprocess.run([ree, "run", "--harness", harness, "--seconds", "600", "--script-timeout", "600", "--mode", "play", "--run-context", context],
		capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT)
	summary = json.loads(result.stdout[result.stdout.index("{"):])
	return [line["message"].rstrip() for line in summary.get("output") or [] if line.get("kind") == "print"]


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--ree", default=os.path.join(ROOT, "target", "release", "ree.exe"))
	parser.add_argument("--list", default="")
	parser.add_argument("--grep", default="")
	args = parser.parse_args()
	sys.stdout.reconfigure(encoding="utf-8")
	skippedMessages = unpublished_only_messages()
	with tempfile.TemporaryDirectory() as folder:
		harness = os.path.join(folder, "SurfaceProbe.luau")
		subprocess.run(["lune", "run", "validator/probe/surface.luau", "harness", harness], check=True, cwd=ROOT)
		for context in ("server", "client"):
			with open(os.path.join(HERE, "expected", f"surface_{context}.txt"), encoding="utf-8") as file:
				roblox = lines_by_key(file.read().split("\n"))
			roblox = {key: line for key, line in roblox.items() if not any(message in line for message in skippedMessages)}
			ree =lines_by_key(ree_lines(args.ree, harness, context))
			differing = [key for key in roblox if ree.get(key) != roblox[key]]
			print(f"{context}: {len(roblox) - len(differing)}/{len(roblox)} match Roblox")
			for kind, count in sorted(collections.Counter(line_kind(key) for key in differing).items()):
				print(f"  {kind:5} {count}")
			for key in differing:
				if args.list and line_kind(key) != args.list:
					continue
				if args.grep and args.grep not in key:
					continue
				if args.list or args.grep:
					print(f"    roblox: {roblox[key]}\n    ree:    {ree.get(key, '(no line)')}")


if __name__ == "__main__":
	main()

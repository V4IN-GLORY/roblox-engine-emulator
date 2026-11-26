"""Writes validator/probe/surface_spec.json, the in-game API surface SurfaceProbe.luau checks, from the creator docs.

  git clone --depth 1 --filter=blob:none --sparse https://github.com/Roblox/creator-docs.git <dir>
  git -C <dir> sparse-checkout set content/en-us/reference/engine
  python validator/probe/make_surface_spec.py --docs <dir>/content/en-us/reference/engine

Only what the docs list counts (AppHandle and other internals aren't there), and only members a normal script may use
(security None). Whether a game script can really reach a class is measured by the probe, not decided here.
"""
import argparse
import json
import os

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
KIND_BY_SECTION = {"properties": "p", "methods": "m", "events": "e", "callbacks": "c"}
STRING_LIKE_TYPES = {"string", "Content", "ContentId", "number", "int", "int64", "float", "double"}
UNCALLABLE_TYPES = {"Variant", "Tuple", "any", "boolean", "bool"}


def load_folder(folder: str) -> list[dict]:
	documents = []
	for fileName in sorted(os.listdir(folder)):
		if fileName.endswith(".yaml"):
			with open(os.path.join(folder, fileName), encoding="utf-8") as file:
				documents.append(yaml.safe_load(file))
	return documents


def is_game_usable(entry: dict) -> bool:
	security = entry.get("security") or "None"
	if isinstance(security, dict):
		security = security.get("read", "None")
	return security == "None" and "NotScriptable" not in (entry.get("tags") or [])


def short_name(qualified: str) -> str:
	for separator in (":", "."):
		if separator in qualified:
			return qualified.split(separator, 1)[1]
	return qualified


def wrong_value_kind(method: dict) -> str:
	"""t: pass a table as the first argument, s: pass a string, "": don't call (no args, or any value fits)"""
	parameters = method.get("parameters") or []
	if not parameters or parameters[0]["name"] == "...":
		return ""
	firstType = parameters[0]["type"]
	if firstType.endswith("?") or firstType in UNCALLABLE_TYPES or "|" in firstType:
		return ""
	return "t" if firstType in STRING_LIKE_TYPES else "s"


def class_specs(classesFolder: str) -> list:
	documents = load_folder(classesFolder)
	creatable = {document["name"] for document in documents if "NotCreatable" not in (document.get("tags") or [])}
	specs = []
	for document in documents:
		tags = document.get("tags") or []
		flags = ("s" if "Service" in tags else "") + ("n" if "NotCreatable" in tags else "")
		members = []
		for section, kind in KIND_BY_SECTION.items():
			for member in document.get(section) or []:
				if not is_game_usable(member):
					continue
				if kind == "m":
					parameterTypes = [parameter["type"] for parameter in member.get("parameters") or [] if parameter["name"] != "..."]
					members.append([kind, short_name(member["name"]), wrong_value_kind(member), parameterTypes])
				else:
					members.append([kind, short_name(member["name"]), ""])
		descendants = [name for name in document.get("descendants") or [] if name in creatable][:3]
		specs.append([document["name"], flags, descendants, members])
	return specs


def value_specs(docs: str) -> list:
	specs = []
	for datatype in load_folder(os.path.join(docs, "datatypes")):
		for section in ("constructors", "constants", "functions"):
			for entry in datatype.get(section) or []:
				specs.append(["datatype", datatype["name"], short_name(entry["name"])])
	for library in load_folder(os.path.join(docs, "libraries")):
		for section in ("functions", "properties"):
			for entry in library.get(section) or []:
				libraryName, memberName = entry["name"].split(".", 1)
				specs.append(["library", libraryName, memberName])
	for globals in load_folder(os.path.join(docs, "globals")):
		for section in ("functions", "properties"):
			for entry in globals.get(section) or []:
				specs.append(["global", entry["name"], ""])
	return specs


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--docs", required=True)
	args = parser.parse_args()
	enums = [[enum["name"], [item["name"] for item in enum.get("items") or []]] for enum in load_folder(os.path.join(args.docs, "enums"))]
	with open(os.path.join(args.docs, "STUDIO_VERSION"), encoding="utf-8") as file:
		version = file.read().splitlines()[0].strip()
	with open(os.path.join(HERE, "expected", "crashes.txt"), encoding="utf-8") as file:
		crashingCalls = [line.strip() for line in file if line.strip() and not line.startswith("#")]
	spec = {"version": version, "classes": class_specs(os.path.join(args.docs, "classes")), "enums": enums, "values": value_specs(args.docs), "skipValidCalls": crashingCalls}
	with open(os.path.join(HERE, "surface_spec.json"), "w", encoding="utf-8") as file:
		json.dump(spec, file, separators=(",", ":"))
	memberCount = sum(len(classSpec[3]) for classSpec in spec["classes"])
	print(f"{version}: {len(spec['classes'])} classes, {memberCount} members, {len(enums)} enums, {len(spec['values'])} values")


if __name__ == "__main__":
	main()

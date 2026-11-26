"""Harness that calls every script-callable function with arguments synthesized from its parameter types, following
returned objects one level down, and reports calls that succeed but return nil for a non-optional return type."""
import json, os, sys


dump = {c["Name"]: c for c in json.load(open(os.path.join(os.path.dirname(__file__), "Full-API-Dump.json"), encoding="utf-8"))["Classes"]}
functions = {}
roots = []
for name, info in dump.items():
	tags = {tag for tag in info.get("Tags") or [] if isinstance(tag, str)}
	entries = []
	for member in info.get("Members", []):
		memberTags = {tag for tag in member.get("Tags") or [] if isinstance(tag, str)}
		security = member.get("Security")
		if member["MemberType"] != "Function" or memberTags & {"Deprecated", "Hidden", "NotScriptable"} or (security if isinstance(security, str) else security.get("Read")) != "None":
			continue
		returnType = member.get("ReturnType") or {}
		if isinstance(returnType, list):
			returnType = {"Name": "Tuple?"}  # several returns: nil can be legit
		parameters = [[parameter["Type"]["Name"], parameter["Type"].get("Category", ""), "Default" in parameter] for parameter in member.get("Parameters", [])]
		entries.append({"name": member["Name"], "params": parameters, "returns": returnType.get("Name", "null"), "returnCategory": returnType.get("Category", ""), "yields": "Yields" in memberTags})
	if entries:
		functions[name] = {"superclass": info.get("Superclass"), "functions": entries}
	if not tags & {"Deprecated", "NotBrowsable"}:
		if "Service" in tags or "NotCreatable" not in tags:
			roots.append([name, "Service" in tags])
lua = "local HttpService = game:GetService('HttpService')\nlocal FUNCTIONS = HttpService:JSONDecode([==[" + json.dumps(functions) + "]==])\nlocal ROOTS = HttpService:JSONDecode([==[" + json.dumps(roots) + "]==])\n" + open(os.path.join(os.path.dirname(__file__), "stub_probe_body.luau")).read()
open(os.path.join(os.path.dirname(__file__), "StubProbe.luau"), "w", encoding="utf-8").write(lua)
print(len(functions), "classes with functions", len(roots), "roots")

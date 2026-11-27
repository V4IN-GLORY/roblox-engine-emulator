"""Runs a package's specs: every *.ok.luau must pass, every *.bad.luau must fail, in the context its name says.

  python validator/specs/run.py <Package>     (names: Thing.ok.luau, Thing.bad.luau, Thing.client.ok.luau ...)

Context is server unless the file name has `.client.`. Prints only failures and a summary line.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from validate import ROOT, validate  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
package = sys.argv[1]
ree = os.path.join(ROOT, "target", "release", "ree.exe")
folder = os.path.join(HERE, package)
passed, failed = 0, 0
for name in sorted(os.listdir(folder)):
	if not name.endswith(".luau"):
		continue
	context = "client" if ".client." in name else "server"
	wantOk = ".ok." in name
	result = validate(open(os.path.join(folder, name), encoding="utf-8").read(), context, ree, warnings=False)
	if result["ok"] is wantOk:
		passed += 1
		continue
	failed += 1
	print(f"FAIL {name} ({context}): wanted ok={wantOk}, got {result}")
print(f"{package}: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

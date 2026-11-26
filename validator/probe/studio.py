"""Studio helpers for capturing SurfaceProbe without anyone clicking anything.

  python validator/probe/studio.py open     launch Studio (newest installed version) on an empty throwaway place
  python validator/probe/studio.py crash    the probe call running when Studio last died (from Studio's own log file)

The probe prints `PROBE-AT <call>` before each call when `_G.SurfaceProbeLog` is set, one call at a time, and Studio's log
file survives a crash, so its last marker names the call that took Studio down. Add it to expected/crashes.txt.
"""
import glob
import os
import subprocess
import sys
import tempfile

ROBLOX = os.path.join(os.environ["LOCALAPPDATA"], "Roblox")
PLACE_SCRIPT = """
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.Instance.new("DataModel")
local baseplate = roblox.Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Anchored = true
baseplate.Size = roblox.Vector3.new(512, 20, 512)
baseplate.Position = roblox.Vector3.new(0, -10, 0)
baseplate.Parent = game:GetService("Workspace")
local spawnLocation = roblox.Instance.new("SpawnLocation")
spawnLocation.Anchored = true
spawnLocation.Parent = game:GetService("Workspace")
fs.writeFile(PLACE_PATH, roblox.serializePlace(game))
"""


def newest(pattern: str) -> str:
	return max(glob.glob(pattern), key=os.path.getmtime)


def open_studio():
	folder = os.path.join(tempfile.gettempdir(), "ree-surface-probe")
	os.makedirs(folder, exist_ok=True)
	placePath = os.path.join(folder, "ProbePlace.rbxl")
	scriptPath = os.path.join(folder, "make_place.luau")
	with open(scriptPath, "w", encoding="utf-8") as file:
		file.write(PLACE_SCRIPT.replace("PLACE_PATH", repr(placePath.replace("\\", "/")).replace("'", '"')))
	subprocess.run(["lune", "run", scriptPath], check=True)
	studio = newest(os.path.join(ROBLOX, "Versions", "*", "RobloxStudioBeta.exe"))
	subprocess.Popen([studio, "-task", "EditFile", "-localPlaceFile", placePath], close_fds=True)
	print(f"opened {placePath}")


def last_crash():
	log = newest(os.path.join(ROBLOX, "logs", "*_Studio_*_last.log"))
	marker = None
	with open(log, encoding="utf-8", errors="replace") as file:
		for line in file:
			if "PROBE-AT " in line:
				marker = line.split("PROBE-AT ", 1)[1].strip()
	print(f"{os.path.basename(log)}: last call {marker}")


if __name__ == "__main__":
	{"open": open_studio, "crash": last_crash}[sys.argv[1]]()

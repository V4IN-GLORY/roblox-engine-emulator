-- lune: moves SurfaceProbe in and out of a Studio playtest as .rbxm files, so neither the spec nor the results pass
-- through an MCP call's text.
--   lune run validator/probe/surface.luau pack <out.rbxm>            Folder SurfaceProbe { Probe (ModuleScript), Report (RemoteEvent) }
--   lune run validator/probe/surface.luau unpack <in.rbxm> <outDir>  SurfaceResults' StringValues -> <outDir>/<name>.txt
--   lune run validator/probe/surface.luau harness <out.luau>         the same probe as a `ree run --harness` file
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local PROBE_FOLDER = "validator/probe"

local function Harness(): string
	local spec = fs.readFile(`{PROBE_FOLDER}/surface_spec.json`)
	local body = fs.readFile(`{PROBE_FOLDER}/SurfaceProbe.luau`)
	assert(not string.find(spec, "]=]", 1, true), "spec contains the long-string terminator")
	return `--!nocheck\nlocal SPEC = game:GetService("HttpService"):JSONDecode([=[{spec}]=])\nreturn function()\n{body}\nend\n`
end

local function Pack(outputPath: string)
	local folder = roblox.Instance.new("Folder")
	folder.Name = "SurfaceProbe"
	local probe = roblox.Instance.new("ModuleScript")
	probe.Name = "Probe"
	probe.Source = Harness()
	probe.Parent = folder
	local report = roblox.Instance.new("RemoteEvent")
	report.Name = "Report"
	report.Parent = folder
	fs.writeFile(outputPath, roblox.serializeModel({ folder }))
end

local function Unpack(inputPath: string, outputFolder: string)
	local roots = roblox.deserializeModel(fs.readFile(inputPath))
	fs.writeDir(outputFolder)
	local chunksByContext: { [string]: { [number]: string } } = {}
	for _, root in roots do
		for _, value in root:GetChildren() do
			if value.ClassName ~= "StringValue" then continue end
			local context, index = string.match(value.Name, "^(%a+)_(%d+)$") -- StringValue caps at 200000 chars, so results come in chunks
			chunksByContext[context] = chunksByContext[context] or {}
			chunksByContext[context][tonumber(index)] = value.Value
		end
	end
	for context, chunks in chunksByContext do
		local text = table.concat(chunks)
		fs.writeFile(`{outputFolder}/{context}.txt`, text)
		print(`{context}: {#string.split(text, "\n")} lines`)
	end
end

local function WriteReeHarness(outputPath: string)
	local probe = string.gsub(Harness(), "^%-%-!nocheck\n", "")
	fs.writeFile(outputPath, `return function(Context)\nlocal run = (function()\n{probe}\nend)()\nfor _, line in run() do print(line) end\nend\n`)
end

local command = process.args[1]
if command == "pack" then
	Pack(process.args[2])
elseif command == "unpack" then
	Unpack(process.args[2], process.args[3])
elseif command == "harness" then
	WriteReeHarness(process.args[2])
else
	error("usage: pack <out.rbxm> | unpack <in.rbxm> <outDir> | harness <out.luau>")
end

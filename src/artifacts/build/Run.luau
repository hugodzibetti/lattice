--!strict
-- Usage: lune run src/artifacts/build/Run.luau [dumpPath] [outPath]

local parseDump = require("@src/artifacts/build/parseDump")
local buildArtifact = require("@src/artifacts/build/buildArtifact")
local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local args = process.args
local dumpPath: string = "data/api-dump.json"
local outPath: string = "data/artifact.bin"

-- Parse CLI args: lune run Run.luau [dumpPath] [outPath]
-- Skip the first arg (script path)
local argIdx = 1
for i = 1, #args do
	if args[i] == "Run.luau" or args[i]:find("src/artifacts/build/Run.luau") then
		argIdx = i + 1
		break
	end
end

if args[argIdx] then
	dumpPath = args[argIdx]
end
if args[argIdx + 1] then
	outPath = args[argIdx + 1]
end

-- Read and parse dump
local ok, content = pcall(fs.readFile, dumpPath)
if not ok then
	error("Cannot open dump: " .. dumpPath .. " — " .. tostring(content))
end

local raw: any
local parseOk, parseErr = pcall(function()
	raw = serde.decode("json", content)
end)
if not parseOk then
	error("Failed to parse JSON: " .. tostring(parseErr))
end

-- Build pipeline
local classDefs = parseDump(raw)
local artifactBuf = buildArtifact(classDefs)

-- Write output
local ok2, writeErr = pcall(fs.writeFile, outPath, artifactBuf)
if not ok2 then
	error("Cannot write output: " .. outPath .. " — " .. tostring(writeErr))
end

-- Summary
local totalProps = 0
for _, cd in classDefs do
	totalProps += #cd.properties
end
print(string.format("Built artifact: %d classes, %d properties", #classDefs, totalProps))

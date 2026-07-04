--!strict
-- Usage: lune run src/artifacts/build/Run.luau [dumpPath] [outPath]

local parseDump = require("@src/artifacts/build/parseDump")
local buildArtifact = require("@src/artifacts/build/buildArtifact")
local process = require("@lune/process")

-- Minimal JSON parser for Roblox API dumps.
-- Handles: objects, arrays, strings, numbers, true/false/null.
local function jsonDecode(json: string): any
	local pos = 1
	local len = #json

	local function skipWhitespace()
		while pos <= len do
			local ch = json:sub(pos, pos)
			if ch == " " or ch == "\n" or ch == "\r" or ch == "\t" then
				pos += 1
			else
				break
			end
		end
	end

	local function parseValue(): any
		skipWhitespace()
		if pos > len then
			return nil
		end
		local ch = json:sub(pos, pos)
		if ch == "\"" then
			return parseString()
		elseif ch == "{" then
			return parseObject()
		elseif ch == "[" then
			return parseArray()
		elseif ch == "t" then
			pos += 4
			return true
		elseif ch == "f" then
			pos += 5
			return false
		elseif ch == "n" then
			pos += 4
			return nil
		else
			return parseNumber()
		end
	end

	local function parseString(): string
		pos += 1 -- skip opening "
		local parts: { string } = {}
		local start = pos
		while pos <= len do
			local ch = json:sub(pos, pos)
			if ch == "\\" then
				if pos > start then
					table.insert(parts, json:sub(start, pos - 1))
				end
				pos += 1
				local esc = json:sub(pos, pos)
				if esc == "\"" then
					table.insert(parts, "\"")
				elseif esc == "\\" then
					table.insert(parts, "\\")
				elseif esc == "/" then
					table.insert(parts, "/")
				elseif esc == "n" then
					table.insert(parts, "\n")
				elseif esc == "r" then
					table.insert(parts, "\r")
				elseif esc == "t" then
					table.insert(parts, "\t")
				elseif esc == "u" then
					local hex = json:sub(pos + 1, pos + 4)
					local codepoint = tonumber(hex, 16)
					if codepoint then
						table.insert(parts, utf8.char(codepoint))
					end
					pos += 4
				else
					table.insert(parts, esc)
				end
				pos += 1
				start = pos
			elseif ch == "\"" then
				if pos > start then
					table.insert(parts, json:sub(start, pos - 1))
				end
				pos += 1
				return table.concat(parts)
			else
				pos += 1
			end
		end
		error("Unterminated string")
	end

	local function parseNumber(): number
		local start = pos
		while pos <= len do
			local ch = json:sub(pos, pos)
			if ch:match("[%d%.%+%-eE]") then
				pos += 1
			else
				break
			end
		end
		return tonumber(json:sub(start, pos - 1)) :: number
	end

	local function parseObject(): { [string]: any }
		pos += 1 -- skip {
		local obj: { [string]: any } = {}
		skipWhitespace()
		if json:sub(pos, pos) == "}" then
			pos += 1
			return obj
		end
		while true do
			skipWhitespace()
			local key = parseString()
			skipWhitespace()
			pos += 1 -- skip :
			local value = parseValue()
			obj[key] = value
			skipWhitespace()
			local ch = json:sub(pos, pos)
			if ch == "," then
				pos += 1
			elseif ch == "}" then
				pos += 1
				break
			end
		end
		return obj
	end

	local function parseArray(): { any }
		pos += 1 -- skip [
		local arr: { any } = {}
		skipWhitespace()
		if json:sub(pos, pos) == "]" then
			pos += 1
			return arr
		end
		while true do
			local value = parseValue()
			table.insert(arr, value)
			skipWhitespace()
			local ch = json:sub(pos, pos)
			if ch == "," then
				pos += 1
			elseif ch == "]" then
				pos += 1
				break
			end
		end
		return arr
	end

	return parseValue()
end

local args = process.argv
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
local file, err = io.open(dumpPath, "r")
if not file then
	error("Cannot open dump: " .. dumpPath .. " — " .. (err or "unknown error"))
end
local content = file:read("*a")
file:close()

local raw: any
local parseOk, parseErr = pcall(function()
	raw = jsonDecode(content)
end)
if not parseOk then
	error("Failed to parse JSON: " .. tostring(parseErr))
end

-- Build pipeline
local classDefs = parseDump(raw)
local artifactBuf = buildArtifact(classDefs)

-- Write output
local outFile, outErr = io.open(outPath, "wb")
if not outFile then
	error("Cannot write output: " .. outPath .. " — " .. (outErr or "unknown error"))
end
outFile:write(artifactBuf)
outFile:close()

-- Summary
local totalProps = 0
for _, cd in classDefs do
	totalProps += #cd.properties
end
print(string.format("Built artifact: %d classes, %d properties", #classDefs, totalProps))

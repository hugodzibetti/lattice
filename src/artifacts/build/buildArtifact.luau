--!strict
--!native
--!optimize 2

-- Takes ClassDef[], builds ArtifactData, serializes to buffer.

local Writer = require("@src/buffer/Writer")
local serde = require("@src/serde")
local Types = require("@src/artifacts/types")
local resolveType = require("@src/artifacts/build/resolveType")
local getCodec = require("@src/artifacts/getCodec")

type ClassDef = Types.ClassDef
type PropertyDef = Types.PropertyDef
type PropertyMetadata = Types.PropertyMetadata
type ClassMetadata = Types.ClassMetadata

local roblox = require("@lune/roblox")

-- Properties that should never have their default elided.
local NEVER_ELIDE: { [string]: boolean } = {
	Name = true,
	UniqueId = true,
}

-- Parse a default value string into a native Luau value using @lune/roblox.
-- Returns nil if parsing fails (safe: property always serialized, never elided).
local function parseDefault(raw: string, prop: PropertyDef): any?
	local vt = prop.valueType

	-- Simple types
	if vt == "float" or vt == "double" or vt == "int64" or vt == "int" then
		return tonumber(raw)
	elseif vt == "bool" or vt == "boolean" then
		return raw == "true"
	elseif vt == "string" then
		if #raw >= 2 and raw:sub(1, 1) == "\"" and raw:sub(#raw, #raw) == "\"" then
			return raw:sub(2, #raw - 1)
		end
		return raw
	end

	-- Vector2: "x, y"
	if vt == "Vector2" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 2 then
			return roblox.Vector2.new(parts[1], parts[2])
		end
		return nil
	end

	-- Vector3: "x, y, z"
	if vt == "Vector3" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 3 then
			return roblox.Vector3.new(parts[1], parts[2], parts[3])
		end
		return nil
	end

	-- CFrame: 12 numbers (pos + rotation matrix)
	if vt == "CFrame" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 12 then
			-- CFrame.fromMatrix(pos, r00, r01, r02, r10, r11, r12, r20, r21, r22)
			local pos = roblox.Vector3.new(parts[1], parts[2], parts[3])
			return roblox.CFrame.fromMatrix(pos, parts[4], parts[5], parts[6], parts[7], parts[8], parts[9], parts[10], parts[11], parts[12])
		end
		return nil
	end

	-- Color3: "r, g, b" (0-1 range)
	if vt == "Color3" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 3 then
			return roblox.Color3.new(parts[1], parts[2], parts[3])
		end
		return nil
	end

	-- BrickColor: name string
	if vt == "BrickColor" then
		local ok, result = pcall(function()
			return roblox.BrickColor.new(raw)
		end)
		if ok then
			return result
		end
		return nil
	end

	-- UDim: "scale, offset"
	if vt == "UDim" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 2 then
			return roblox.UDim.new(parts[1], parts[2])
		end
		return nil
	end

	-- UDim2: "xScale, xOffset, yScale, yOffset"
	if vt == "UDim2" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 4 then
			return roblox.UDim2.new(parts[1], parts[2], parts[3], parts[4])
		end
		return nil
	end

	-- Rect: "minX, minY, maxX, maxY"
	if vt == "Rect" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 4 then
			return roblox.Rect.new(parts[1], parts[2], parts[3], parts[4])
		end
		return nil
	end

	-- Enum: numeric enum value
	if vt == "Enum" then
		return tonumber(raw)
	end

	-- NumberRange: "min, max"
	if vt == "NumberRange" then
		local parts = {}
		for part in raw:gmatch("[%d%.%-%+eE]+") do
			table.insert(parts, tonumber(part))
		end
		if #parts >= 2 then
			return roblox.NumberRange.new(parts[1], parts[2])
		end
		return nil
	end

	-- Content: path string
	if vt == "Content" then
		return roblox.Content.new(raw)
	end

	-- Font: similar to Content
	if vt == "Font" then
		return roblox.Font.new(raw)
	end

	-- UniqueId: never elided, but parse anyway
	if vt == "UniqueId" then
		return raw
	end

	-- Complex types: skip default parsing (safe — always serialized)
	-- ColorSequence, NumberSequence, PhysicalProperties, Axes, Faces
	return nil
end

-- Internal: serialize default value to bytes using its codec.
local function serializeDefault(value: any?, codecId: number, codecParams: { number }?): buffer
	if value == nil then
		return buffer.create(0)
	end
	local codec = getCodec(codecId, codecParams)
	if not codec then
		return buffer.create(0)
	end
	local ok, result = pcall(function()
		local w = Writer.new()
		codec.write(w, value)
		return w:toBuffer()
	end)
	if ok then
		return result :: buffer
	end
	return buffer.create(0)
end

local function buildArtifact(classDefs: { ClassDef }): buffer
	-- Sort alphabetically, assign sequential IDs starting from 1
	table.sort(classDefs, function(a: ClassDef, b: ClassDef): boolean
		return a.name < b.name
	end)

	local classNamesSet: { [string]: boolean } = {}
	for _, cd in classDefs do
		classNamesSet[cd.name] = true
	end

	local classMetas: { ClassMetadata } = {}
	local classId = 0

	for _, cd in classDefs do
		classId += 1
		local props: { PropertyMetadata } = {}

		for _, pd in cd.properties do
			local resolved = resolveType(pd, classNamesSet)
			if not resolved then
				warn(string.format("WARNING: %s.%s (%s) — no codec, skipping", cd.name, pd.name, pd.valueType))
				continue
			end

			local defaultVal: any? = nil
			if pd.hasDefault and pd.defaultRaw and not NEVER_ELIDE[pd.name] then
				defaultVal = parseDefault(pd.defaultRaw, pd)
			end

			table.insert(props, {
				name = pd.name,
				codecId = resolved.codecId,
				codecParams = resolved.codecParams,
				default = defaultVal,
			})
		end

		table.insert(classMetas, {
			id = classId,
			name = cd.name,
			properties = props,
		})
	end

	-- Serialize to binary
	local w = Writer.new()

	-- Magic: "LATA"
	w:u8(0x4C)
	w:u8(0x41)
	w:u8(0x54)
	w:u8(0x41)

	-- Version: u16 = 1
	w:u16(1)

	-- classCount
	w:varint(#classMetas)

	for _, cm in classMetas do
		w:varint(cm.id)
		w:string(cm.name)
		w:varint(#cm.properties)

		for _, pm in cm.properties do
			w:string(pm.name)
			w:varint(pm.codecId)

			local params = pm.codecParams or {}
			w:varint(#params)
			for _, p in params do
				w:varint(p)
			end

			local defaultBytes = serializeDefault(pm.default, pm.codecId, pm.codecParams)
			w:varint(buffer.len(defaultBytes))
			if buffer.len(defaultBytes) > 0 then
				w:bytes(defaultBytes)
			end
		end
	end

	return w:toBuffer()
end

return buildArtifact

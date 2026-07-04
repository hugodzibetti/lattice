--!strict
--!native
--!optimize 2

local Reader = require("@src/buffer/Reader")
local serde = require("@src/serde")
local Types = require("@src/artifacts/types")

type PropertyMetadata = Types.PropertyMetadata
type ClassMetadata = Types.ClassMetadata
type ArtifactData = Types.ArtifactData

local function getCodec(codecId: number, codecParams: { number }?): any?
	if codecId == 4 or codecId == 5 then
		local factory = serde.codecIdToFactory[codecId]
		if not factory or not codecParams or #codecParams == 0 then
			return nil
		end
		local innerCodec = serde.codecIdToModule[codecParams[1]]
		if not innerCodec then
			return nil
		end
		return factory(innerCodec)
	end
	return serde.codecIdToModule[codecId]
end

local function load(artifactBuffer: buffer): ArtifactData
	local r = Reader.new(artifactBuffer)

	-- Magic bytes: "LATA"
	local m0 = r:u8()
	local m1 = r:u8()
	local m2 = r:u8()
	local m3 = r:u8()
	assert(m0 == 0x4C and m1 == 0x41 and m2 == 0x54 and m3 == 0x41, "Invalid artifact magic bytes")

	-- Version
	local version = r:u16()
	assert(version == 1, "Unsupported artifact version: " .. tostring(version))

	local classCount = r:varint()
	local classes: { ClassMetadata } = {}
	local classByName: { [string]: ClassMetadata } = {}
	local classById: { [number]: ClassMetadata } = {}

	for _ = 1, classCount do
		local classId = r:varint()
		local className = r:string()
		local propCount = r:varint()
		local properties: { PropertyMetadata } = {}

		for _ = 1, propCount do
			local propName = r:string()
			local codecId = r:varint()

			local paramCount = r:varint()
			local codecParams: { number }? = nil
			if paramCount > 0 then
				codecParams = {}
				for __ = 1, paramCount do
					table.insert(codecParams :: { number }, r:varint())
				end
			end

			local defaultLen = r:varint()
			local defaultVal: any? = nil
			if defaultLen > 0 then
				local defaultBytes = r:bytes(defaultLen)
				local codec = getCodec(codecId, codecParams)
				if codec then
					local ok, val = pcall(function()
						local dr = Reader.new(defaultBytes)
						return codec.read(dr)
					end)
					if ok then
						defaultVal = val
					end
				end
			end

			table.insert(properties, {
				name = propName,
				codecId = codecId,
				codecParams = codecParams,
				default = defaultVal,
			})
		end

		local cm: ClassMetadata = {
			id = classId,
			name = className,
			properties = properties,
		}
		table.insert(classes, cm)
		classByName[className] = cm
		classById[classId] = cm
	end

	return {
		version = version,
		classes = classes,
		classByName = classByName,
		classById = classById,
	}
end

return {
	load = load,
}

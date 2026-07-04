--!strict

local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")

local resolveType = require("@src/artifacts/build/resolveType")
local parseDump = require("@src/artifacts/build/parseDump")
local buildArtifact = require("@src/artifacts/build/buildArtifact")
local Artifact = require("@src/artifacts/Artifact")
local Writer = require("@src/buffer/Writer")
local serde = require("@src/serde")

return function()
	test.suite("resolveType", function()
		test.case("leaf types map to correct codec IDs", function()
			local cases = {
				{ valueType = "float", expected = 0 },
				{ valueType = "double", expected = 1 },
				{ valueType = "int64", expected = 1 },
				{ valueType = "bool", expected = 2 },
				{ valueType = "boolean", expected = 2 },
				{ valueType = "string", expected = 3 },
				{ valueType = "CFrame", expected = 6 },
				{ valueType = "Color3", expected = 7 },
				{ valueType = "BrickColor", expected = 8 },
				{ valueType = "ColorSequence", expected = 9 },
				{ valueType = "NumberRange", expected = 11 },
				{ valueType = "NumberSequence", expected = 12 },
				{ valueType = "UDim", expected = 14 },
				{ valueType = "UDim2", expected = 15 },
				{ valueType = "Vector2", expected = 16 },
				{ valueType = "Vector3", expected = 17 },
				{ valueType = "Rect", expected = 18 },
				{ valueType = "Axes", expected = 19 },
				{ valueType = "Faces", expected = 20 },
				{ valueType = "PhysicalProperties", expected = 21 },
				{ valueType = "Font", expected = 22 },
				{ valueType = "Content", expected = 23 },
				{ valueType = "UniqueId", expected = 24 },
				{ valueType = "Enum", expected = 25 },
			}
			for _, c in cases do
				local result = resolveType({ valueType = c.valueType })
				check.equal(result.codecId, c.expected, "type: " .. c.valueType)
				check.equal(result.codecParams, nil, "type: " .. c.valueType)
			end
		end)

		test.case("Array factory resolves with inner type params", function()
			local result = resolveType({ valueType = "Array", valueTypeParams = { "float" } })
			check.equal(result.codecId, 4)
			check.equal(#result.codecParams, 1)
			check.equal(result.codecParams[1], 0)
		end)

		test.case("Optional factory resolves with inner type params", function()
			local result = resolveType({ valueType = "Optional", valueTypeParams = { "Vector3" } })
			check.equal(result.codecId, 5)
			check.equal(#result.codecParams, 1)
			check.equal(result.codecParams[1], 17)
		end)

		test.case("unknown type returns nil", function()
			local result = resolveType({ valueType = "UnknownType" })
			check.equal(result, nil)
		end)
	end)

	test.suite("parseDump", function()
		test.case("class with no superclass gets its own properties", function()
			local raw = {
				Classes = {
					{
						Name = "SimpleClass",
						Members = {
							{
								MemberType = "Property",
								Name = "Health",
								ValueType = { Name = "float" },
								Default = "100",
							},
							{
								MemberType = "Property",
								Name = "Active",
								ValueType = { Name = "bool" },
								Default = "false",
							},
						},
					},
				},
			}
			local result = parseDump(raw)
			check.equal(#result, 1)
			check.equal(result[1].name, "SimpleClass")
			check.equal(result[1].superclass, nil)
			check.equal(#result[1].properties, 2)
			check.equal(result[1].properties[1].name, "Active") -- alphabetical
			check.equal(result[1].properties[2].name, "Health")
		end)

		test.case("class with superclass inherits properties, ancestor first", function()
			local raw = {
				Classes = {
					{
						Name = "BaseClass",
						Members = {
							{
								MemberType = "Property",
								Name = "BaseProp",
								ValueType = { Name = "bool" },
							},
						},
					},
					{
						Name = "Derived",
						Superclass = "BaseClass",
						Members = {
							{
								MemberType = "Property",
								Name = "DerivedProp",
								ValueType = { Name = "float" },
							},
						},
					},
				},
			}
			local result = parseDump(raw)
			check.equal(#result, 2)

			local derived = result[1] -- alphabetical: BaseClass, Derived
			if result[2].name == "Derived" then
				derived = result[2]
			end
			check.equal(derived.name, "Derived")
			check.equal(#derived.properties, 2)
			check.equal(derived.properties[1].name, "BaseProp") -- inherited first
			check.equal(derived.properties[2].name, "DerivedProp")
		end)

		test.case("notScriptable properties are skipped", function()
			local raw = {
				Classes = {
					{
						Name = "Test",
						Members = {
							{
								MemberType = "Property",
								Name = "HiddenProp",
								ValueType = { Name = "bool" },
								Tags = { "notScriptable" },
							},
							{
								MemberType = "Property",
								Name = "VisibleProp",
								ValueType = { Name = "float" },
							},
						},
					},
				},
			}
			local result = parseDump(raw)
			check.equal(#result, 1)
			check.equal(#result[1].properties, 1)
			check.equal(result[1].properties[1].name, "VisibleProp")
		end)

		test.case("CanSave=false properties are skipped", function()
			local raw = {
				Classes = {
					{
						Name = "Test",
						Members = {
							{
								MemberType = "Property",
								Name = "SaveProp",
								ValueType = { Name = "bool" },
								Serialization = { CanSave = true, CanLoad = true },
							},
							{
								MemberType = "Property",
								Name = "NoSaveProp",
								ValueType = { Name = "float" },
								Serialization = { CanSave = false },
							},
						},
					},
				},
			}
			local result = parseDump(raw)
			check.equal(#result, 1)
			check.equal(#result[1].properties, 1)
			check.equal(result[1].properties[1].name, "SaveProp")
		end)

		test.case("non-Property members are skipped", function()
			local raw = {
				Classes = {
					{
						Name = "Test",
						Members = {
							{
								MemberType = "Function",
								Name = "DoSomething",
							},
							{
								MemberType = "Property",
								Name = "RealProp",
								ValueType = { Name = "float" },
							},
							{
								MemberType = "Event",
								Name = "OnChanged",
							},
						},
					},
				},
			}
			local result = parseDump(raw)
			check.equal(#result, 1)
			check.equal(#result[1].properties, 1)
			check.equal(result[1].properties[1].name, "RealProp")
		end)

		test.case("BinaryString is skipped, Instance value types are mapped to referent", function()
			local raw = {
				Classes = {
					{
						Name = "Test",
						Members = {
							{
								MemberType = "Property",
								Name = "SoundData",
								ValueType = { Name = "BinaryString" },
							},
							{
								MemberType = "Property",
								Name = "Child",
								ValueType = { Name = "Instance" },
							},
							{
								MemberType = "Property",
								Name = "GoodProp",
								ValueType = { Name = "string" },
							},
						},
					},
				},
			}
			local result = parseDump(raw)
			check.equal(#result, 1)
			check.equal(#result[1].properties, 2)
			check.equal(result[1].properties[1].name, "Child")
			check.equal(result[1].properties[2].name, "GoodProp")
		end)
	end)

	test.suite("Artifact round-trip", function()
		test.case("build and load with basic property types", function()
			local w = Writer.new()

			-- Magic
			w:u8(0x4C)
			w:u8(0x41)
			w:u8(0x54)
			w:u8(0x41)
			-- Version
			w:u16(1)
			-- classCount = 2
			w:varint(2)

			-- Class 1: id=1, name="Part"
			w:varint(1)
			w:string("Part")
			w:varint(2) -- 2 properties

			-- Prop: Anchored, codecId=2 (bool), no params, default=true
			local anchoredDefaultBuf = buffer.create(0)
			do
				local dw = Writer.new()
				serde.codecIdToModule[2].write(dw, true)
				anchoredDefaultBuf = dw:toBuffer()
			end
			w:string("Anchored")
			w:varint(2)
			w:varint(0) -- paramCount
			w:varint(buffer.len(anchoredDefaultBuf))
			w:bytes(anchoredDefaultBuf)

			-- Prop: Position, codecId=17 (Vector3), no params, default=0,0,0
			local posDefaultBuf = buffer.create(0)
			do
				local dw = Writer.new()
				serde.codecIdToModule[17].write(dw, roblox.Vector3.new(0, 0, 0))
				posDefaultBuf = dw:toBuffer()
			end
			w:string("Position")
			w:varint(17)
			w:varint(0)
			w:varint(buffer.len(posDefaultBuf))
			w:bytes(posDefaultBuf)

			-- Class 2: id=2, name="Model"
			w:varint(2)
			w:string("Model")
			w:varint(1) -- 1 property

			-- Prop: Scale, codecId=0 (f32), no params, default=1.0
			local scaleDefaultBuf = buffer.create(0)
			do
				local dw = Writer.new()
				serde.codecIdToModule[0].write(dw, 1.0)
				scaleDefaultBuf = dw:toBuffer()
			end
			w:string("Scale")
			w:varint(0)
			w:varint(0)
			w:varint(buffer.len(scaleDefaultBuf))
			w:bytes(scaleDefaultBuf)

			local artifactBuf = w:toBuffer()

			-- Load it back
			local artifact = Artifact.load(artifactBuf)

			check.equal(artifact.version, 1)
			check.equal(#artifact.classes, 2)

			-- Class "Part"
			local part = artifact.classByName["Part"]
			check.equal(part.id, 1)
			check.equal(#part.properties, 2)
			check.equal(part.properties[1].name, "Anchored")
			check.equal(part.properties[1].codecId, 2)
			check.equal(part.properties[1].default, true)
			check.equal(part.properties[1].codec, serde.codecIdToModule[2])

			check.equal(part.properties[2].name, "Position")
			check.equal(part.properties[2].codecId, 17)
			check.equal(part.properties[2].default, roblox.Vector3.new(0, 0, 0))
			check.equal(part.properties[2].codec, serde.codecIdToModule[17])

			-- Class "Model"
			local model = artifact.classByName["Model"]
			check.equal(model.id, 2)
			check.equal(#model.properties, 1)
			check.equal(model.properties[1].name, "Scale")
			check.equal(model.properties[1].codecId, 0)
			check.equal(model.properties[1].default, 1.0)
			check.equal(model.properties[1].codec, serde.codecIdToModule[0])

			-- classById lookups
			check.equal(artifact.classById[1].name, "Part")
			check.equal(artifact.classById[2].name, "Model")
		end)

		test.case("property with no default has nil default", function()
			local w = Writer.new()
			w:u8(0x4C)
			w:u8(0x41)
			w:u8(0x54)
			w:u8(0x41)
			w:u16(1)
			w:varint(1)

			w:varint(1)
			w:string("Empty")
			w:varint(1)

			w:string("Value")
			w:varint(0) -- f32
			w:varint(0) -- no params
			w:varint(0) -- no default

			local artifact = Artifact.load(w:toBuffer())
			check.equal(artifact.classes[1].properties[1].default, nil)
		end)

		test.case("array factory codec with params", function()
			local w = Writer.new()
			w:u8(0x4C)
			w:u8(0x41)
			w:u8(0x54)
			w:u8(0x41)
			w:u16(1)
			w:varint(1)

			w:varint(1)
			w:string("Test")
			w:varint(1)

			-- Array of float: codecId=4, params=[0]
			w:string("Values")
			w:varint(4)
			w:varint(1)
			w:varint(0) -- inner = f32
			w:varint(0) -- no default

			local artifact = Artifact.load(w:toBuffer())
			local prop = artifact.classes[1].properties[1]
			check.equal(prop.name, "Values")
			check.equal(prop.codecId, 4)
			check.equal(#prop.codecParams, 1)
			check.equal(prop.codecParams[1], 0)
		end)
	end)
end

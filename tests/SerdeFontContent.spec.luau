local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local font = require("@src/serde/font")
local content = require("@src/serde/content")

return function()
	test.suite("serde.font", function()
		test.case("round trip with non-default weight/style", function()
			local value = roblox.Font.new(
				"rbxasset://fonts/families/SourceSansPro.json",
				roblox.Enum.FontWeight.Bold,
				roblox.Enum.FontStyle.Italic
			)
			local w = Writer.new()
			font.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = font.read(r)
			check.equal(result.Family, value.Family)
			check.equal(result.Weight, value.Weight)
			check.equal(result.Style, value.Style)
		end)

		test.case("round trip with heavy weight (value 900, exceeds a u8)", function()
			local value = roblox.Font.new(
				"rbxasset://fonts/families/SourceSansPro.json",
				roblox.Enum.FontWeight.Heavy,
				roblox.Enum.FontStyle.Normal
			)
			local w = Writer.new()
			font.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = font.read(r)
			check.equal(result.Weight, value.Weight)
		end)

		test.case("round trip Arial Regular normal (most common real-world case)", function()
			local value = roblox.Font.new(
				"rbxasset://fonts/families/Arial.json",
				roblox.Enum.FontWeight.Regular,
				roblox.Enum.FontStyle.Normal
			)
			local w = Writer.new()
			font.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = font.read(r)
			check.equal(result.Family, value.Family)
			check.equal(result.Weight, value.Weight)
			check.equal(result.Style, value.Style)
		end)
	end)

	test.suite("serde.content", function()
		test.case("round trip Content.none", function()
			local value = roblox.Content.none
			local w = Writer.new()
			content.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = content.read(r)
			check.equal(result.SourceType, value.SourceType)
		end)

		test.case("round trip Content.fromUri", function()
			local value = roblox.Content.fromUri("rbxassetid://123456")
			local w = Writer.new()
			content.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = content.read(r)
			check.equal(result.SourceType, value.SourceType)
			check.equal(result.Uri, value.Uri)
		end)

		test.case("round trip Content.fromUri with empty URI", function()
			local value = roblox.Content.fromUri("")
			local w = Writer.new()
			content.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = content.read(r)
			check.equal(result.SourceType, value.SourceType)
			check.equal(result.Uri, value.Uri)
		end)

		test.case("error on unsupported Content SourceType (Object)", function()
			local mockContent = {
				SourceType = roblox.Enum.ContentSourceType.Object
			}
			local w = Writer.new()
			local success = pcall(function()
				content.write(w, mockContent :: any)
			end)
			check.equal(success, false)
		end)
	end)
end

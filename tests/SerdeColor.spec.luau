local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local color3 = require("@src/serde/color3")
local brickColor = require("@src/serde/brickColor")

local EPSILON = 1 / 255 + 1e-6

return function()
	test.suite("serde.color3", function()
		local function roundTrip(value: Color3): Color3
			local w = Writer.new()
			color3.write(w, value)
			local r = Reader.new(w:toBuffer())
			return color3.read(r)
		end

		test.case("pure black", function()
			local value = roblox.Color3.new(0, 0, 0)
			local result = roundTrip(value)
			check.is_true(math.abs(result.R - value.R) < EPSILON)
			check.is_true(math.abs(result.G - value.G) < EPSILON)
			check.is_true(math.abs(result.B - value.B) < EPSILON)
		end)

		test.case("pure white", function()
			local value = roblox.Color3.new(1, 1, 1)
			local result = roundTrip(value)
			check.is_true(math.abs(result.R - value.R) < EPSILON)
			check.is_true(math.abs(result.G - value.G) < EPSILON)
			check.is_true(math.abs(result.B - value.B) < EPSILON)
		end)

		test.case("distinct RGB channels", function()
			local value = roblox.Color3.new(0.2, 0.6, 0.9)
			local result = roundTrip(value)
			check.is_true(math.abs(result.R - value.R) < EPSILON)
			check.is_true(math.abs(result.G - value.G) < EPSILON)
			check.is_true(math.abs(result.B - value.B) < EPSILON)
		end)
	end)

	test.suite("serde.brickColor", function()
		local function roundTrip(value: BrickColor): BrickColor
			local w = Writer.new()
			brickColor.write(w, value)
			local r = Reader.new(w:toBuffer())
			return brickColor.read(r)
		end

		test.case("Really red", function()
			local value = roblox.BrickColor.new("Really red")
			local result = roundTrip(value)
			check.equal(result.Number, value.Number)
		end)

		test.case("Institutional white", function()
			local value = roblox.BrickColor.new("Institutional white")
			local result = roundTrip(value)
			check.equal(result.Number, value.Number)
		end)

		test.case("palette boundary and fallback cases", function()
			local cases = {
				roblox.BrickColor.new(1),
				roblox.BrickColor.new(1032),
				roblox.BrickColor.new(194),
			}
			for _, value in cases do
				local result = roundTrip(value)
				check.equal(result.Number, value.Number)
			end
		end)
	end)
end

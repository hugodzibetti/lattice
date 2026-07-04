local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local Types = require("@src/types")
local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local array = require("@src/serde/array")

local numberCodec: Types.Codec<number> = {
	write = function(writer, value)
		writer:f64(value)
	end,
	read = function(reader)
		return reader:f64()
	end,
}

local function roundTrip<T>(codec: Types.Codec<T>, value: T): T
	local w = Writer.new()
	codec.write(w, value)
	local r = Reader.new(w:toBuffer())
	return codec.read(r)
end

return function()
	test.suite("serde.array", function()
		local numberArray = array(numberCodec)

		test.case("empty array round trip", function()
			local result = roundTrip(numberArray, {})
			check.equal(#result, 0)
		end)

		test.case("single-element array round trip", function()
			local result = roundTrip(numberArray, { 42 })
			check.equal(#result, 1)
			check.equal(result[1], 42)
		end)

		test.case("multi-element array preserves order, negatives, fractions", function()
			local value = { -5.5, 0, 3.25, 100 }
			local result = roundTrip(numberArray, value)
			check.equal(#result, #value)
			for i, v in value do
				check.equal(result[i], v)
			end
		end)

		test.case("large array with 128+ elements (varint boundary)", function()
			local value = table.create(150, 4.5)
			local result = roundTrip(numberArray, value)
			check.equal(#result, #value)
			for i, v in value do
				check.equal(result[i], v)
			end
		end)

		test.case("composes with itself: array of arrays", function()
			local nested = array(numberArray)
			local value = { { 1, 2 }, {}, { 3 } }
			local result = roundTrip(nested, value)
			check.equal(#result, #value)
			for i, inner in value do
				check.equal(#result[i], #inner)
				for j, v in inner do
					check.equal(result[i][j], v)
				end
			end
		end)
	end)
end

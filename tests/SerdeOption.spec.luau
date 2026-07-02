local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local Types = require("@src/types")
local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local option = require("@src/serde/option")

local numberCodec: Types.Codec<number> = {
	write = function(writer, value)
		writer:f64(value)
	end,
	read = function(reader)
		return reader:f64()
	end,
}

return function()
	test.suite("serde.option", function()
		local optionalNumber = option(numberCodec)

		test.case("nil round trip", function()
			local w = Writer.new()
			optionalNumber.write(w, nil)
			local r = Reader.new(w:toBuffer())
			check.equal(optionalNumber.read(r), nil)
		end)

		test.case("present value round trip", function()
			local w = Writer.new()
			optionalNumber.write(w, 42)
			local r = Reader.new(w:toBuffer())
			check.equal(optionalNumber.read(r), 42)
		end)

		test.case("zero is not confused with nil", function()
			local w = Writer.new()
			optionalNumber.write(w, 0)
			local r = Reader.new(w:toBuffer())
			local result = optionalNumber.read(r)
			check.equal(result ~= nil, true)
			check.equal(result, 0)
		end)

		test.case("sequence of nil/present values keeps position in sync", function()
			local w = Writer.new()
			optionalNumber.write(w, nil)
			optionalNumber.write(w, 7)
			optionalNumber.write(w, nil)
			optionalNumber.write(w, 0)

			local r = Reader.new(w:toBuffer())
			check.equal(optionalNumber.read(r), nil)
			check.equal(optionalNumber.read(r), 7)
			check.equal(optionalNumber.read(r), nil)
			check.equal(optionalNumber.read(r), 0)
			check.equal(r:remaining(), 0)
		end)
	end)
end

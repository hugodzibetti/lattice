local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")

local f32 = require("@src/serde/f32")
local f64 = require("@src/serde/f64")
local boolCodec = require("@src/serde/bool")
local stringCodec = require("@src/serde/string")

return function()
	test.suite("serde.f32", function()
		test.case("round trip (zero, negative, large magnitude, fractional)", function()
			local values = { 0, -100.25, 1.5, 65536.0 }
			local w = Writer.new()
			for _, v in values do
				f32.write(w, v)
			end

			local r = Reader.new(w:toBuffer())
			for _, v in values do
				check.equal(f32.read(r), v)
			end
		end)

		test.case("round trip NaN, Inf, -Inf, -0", function()
			local w = Writer.new()
			f32.write(w, math.huge)
			f32.write(w, -math.huge)
			f32.write(w, -0)

			local r = Reader.new(w:toBuffer())
			check.equal(f32.read(r), math.huge)
			check.equal(f32.read(r), -math.huge)
			local negZero = f32.read(r)
			check.equal(negZero, 0)
			check.equal(1 / negZero, -math.huge)

			local wNan = Writer.new()
			f32.write(wNan, 0/0)
			local rNan = Reader.new(wNan:toBuffer())
			local nanResult = f32.read(rNan)
			check.is_true(nanResult ~= nanResult)
		end)
	end)

	test.suite("serde.f64", function()
		test.case("round trip (zero, negative, large magnitude, fractional)", function()
			local values = { 0, -123456.789, 1.5, 1e300 }
			local w = Writer.new()
			for _, v in values do
				f64.write(w, v)
			end

			local r = Reader.new(w:toBuffer())
			for _, v in values do
				check.equal(f64.read(r), v)
			end
		end)

		test.case("round trip NaN, Inf, -Inf, -0", function()
			local w = Writer.new()
			f64.write(w, math.huge)
			f64.write(w, -math.huge)
			f64.write(w, -0)

			local r = Reader.new(w:toBuffer())
			check.equal(f64.read(r), math.huge)
			check.equal(f64.read(r), -math.huge)
			local negZero = f64.read(r)
			check.equal(negZero, 0)
			check.equal(1 / negZero, -math.huge)

			local wNan = Writer.new()
			f64.write(wNan, 0/0)
			local rNan = Reader.new(wNan:toBuffer())
			local nanResult = f64.read(rNan)
			check.is_true(nanResult ~= nanResult)
		end)
	end)

	test.suite("serde.bool", function()
		test.case("round trip (true and false)", function()
			local w = Writer.new()
			boolCodec.write(w, true)
			boolCodec.write(w, false)

			local r = Reader.new(w:toBuffer())
			check.equal(boolCodec.read(r), true)
			check.equal(boolCodec.read(r), false)
		end)
	end)

	test.suite("serde.string", function()
		test.case("round trip (empty, short, unicode)", function()
			local values = { "", "hello", "héllo wörld 你好 🎉" }
			local w = Writer.new()
			for _, v in values do
				stringCodec.write(w, v)
			end

			local r = Reader.new(w:toBuffer())
			for _, v in values do
				check.equal(stringCodec.read(r), v)
			end
		end)
	end)
end

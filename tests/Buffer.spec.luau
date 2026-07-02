local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")

return function()
	test.suite("buffer.Writer/Reader", function()
		test.case("fixed-width round trip", function()
			local w = Writer.new()
			w:u8(255)
			w:u16(65535)
			w:u32(4294967295)
			w:i8(-128)
			w:i16(-32768)
			w:i32(-2147483648)
			w:f32(1.5)
			w:f64(0.1)
			w:bool(true)
			w:bool(false)

			local r = Reader.new(w:toBuffer())
			check.equal(r:u8(), 255)
			check.equal(r:u16(), 65535)
			check.equal(r:u32(), 4294967295)
			check.equal(r:i8(), -128)
			check.equal(r:i16(), -32768)
			check.equal(r:i32(), -2147483648)
			check.equal(r:f32(), 1.5)
			check.equal(r:f64(), 0.1)
			check.equal(r:bool(), true)
			check.equal(r:bool(), false)
		end)

		test.case("varint round trip (small and large)", function()
			local values = { 0, 1, 127, 128, 300, 16384, 2097151, 2097152, 268435455, 999999999 }
			local w = Writer.new()
			for _, v in values do
				w:varint(v)
			end

			local r = Reader.new(w:toBuffer())
			for _, v in values do
				check.equal(r:varint(), v)
			end
		end)

		test.case("varintSigned round trip (positive, negative, zero)", function()
			local values = { 0, 1, -1, 63, -63, 1000, -1000, 1000000, -1000000 }
			local w = Writer.new()
			for _, v in values do
				w:varintSigned(v)
			end

			local r = Reader.new(w:toBuffer())
			for _, v in values do
				check.equal(r:varintSigned(), v)
			end
		end)

		test.case("string round trip", function()
			local w = Writer.new()
			w:string("")
			w:string("hello")
			w:string("a much longer string that forces the writer to grow its backing buffer more than once, hopefully")

			local r = Reader.new(w:toBuffer())
			check.equal(r:string(), "")
			check.equal(r:string(), "hello")
			check.equal(
				r:string(),
				"a much longer string that forces the writer to grow its backing buffer more than once, hopefully"
			)
		end)

		test.case("grows past initial capacity without corrupting prior writes", function()
			local w = Writer.new(1)
			for i = 1, 500 do
				w:varint(i)
			end

			local r = Reader.new(w:toBuffer())
			for i = 1, 500 do
				check.equal(r:varint(), i)
			end
		end)

		test.case("bytes round trip", function()
			local raw = buffer.create(4)
			buffer.writeu32(raw, 0, 12345)

			local w = Writer.new()
			w:bytes(raw)

			local r = Reader.new(w:toBuffer())
			local out = r:bytes(4)
			check.equal(buffer.readu32(out, 0), 12345)
		end)

		test.case("mixed sequence preserves order and position tracking", function()
			local w = Writer.new()
			w:varint(3)
			w:string("abc")
			w:f32(2.5)
			w:bool(true)

			local r = Reader.new(w:toBuffer())
			check.equal(r:varint(), 3)
			check.equal(r:string(), "abc")
			check.equal(r:f32(), 2.5)
			check.equal(r:bool(), true)
			check.equal(r:remaining(), 0)
		end)
	end)
end

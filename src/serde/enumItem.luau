--!strict
--!native
--!optimize 2

local Types = require("@src/types")
local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")

local codec: Types.Codec<number> = {
	write = function(writer: Writer.Writer, value: number)
		writer:varint(value)
	end,
	read = function(reader: Reader.Reader): number
		local n = reader:varint()
		assert(n ~= nil, "enumItem codec: read returned nil")
		return n
	end,
}

return codec

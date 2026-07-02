--!strict
--!native
--!optimize 2

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local types = require("@src/types")

local function option<T>(valueCodec: types.Codec<T>): types.Codec<T?>
	return {
		write = function(writer: Writer.Writer, value: T?)
			if value == nil then
				writer:bool(false)
			else
				writer:bool(true)
				valueCodec.write(writer, value)
			end
		end,
		read = function(reader: Reader.Reader): T?
			if reader:bool() then
				return valueCodec.read(reader)
			end
			return nil
		end,
	}
end

return option

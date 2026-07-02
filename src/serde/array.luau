--!strict
--!native
--!optimize 2

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local types = require("@src/types")

local function array<T>(elementCodec: types.Codec<T>): types.Codec<{ T }>
	return {
		write = function(writer: Writer.Writer, values: { T })
			writer:varint(#values)
			for _, value in values do
				elementCodec.write(writer, value)
			end
		end,
		read = function(reader: Reader.Reader): { T }
			local count = reader:varint()
			local result = table.create(count)
			for i = 1, count do
				result[i] = elementCodec.read(reader)
			end
			return result
		end,
	}
end

return array

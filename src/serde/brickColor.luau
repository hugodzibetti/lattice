--!strict
--!native
--!optimize 2

local roblox = require("@lune/roblox")

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local types = require("@src/types")

-- BrickColor's `.Number` is a stable palette index (small, usually 1-2 bytes
-- as a varint) that round-trips exactly through the numeric constructor.
local function write(writer: Writer.Writer, value: BrickColor)
	writer:varint(value.Number)
end

local function read(reader: Reader.Reader): BrickColor
	return roblox.BrickColor.new(reader:varint())
end

return {
	write = write,
	read = read,
} :: types.Codec<BrickColor>

--!strict
--!native
--!optimize 2

local roblox = require("@lune/roblox")
local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local types = require("@src/types")

local Font = roblox.Font
local FontWeight = roblox.Enum.FontWeight
local FontStyle = roblox.Enum.FontStyle

-- Lune's Enum has no `FromValue` lookup, so resolve by scanning. FontWeight
-- values go up to 900 (Heavy), so it needs a varint, not a u8; FontStyle only
-- has Normal/Italic and fits in a u8.
local function findByValue(enum: Enum, value: number): EnumItem
	for _, item in enum:GetEnumItems() do
		if item.Value == value then
			return item
		end
	end
	error(`no enum item on {tostring(enum)} with value {value}`)
end

local font: types.Codec<Font> = {
	write = function(writer: Writer.Writer, value: Font)
		writer:string(value.Family)
		writer:varint(value.Weight.Value)
		writer:u8(value.Style.Value)
	end,

	read = function(reader: Reader.Reader): Font
		local family = reader:string()
		local weight = findByValue(FontWeight, reader:varint())
		local style = findByValue(FontStyle, reader:u8())
		return Font.new(family, weight :: any, style :: any)
	end,
}

return font

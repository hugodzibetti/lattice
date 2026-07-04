--!strict
local Types = require("@src/format/types")
local Writer = require("@src/format/Writer")
local Reader = require("@src/format/Reader")

export type Encoding = Types.Encoding
export type PropertyColumn = Types.PropertyColumn
export type ClassBlock = Types.ClassBlock
export type FormatData = Types.FormatData

return {
	write = Writer.write,
	read = Reader.read,
}

--!strict

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local Serde = require("@src/serde/init")
local Types = require("@src/types")

export type Codec<T> = Types.Codec<T>
export type Writer = Writer.Writer
export type Reader = Reader.Reader
export type SerdeRegistry = Serde.SerdeRegistry

return {
	Writer = Writer,
	Reader = Reader,
	serde = Serde,
}

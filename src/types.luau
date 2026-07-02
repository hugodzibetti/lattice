--!strict

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")

-- Shared codec interface implemented by every module in serde/. Default-value
-- elision is the instance layer's job (plain `value == artifactDefault`), so
-- codecs only need to move values in and out of the wire format.
export type Codec<T> = {
	write: (writer: Writer.Writer, value: T) -> (),
	read: (reader: Reader.Reader) -> T,
}

return {}

--!strict
local Serializer = require("@src/instance/Serializer")
local Deserializer = require("@src/instance/Deserializer")

return {
	serialize = Serializer.serialize,
	deserialize = Deserializer.deserialize,
}

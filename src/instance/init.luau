--!strict
local Serializer = require("@src/instance/Serializer")
local Deserializer = require("@src/instance/Deserializer")

return {
	serialize = Serializer.serialize,
	serializeParallel = Serializer.serializeParallel,
	serializeAuto = Serializer.serializeAuto,
	deserialize = Deserializer.deserialize,
	deserializeParallel = Deserializer.deserializeParallel,
	deserializeAuto = Deserializer.deserializeAuto,
}

--!strict
local serde = require("@src/serde")

local function getCodec(codecId: number, codecParams: { number }?): any?
	if codecId == 4 or codecId == 5 then
		local factory = serde.codecIdToFactory[codecId]
		if not factory or not codecParams or #codecParams == 0 then
			return nil
		end
		local innerCodec = serde.codecIdToModule[codecParams[1]]
		if not innerCodec then
			return nil
		end
		return factory(innerCodec)
	end
	return serde.codecIdToModule[codecId]
end

return getCodec

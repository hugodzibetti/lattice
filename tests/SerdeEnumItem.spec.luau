local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local enumItem = require("@src/serde/enumItem")

return function()
	test.suite("serde.enumItem", function()
		test.case("round trips Material values", function()
			local values = { roblox.Enum.Material.Plastic.Value, roblox.Enum.Material.Wood.Value, roblox.Enum.Material.Neon.Value }
			for _, value in values do
				local w = Writer.new()
				enumItem.write(w, value)
				local r = Reader.new(w:toBuffer())
				check.equal(enumItem.read(r), value)
			end
		end)

		test.case("round trips value = 0", function()
			local value = roblox.Enum.HumanoidStateType.FallingDown.Value
			check.equal(value, 0)
			local w = Writer.new()
			enumItem.write(w, value)
			local r = Reader.new(w:toBuffer())
			check.equal(enumItem.read(r), value)
		end)
	end)
end

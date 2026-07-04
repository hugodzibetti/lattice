local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local referent = require("@src/serde/referent")

return function()
	test.suite("serde.referent", function()
		test.case("round trips global ID values", function()
			local values = { 0, 1, 127, 128, 500, 100000 }
			for _, value in values do
				local w = Writer.new()
				referent.write(w, value)
				local r = Reader.new(w:toBuffer())
				check.equal(referent.read(r), value)
			end
		end)
	end)
end

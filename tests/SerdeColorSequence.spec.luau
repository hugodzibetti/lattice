local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local colorSequenceKeypoint = require("@src/serde/colorSequenceKeypoint")
local colorSequence = require("@src/serde/colorSequence")

local EPSILON = 1 / 255 + 1e-6

local function checkColor(result: Color3, expected: Color3)
	check.is_true(math.abs(result.R - expected.R) < EPSILON)
	check.is_true(math.abs(result.G - expected.G) < EPSILON)
	check.is_true(math.abs(result.B - expected.B) < EPSILON)
end

local function checkKeypoints(
	result: { roblox.ColorSequenceKeypoint },
	expected: { roblox.ColorSequenceKeypoint }
)
	check.equal(#result, #expected)
	for i, expectedKeypoint in expected do
		check.equal(result[i].Time, expectedKeypoint.Time)
		checkColor(result[i].Value, expectedKeypoint.Value)
	end
end

return function()
	test.suite("serde.colorSequenceKeypoint", function()
		test.case("round trip with a distinct color", function()
			local value = roblox.ColorSequenceKeypoint.new(0.5, roblox.Color3.new(0.2, 0.6, 0.9))
			local w = Writer.new()
			colorSequenceKeypoint.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = colorSequenceKeypoint.read(r)
			check.equal(result.Time, value.Time)
			checkColor(result.Value, value.Value)
		end)
	end)

	test.suite("serde.colorSequence", function()
		test.case("round trip with the minimal 2-keypoint case", function()
			local value = roblox.ColorSequence.new(roblox.Color3.new(1, 0, 0))
			local w = Writer.new()
			colorSequence.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = colorSequence.read(r)
			checkKeypoints(result.Keypoints, value.Keypoints)
		end)

		test.case("round trip with a 3-keypoint sequence", function()
			local value = roblox.ColorSequence.new({
				roblox.ColorSequenceKeypoint.new(0, roblox.Color3.new(1, 0, 0)),
				roblox.ColorSequenceKeypoint.new(0.5, roblox.Color3.new(0, 1, 0)),
				roblox.ColorSequenceKeypoint.new(1, roblox.Color3.new(0, 0, 1)),
			})
			local w = Writer.new()
			colorSequence.write(w, value)
			local r = Reader.new(w:toBuffer())
			local result = colorSequence.read(r)
			checkKeypoints(result.Keypoints, value.Keypoints)
		end)
	end)
end

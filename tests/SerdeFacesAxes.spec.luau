local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")

local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")
local faces = require("@src/serde/faces")
local axes = require("@src/serde/axes")

local function checkFaces(result: roblox.Faces, expected: roblox.Faces)
	check.equal(result.Top, expected.Top)
	check.equal(result.Bottom, expected.Bottom)
	check.equal(result.Left, expected.Left)
	check.equal(result.Right, expected.Right)
	check.equal(result.Front, expected.Front)
	check.equal(result.Back, expected.Back)
end

local function checkAxes(result: roblox.Axes, expected: roblox.Axes)
	check.equal(result.X, expected.X)
	check.equal(result.Y, expected.Y)
	check.equal(result.Z, expected.Z)
end

return function()
	test.suite("serde.faces", function()
		local function roundTrip(value: roblox.Faces): roblox.Faces
			local w = Writer.new()
			faces.write(w, value)
			local r = Reader.new(w:toBuffer())
			return faces.read(r)
		end

		test.case("no flags set", function()
			local value = roblox.Faces.new()
			checkFaces(roundTrip(value), value)
		end)

		test.case("all flags set", function()
			local value = roblox.Faces.new(
				roblox.Enum.NormalId.Top,
				roblox.Enum.NormalId.Bottom,
				roblox.Enum.NormalId.Left,
				roblox.Enum.NormalId.Right,
				roblox.Enum.NormalId.Front,
				roblox.Enum.NormalId.Back
			)
			checkFaces(roundTrip(value), value)
		end)

		test.case("partial combination", function()
			local value = roblox.Faces.new(roblox.Enum.NormalId.Top, roblox.Enum.NormalId.Right)
			checkFaces(roundTrip(value), value)
		end)
	end)

	test.suite("serde.axes", function()
		local function roundTrip(value: roblox.Axes): roblox.Axes
			local w = Writer.new()
			axes.write(w, value)
			local r = Reader.new(w:toBuffer())
			return axes.read(r)
		end

		test.case("no flags set", function()
			local value = roblox.Axes.new()
			checkAxes(roundTrip(value), value)
		end)

		test.case("all flags set", function()
			local value = roblox.Axes.new(roblox.Enum.Axis.X, roblox.Enum.Axis.Y, roblox.Enum.Axis.Z)
			checkAxes(roundTrip(value), value)
		end)

		test.case("partial combination", function()
			local value = roblox.Axes.new(roblox.Enum.Axis.X, roblox.Enum.Axis.Z)
			checkAxes(roundTrip(value), value)
		end)
	end)
end

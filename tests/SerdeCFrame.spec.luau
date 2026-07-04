local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")
local CFrameCodec = require("@src/serde/cframe")
local Writer = require("@src/buffer/Writer")
local Reader = require("@src/buffer/Reader")

local function roundTrip(cf: roblox.CFrame): roblox.CFrame
	local w = Writer.new()
	CFrameCodec.write(w, cf)
	local r = Reader.new(w:toBuffer())
	return CFrameCodec.read(r)
end

local SPECIAL_ROTATIONS = (function()
	local perms = {
		{ 1, 2, 3 },
		{ 1, 3, 2 },
		{ 2, 1, 3 },
		{ 2, 3, 1 },
		{ 3, 1, 2 },
		{ 3, 2, 1 },
	}

	local function permSign(perm)
		local inversions = 0
		for i = 1, 3 do
			for j = i + 1, 3 do
				if perm[i] > perm[j] then
					inversions += 1
				end
			end
		end
		return if inversions % 2 == 0 then 1 else -1
	end

	local rotations = {}
	for _, perm in perms do
		local pSign = permSign(perm)
		for s1 = -1, 1, 2 do
			for s2 = -1, 1, 2 do
				for s3 = -1, 1, 2 do
					if pSign * s1 * s2 * s3 == 1 then
						local signs = { s1, s2, s3 }
						local m = table.create(9, 0)
						for row = 1, 3 do
							m[(row - 1) * 3 + perm[row]] = signs[row]
						end
						table.insert(rotations, m)
					end
				end
			end
		end
	end
	return rotations
end)()

return function()
	test.suite("serde.cframe", function()
		test.case("identity CFrame round trips exactly", function()
			local cf = roblox.CFrame.new()
			local out = roundTrip(cf)
			check.equal(out == cf, true)
		end)

		test.case("position-only CFrame round trips exactly", function()
			local cf = roblox.CFrame.new(roblox.Vector3.new(12.5, -7, 300))
			local out = roundTrip(cf)
			check.equal(out == cf, true)
		end)

		test.case("axis-aligned 90-degree rotation round trips exactly", function()
			-- Construct CFrame with exact components (no math.rad/floating-point drift)
			local cf = roblox.CFrame.fromMatrix(
				roblox.Vector3.new(1, 2, 3),
				roblox.Vector3.new(1, 0, 0),
				roblox.Vector3.new(0, 0, 1),
				roblox.Vector3.new(0, -1, 0)
			)
			local out = roundTrip(cf)
			check.equal(out == cf, true)
		end)

		test.case("all 24 special rotations round trip and compress to 14 bytes", function()
			for _, m in SPECIAL_ROTATIONS do
				local cf = roblox.CFrame.new(1, 2, 3, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
				local w = Writer.new()
				CFrameCodec.write(w, cf)
				check.equal(w:len(), 14) -- 1 flag + 1 index + 12 position (3x f32)
				local out = roundTrip(cf)
				check.equal(out == cf, true)
			end
		end)

		test.case("arbitrary non-axis-aligned rotation round trips within tolerance", function()
			local cf = roblox.CFrame.new(roblox.Vector3.new(4, -5, 6))
				* roblox.CFrame.Angles(math.rad(37), math.rad(12), math.rad(58))
			local out = roundTrip(cf)

			local ox, oy, oz, or00, or01, or02, or10, or11, or12, or20, or21, or22 = out:GetComponents()
			local ex, ey, ez, er00, er01, er02, er10, er11, er12, er20, er21, er22 = cf:GetComponents()

			local components = {
				{ ox, ex },
				{ oy, ey },
				{ oz, ez },
				{ or00, er00 },
				{ or01, er01 },
				{ or02, er02 },
				{ or10, er10 },
				{ or11, er11 },
				{ or12, er12 },
				{ or20, er20 },
				{ or21, er21 },
				{ or22, er22 },
			}

			for _, pair in components do
				check.equal(math.abs(pair[1] - pair[2]) < 1e-4, true)
			end
		end)
	end)
end

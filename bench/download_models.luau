--!strict
--!native

local net = require("@lune/net")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local ASSET_IDS = {
	18417434485,
	132810230805035,
	119923183258507,
	102667935150963,
	8767718758,
}

local MODEL_NAMES = {
	"haunted-mansion-bear-alpha",
	"the-big-house",
	"big-town-map",
	"gm-big-city",
	"minecraft-map",
}

local OUTPUT_DIR = "bench/models"

local function downloadModel(assetId: number, name: string)
	local filename = `{OUTPUT_DIR}/{name}.rbxl`

	if fs.isFile(filename) then
		print(`✓ {name} already exists`)
		return true
	end

	print(`⬇ Downloading {name} (ID: {assetId})...`)

	-- Try multiple download endpoints
	local urls = {
		`https://assetdelivery.roblox.com/v1/asset/?id={assetId}`,
		`https://assetdelivery.roblox.com/v1/assetId/{assetId}`,
		`https://www.roblox.com/asset/?id={assetId}`,
	}

	local success = false
	local response = nil

	for _, url in urls do
		local s, r = pcall(function()
			return net.request({
				url = url,
				method = "GET",
			})
		end)

		if s and r and r.ok then
			success = true
			response = r
			break
		end
	end

	if not success or not response.ok then
		local reason = if response then tostring(response.statusCode) else "Network error"
		print(`✗ Failed to download {name}: {reason}`)
		return false
	end

	fs.writeFile(filename, response.body)
	print(`✓ Saved: {filename} ({#response.body} bytes)`)

	return true
end

print("\n" .. string.rep("=", 70))
print("DOWNLOADING REAL ROBLOX MODELS")
print(string.rep("=", 70) .. "\n")

if not fs.isDir(OUTPUT_DIR) then
	fs.writeDir(OUTPUT_DIR)
end

local downloaded = 0
for i, assetId in ASSET_IDS do
	if downloadModel(assetId, MODEL_NAMES[i]) then
		downloaded += 1
	end
	if i < #ASSET_IDS then
		print("")
	end
end

print("\n" .. string.rep("=", 70))
print(`Downloaded {downloaded}/{#ASSET_IDS} models`)
print(string.rep("=", 70))

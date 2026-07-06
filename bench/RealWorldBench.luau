--!strict
--!native
--!optimize 2

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Serializer = require("@src/instance/Serializer")
local FormatReader = require("@src/format/Reader")
local Artifact = require("@src/artifacts/Artifact")
local Timer = require("./Timer")

local function rf(min: number, max: number): number
	return min + math.random() * (max - min)
end

local function ri(min: number, max: number): number
	return math.floor(rf(min, max + 0.999))
end

-- Generate realistic model structures
local function generateBuilding(name: string, floors: number): roblox.Instance
	local model = roblox.Instance.new("Model")
	model.Name = name

	for floor = 1, floors do
		local floorPart = roblox.Instance.new("Part")
		floorPart.Name = "Floor_" .. tostring(floor)
		floorPart.Shape = roblox.Enum.PartType.Block
		floorPart.Material = roblox.Enum.Material.Concrete
		floorPart.Size = roblox.Vector3.new(100, 1, 100)
		floorPart.Position = roblox.Vector3.new(0, floor * 10, 0)
		floorPart.CanCollide = true
		floorPart.TopSurface = roblox.Enum.SurfaceType.Smooth
		floorPart.BottomSurface = roblox.Enum.SurfaceType.Smooth
		floorPart.Parent = model

		-- Add columns
		for x = -40, 40, 20 do
			for z = -40, 40, 20 do
				local column = roblox.Instance.new("Part")
				column.Name = "Column_" .. tostring(x) .. "_" .. tostring(z)
				column.Shape = roblox.Enum.PartType.Block
				column.Material = roblox.Enum.Material.Brick
				column.Size = roblox.Vector3.new(2, 10, 2)
				column.Position = roblox.Vector3.new(x, floor * 10 - 5, z)
				column.CanCollide = true
				column.Parent = model
			end
		end

		-- Add windows
		for i = 1, 4 do
			local window = roblox.Instance.new("Part")
			window.Name = "Window_" .. tostring(floor) .. "_" .. tostring(i)
			window.Shape = roblox.Enum.PartType.Block
			window.Material = roblox.Enum.Material.Glass
			window.Size = roblox.Vector3.new(8, 8, 0.5)
			window.Position = roblox.Vector3.new(40 - i * 15, floor * 10 + 4, 50)
			window.CanCollide = false
			window.Parent = model
		end
	end

	return model
end

local function generateScene(name: string): roblox.Instance
	local workspace = roblox.Instance.new("Model")
	workspace.Name = name

	-- Add terrain baseplate
	local baseplate = roblox.Instance.new("Part")
	baseplate.Name = "Baseplate"
	baseplate.Shape = roblox.Enum.PartType.Block
	baseplate.Material = roblox.Enum.Material.Grass
	baseplate.Size = roblox.Vector3.new(2048, 1, 2048)
	baseplate.Position = roblox.Vector3.new(0, -100, 0)
	baseplate.CanCollide = true
	baseplate.Parent = workspace

	-- Add multiple buildings
	for b = 1, 3 do
		local building = generateBuilding("Building_" .. tostring(b), 5 + b)
		-- Offset building's children
		for _, child in building:GetChildren() do
			if child:IsA("BasePart") then
				child.Position = child.Position + roblox.Vector3.new((b - 2) * 300, 0, 0)
			end
		end
		building.Parent = workspace
	end

	-- Add scattered trees
	for t = 1, 50 do
		local treePos = roblox.Vector3.new(rf(-800, 800), 0, rf(-800, 800))

		-- Trunk
		local trunk = roblox.Instance.new("Part")
		trunk.Name = "Tree_" .. tostring(t) .. "_Trunk"
		trunk.Shape = roblox.Enum.PartType.Cylinder
		trunk.Material = roblox.Enum.Material.Wood
		trunk.Size = roblox.Vector3.new(2, 8, 2)
		trunk.Position = treePos
		trunk.CanCollide = true
		trunk.TopSurface = roblox.Enum.SurfaceType.Smooth
		trunk.BottomSurface = roblox.Enum.SurfaceType.Smooth
		trunk.Parent = workspace

		-- Foliage
		local foliage = roblox.Instance.new("Part")
		foliage.Name = "Tree_" .. tostring(t) .. "_Foliage"
		foliage.Shape = roblox.Enum.PartType.Ball
		foliage.Material = roblox.Enum.Material.Neon
		foliage.Size = roblox.Vector3.new(15, 15, 15)
		foliage.Position = treePos + roblox.Vector3.new(0, 8, 0)
		foliage.CanCollide = false
		foliage.Color = roblox.Color3.new(0.2, 0.6, 0.1)
		foliage.Parent = workspace
	end

	-- Add props and decorations
	for p = 1, 100 do
		local prop = roblox.Instance.new("Part")
		prop.Name = "Prop_" .. tostring(p)
		prop.Shape = if ri(1, 2) == 1 then roblox.Enum.PartType.Block else roblox.Enum.PartType.Ball
		prop.Material = if ri(1, 3) == 1 then roblox.Enum.Material.Metal else roblox.Enum.Material.Plastic
		prop.Size = roblox.Vector3.new(rf(1, 5), rf(1, 5), rf(1, 5))
		prop.Position = roblox.Vector3.new(rf(-1000, 1000), rf(0, 50), rf(-1000, 1000))
		prop.CanCollide = true
		prop.Color = roblox.Color3.new(rf(0, 1), rf(0, 1), rf(0, 1))
		prop.CFrame = roblox.CFrame.new(prop.Position) * roblox.CFrame.Angles(
			math.rad(rf(0, 360)),
			math.rad(rf(0, 360)),
			math.rad(rf(0, 360))
		)
		prop.Parent = workspace
	end

	return workspace
end

local function generateLargeScene(name: string): roblox.Instance
	local workspace = roblox.Instance.new("Model")
	workspace.Name = name

	-- Baseplate
	local baseplate = roblox.Instance.new("Part")
	baseplate.Name = "Baseplate"
	baseplate.Shape = roblox.Enum.PartType.Block
	baseplate.Material = roblox.Enum.Material.Grass
	baseplate.Size = roblox.Vector3.new(4096, 1, 4096)
	baseplate.Position = roblox.Vector3.new(0, -100, 0)
	baseplate.CanCollide = true
	baseplate.Parent = workspace

	-- Add a grid of small buildings
	for bx = 1, 10 do
		for bz = 1, 10 do
			local building = generateBuilding("Building_" .. tostring(bx) .. "_" .. tostring(bz), 3 + ri(1, 4))
			local offset = roblox.Vector3.new((bx - 5) * 400, 0, (bz - 5) * 400)
			for _, child in building:GetChildren() do
				if child:IsA("BasePart") then
					child.Position = child.Position + offset
				end
			end
			building.Parent = workspace
		end
	end

	-- Add scattered objects
	for o = 1, 500 do
		local obj = roblox.Instance.new("Part")
		obj.Name = "Object_" .. tostring(o)
		obj.Shape = if ri(1, 3) == 1 then roblox.Enum.PartType.Cylinder else roblox.Enum.PartType.Block
		obj.Material = roblox.Enum.Material.Plastic
		obj.Size = roblox.Vector3.new(rf(0.5, 3), rf(0.5, 3), rf(0.5, 3))
		obj.Position = roblox.Vector3.new(rf(-1500, 1500), rf(0, 100), rf(-1500, 1500))
		obj.CanCollide = true
		obj.Parent = workspace
	end

	return workspace
end

local function countInstances(model: roblox.Instance): number
	local count = 1
	for _, child in model:GetChildren() do
		count += countInstances(child)
	end
	return count
end

local function benchmark(name: string, model: roblox.Instance, artifactBuf: any)
	print("\n=== Benchmark: " .. name .. " ===")
	print("Instances: " .. tostring(countInstances(model)))

	local artifact = Artifact.load(artifactBuf)

	-- Measure serialization time
	local resultBuffer: buffer = nil
	local serializeTime = Timer.run(5, function()
		resultBuffer = Serializer.serialize({model}, artifact)
	end)

	local bytes = buffer.len(resultBuffer)

	-- Deserialize to verify round-trip
	local deserializeTime = Timer.run(5, function()
		FormatReader.read(resultBuffer, artifact)
	end)

	print("Serialization: " .. string.format("%.2f ms/op", (serializeTime.seconds / serializeTime.iterations) * 1000) .. " (" .. string.format("%.0f ops/s", serializeTime.opsPerSecond) .. ")")
	print("Deserialization: " .. string.format("%.2f ms/op", (deserializeTime.seconds / deserializeTime.iterations) * 1000) .. " (" .. string.format("%.0f ops/s", deserializeTime.opsPerSecond) .. ")")
	print("Binary size: " .. string.format("%d bytes (%.2f KB)", bytes, bytes / 1024))

	-- Write to file
	local filename = "bench/results/" .. name .. ".lattice"
	fs.writeFile(filename, buffer.tostring(resultBuffer))
	print("Saved to: " .. filename)

	return {
		name = name,
		instanceCount = countInstances(model),
		serializeTimeMs = (serializeTime.seconds / serializeTime.iterations) * 1000,
		serializeOpsPerSec = serializeTime.opsPerSecond,
		deserializeTimeMs = (deserializeTime.seconds / deserializeTime.iterations) * 1000,
		deserializeOpsPerSec = deserializeTime.opsPerSecond,
		sizeBytes = bytes,
		sizeKB = bytes / 1024,
	}
end

-- Main
local function run()
	math.randomseed(0)

	-- Ensure output directory
	fs.writeFile("bench/results/.gitkeep", "")

	-- Load artifact
	local artifactBuf = buffer.fromstring(fs.readFile("data/artifact.bin"))

	local results = {}

	-- Benchmark various model sizes
	table.insert(results, benchmark("tiny-scene", generateScene("TinyScene"), artifactBuf))
	table.insert(results, benchmark("large-scene", generateLargeScene("LargeScene"), artifactBuf))

	-- Print summary table
	print("\n\n=== SUMMARY ===")
	print("")
	local headers = { "Benchmark", "Instances", "Size (KB)", "Ser. (ms)", "Deser. (ms)", "Ser. Speed" }
	local rows: { { string } } = {}

	for _, result in results do
		table.insert(rows, {
			result.name,
			tostring(result.instanceCount),
			string.format("%.2f", result.sizeKB),
			string.format("%.2f", result.serializeTimeMs),
			string.format("%.2f", result.deserializeTimeMs),
			string.format("%.0f ops/s", result.serializeOpsPerSec),
		})
	end

	-- Simple table printer
	print(table.concat(headers, "  |  "))
	print(string.rep("-", 100))

	for _, row in rows do
		print(table.concat(row, "  |  "))
	end
end

run()

--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Lattice = require("@src")

local function assertEqual(a: any, b: any, msg: string)
	if a ~= b then
		print(string.format("ASSERTION FAILED: %s (Expected %s, got %s)", msg, tostring(b), tostring(a)))
		process.exit(1)
	end
end

print("Loading artifact...")
local artifactBuf = buffer.fromstring(fs.readFile("data/artifact.bin"))
local artifact = Lattice.loadArtifact(artifactBuf)
print("Artifact loaded successfully.")
local partMeta = artifact.classByName["Part"]
print("Part class properties in artifact:")
if partMeta then
	for _, p in partMeta.properties do
		if p.name == "Parent" or p.name == "Name" or p.name == "Anchored" then
			print(" - Property:", p.name, "codecId:", p.codecId, "default:", p.default)
		end
	end
else
	print("Part metadata not found!")
end

print("Constructing synthetic scene...")
local model = roblox.Instance.new("Model")
model.Name = "LatticeTestModel"
print("typeof(model) in Lune:", typeof(model))


local parts = {}
for i = 1, 5 do
	local part = roblox.Instance.new("Part")
	part.Name = "Part_" .. tostring(i)
	part.Anchored = (i % 2 == 0)
	part.Size = roblox.Vector3.new(i, i * 2, i * 3)
	part.Position = roblox.Vector3.new(i * 10, 1.5, 0)
	part.Material = if i % 2 == 0 then roblox.Enum.Material.Wood else roblox.Enum.Material.Plastic
	part.Parent = model
	table.insert(parts, part)
end

local roots = { model }

print("Serializing...")
local startTime = os.clock()
local buf = Lattice.serialize(roots, artifact)
local serializeTime = os.clock() - startTime
print(string.format("Serialized in %.3f ms, buffer size: %d bytes", serializeTime * 1000, buffer.len(buf)))

print("Deserializing...")
local deserializeStartTime = os.clock()
local decodedRoots = Lattice.deserialize(buf, artifact)
local deserializeTime = os.clock() - deserializeStartTime
print(string.format("Deserialized in %.3f ms", deserializeTime * 1000))

-- Verification
assertEqual(#decodedRoots, 1, "Roots count")
local decodedModel = decodedRoots[1]
assertEqual(decodedModel.ClassName, "Model", "Root class name")
assertEqual(decodedModel.Name, "LatticeTestModel", "Root name")

local decodedChildren = decodedModel:GetChildren()
assertEqual(#decodedChildren, 5, "Children count")

-- Sort decoded children by name to match parts
table.sort(decodedChildren, function(a, b)
	return a.Name < b.Name
end)

for i = 1, 5 do
	local orig = parts[i]
	local dec = decodedChildren[i]
	assertEqual(dec.ClassName, "Part", "Child class name")
	assertEqual(dec.Name, orig.Name, "Child name")
	assertEqual(dec.Anchored, orig.Anchored, "Child Anchored")
	assertEqual(dec.Size, orig.Size, "Child Size")
	assertEqual(dec.Position, orig.Position, "Child Position")
	assertEqual(dec.Material, orig.Material, "Child Material")
	assertEqual(dec.Parent, decodedModel, "Child Parent")
end

print("ROUND-TRIP SUCCESSFUL! All assertions passed.")

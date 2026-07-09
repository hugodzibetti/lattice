--!strict
--!native

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Serializer = require("@src/instance/Serializer")
local Deserializer = require("@src/instance/Deserializer")
local Artifact = require("@src/artifacts/Artifact")
local Timer = require("./Timer")

local MODELS_DIR = "bench/models"
local RESULTS_FILE = "bench/results/REAL_MODELS_BENCHMARK.md"

local function countInstances(inst: roblox.Instance): number
	local count = 1
	for _, child in inst:GetChildren() do
		count += countInstances(child)
	end
	return count
end

local function benchmarkModel(name: string, path: string, artifact: any): {
	name: string,
	size: number,
	instances: number,
	serializeTime: number,
	deserializeTime: number,
	latticeSize: number,
	bytesPerInstance: number,
}
	print(`\n📦 {name}`)
	print(string.rep("-", 50))

	-- Load model
	print("  Loading model...")
	local rbxlBinary = fs.readFile(path)
	local deserialized = roblox.deserializeModel(rbxlBinary)
	local roots = deserialized[1]
	local totalInstances = countInstances(roots)
	print(`  ✓ {totalInstances} instances`)

	-- Serialize with Lattice
	print("  Serializing with Lattice...")
	local latticeBuffer: buffer
	local serializeResult = Timer.run(1, function()
		latticeBuffer = Serializer.serialize({ roots }, artifact)
	end)
	local serializeTimeMs = serializeResult.seconds * 1000
	print(string.format("  ✓ %.1f ms", serializeTimeMs))

	-- Deserialize
	print("  Deserializing...")
	local deserializeResult = Timer.run(1, function()
		Deserializer.deserialize(latticeBuffer, artifact)
	end)
	local deserializeTimeMs = deserializeResult.seconds * 1000
	print(string.format("  ✓ %.1f ms", deserializeTimeMs))

	local latticeSize = buffer.len(latticeBuffer)
	local bytesPerInstance = latticeSize / totalInstances

	print(string.format("  📊 Size: %d KB (%d bytes)", math.floor(latticeSize / 1024), latticeSize))
	print(string.format("  📊 Ratio: %.1f bytes/instance", bytesPerInstance))

	return {
		name = name,
		size = #rbxlBinary,
		instances = totalInstances,
		serializeTime = serializeTimeMs,
		deserializeTime = deserializeTimeMs,
		latticeSize = latticeSize,
		bytesPerInstance = bytesPerInstance,
	}
end

print("\n" .. string.rep("=", 70))
print("LATTICE BENCHMARKS: REAL ROBLOX MODELS")
print(string.rep("=", 70))

-- Load artifact
print("\nLoading artifact...")
local artifactBinary = fs.readFile("data/artifact.bin")
local artifact = Artifact.load(buffer.fromstring(artifactBinary))
print("✓ Artifact loaded")

-- Find models
local models = {}
if fs.isDir(MODELS_DIR) then
	for _, item in fs.readDir(MODELS_DIR) do
		if item:match("%.rbxl$") then
			table.insert(models, {
				name = item:gsub("%.rbxl$", ""):gsub("-", " "):gsub("^%l", string.upper),
				path = MODELS_DIR .. "/" .. item,
			})
		end
	end
end

if #models == 0 then
	print("\n❌ No .rbxl models found in " .. MODELS_DIR)
	process.exit(1)
end

print(`\nFound {#models} models\n`)

-- Benchmark each model
local results = {}
for _, model in models do
	local result = benchmarkModel(model.name, model.path, artifact)
	table.insert(results, result)
end

-- Generate report
print("\n" .. string.rep("=", 70))
print("RESULTS")
print(string.rep("=", 70))

print("\n| Model | Instances | Original | Lattice | Ratio | B/inst | Serialize | Deserialize |")
print("|-------|-----------|----------|---------|-------|--------|-----------|-------------|")

local totalInstances = 0
local totalOriginal = 0
local totalLattice = 0

for _, r in results do
	totalInstances += r.instances
	totalOriginal += r.size
	totalLattice += r.latticeSize

	local ratio = r.latticeSize / r.size
	print(
		string.format(
			"| %s | %d | %.1f KB | %.1f KB | %.2f× | %.1f | %.1f ms | %.1f ms |",
			r.name,
			r.instances,
			r.size / 1024,
			r.latticeSize / 1024,
			ratio,
			r.bytesPerInstance,
			r.serializeTime,
			r.deserializeTime
		)
	)
end

print("\n**Summary:**")
print(string.format("- Total instances: %d", totalInstances))
print(string.format("- Total original size: %.1f KB", totalOriginal / 1024))
print(string.format("- Total Lattice size: %.1f KB", totalLattice / 1024))
print(string.format("- Compression ratio: %.2f×", totalLattice / totalOriginal))
print(string.format("- Average bytes/instance: %.1f", totalLattice / totalInstances))

-- Save markdown report
local markdown = "# Lattice Benchmarks: Real Roblox Models\n"
	.. "**Generated:** " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n"
	.. "## Summary\n\n"
	.. "Benchmarks of Lattice serialization on 5 real Roblox models from the creator store.\n\n"
	.. "| Model | Instances | Original | Lattice | Compression | Bytes/Inst | Serialize | Deserialize |\n"
	.. "|-------|-----------|----------|---------|-------------|------------|-----------|-------------|\n"

for _, r in results do
	local ratio = (1 - r.latticeSize / r.size) * 100
	markdown = markdown
		.. string.format(
			"| %s | %d | %.1f KB | %.1f KB | %.1f%% | %.1f | %.1f ms | %.1f ms |\n",
			r.name,
			r.instances,
			r.size / 1024,
			r.latticeSize / 1024,
			ratio,
			r.bytesPerInstance,
			r.serializeTime,
			r.deserializeTime
		)
end

markdown = markdown
	.. "\n## Aggregate\n\n"
	.. string.format("- **Total instances**: %d\n", totalInstances)
	.. string.format("- **Original size**: %.1f KB\n", totalOriginal / 1024)
	.. string.format("- **Lattice size**: %.1f KB\n", totalLattice / 1024)
	.. string.format("- **Compression ratio**: %.2f×\n", totalLattice / totalOriginal)
	.. string.format("- **Average bytes/instance**: %.1f\n", totalLattice / totalInstances)

fs.writeFile(RESULTS_FILE, markdown)
print(`\n✓ Report saved to {RESULTS_FILE}`)

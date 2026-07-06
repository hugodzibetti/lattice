--!strict
-- Standalone smoke test for Serializer.serializeParallel (src/instance/Serializer.luau).
-- Not wired into scripts/RunTests.luau/frktest: it spawns real `lune` child processes
-- per class block (via process.exec inside task.spawn), which doesn't fit frktest's
-- synchronous in-process unit-test model and depends on `lune` being on PATH plus
-- @alias resolution working for a spawned script - same reasoning as the existing
-- scripts/SmokeTestWorker.luau. Run directly instead:
--   lune run scripts/SmokeTestSerializeParallel.luau
--
-- (The real frktest coverage for this path, tests/ParallelIntegration.spec.luau, is a
-- separate follow-up task that also needs deserializeParallel to exist.)

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local serde = require("@src/serde")
local format = require("@src/format")
local instance = require("@src/instance")

local function fail(msg: string): never
	print("SMOKE TEST FAILED: " .. msg)
	process.exit(1)
end

-- Mock ArtifactData with two classes, mirroring the pattern used by
-- tests/Instance.spec.luau's mockArtifactWithParent.
local mockArtifact = {
	version = 1,
	classes = {},
	classByName = {},
	classById = {
		[1] = {
			id = 1,
			name = "Folder",
			properties = {
				{
					name = "Parent",
					codecId = 26,
					codec = serde.codecIdToModule[26],
					default = 0,
				},
			},
		},
		[2] = {
			id = 2,
			name = "Part",
			properties = {
				{
					name = "Parent",
					codecId = 26,
					codec = serde.codecIdToModule[26],
					default = 0,
				},
				{
					name = "Anchored",
					codecId = 2,
					codec = serde.codecIdToModule[2],
					default = false,
				},
				{
					name = "Position",
					codecId = 17,
					codec = serde.codecIdToModule[17],
					default = roblox.Vector3.new(0, 0, 0),
				},
			},
		},
	},
}
mockArtifact.classByName["Folder"] = mockArtifact.classById[1]
mockArtifact.classByName["Part"] = mockArtifact.classById[2]

-- Build a small scene: one Folder with three Part children, two classes total.
local folder = roblox.Instance.new("Folder")

local part1 = roblox.Instance.new("Part")
part1.Parent = folder
part1.Anchored = true
part1.Position = roblox.Vector3.new(1, 2, 3)

local part2 = roblox.Instance.new("Part")
part2.Parent = folder
part2.Anchored = false
part2.Position = roblox.Vector3.new(4, 5, 6)

local part3 = roblox.Instance.new("Part")
part3.Parent = folder
part3.Anchored = true
part3.Position = roblox.Vector3.new(0, 0, 0) -- default position, should be elided

print("Running serializeParallel...")
local buf = instance.serializeParallel({ folder }, mockArtifact :: any)
print("serializeParallel returned a buffer of length " .. tostring(buffer.len(buf)))

-- 1. Confirm it parses via format.read (raw FormatData, no instance reconstruction)
local decodedFormat = format.read(buf, mockArtifact :: any)
assert(decodedFormat.version == 4, "expected decoded version 4, got " .. tostring(decodedFormat.version))
assert(
	#decodedFormat.classBlocks == 2,
	"expected 2 class blocks (Folder, Part), got " .. tostring(#decodedFormat.classBlocks)
)

-- 2. Confirm Deserializer.deserialize reconstructs instances with expected values
local roots = instance.deserialize(buf, mockArtifact :: any)
assert(#roots == 1, "expected 1 root instance, got " .. tostring(#roots))

local decodedFolder = roots[1]
assert(decodedFolder.ClassName == "Folder", "expected root ClassName Folder, got " .. decodedFolder.ClassName)

local children = decodedFolder:GetChildren()
assert(#children == 3, "expected 3 children under Folder, got " .. tostring(#children))

local function findPartByPosition(pos: any): any?
	for _, child in children do
		if child.Position == pos then
			return child
		end
	end
	return nil
end

local decodedPart1 = findPartByPosition(roblox.Vector3.new(1, 2, 3))
local decodedPart2 = findPartByPosition(roblox.Vector3.new(4, 5, 6))
local decodedPart3 = findPartByPosition(roblox.Vector3.new(0, 0, 0))

if not decodedPart1 then
	fail("could not find decoded Part with Position (1, 2, 3)")
end
if not decodedPart2 then
	fail("could not find decoded Part with Position (4, 5, 6)")
end
if not decodedPart3 then
	fail("could not find decoded Part with Position (0, 0, 0)")
end

assert(decodedPart1.Anchored == true, "expected part1.Anchored == true")
assert(decodedPart2.Anchored == false, "expected part2.Anchored == false")
assert(decodedPart3.Anchored == true, "expected part3.Anchored == true")

assert(decodedPart1.Parent == decodedFolder, "expected part1.Parent == decodedFolder")
assert(decodedPart2.Parent == decodedFolder, "expected part2.Parent == decodedFolder")
assert(decodedPart3.Parent == decodedFolder, "expected part3.Parent == decodedFolder")

print("SMOKE TEST PASSED: serializeParallel produced a parseable v4 buffer that round-trips through deserialize()")
process.exit(0)

--!strict
-- Integration coverage for the parallel serialize/deserialize path
-- (src/instance/Serializer.luau's serializeParallel, src/instance/Deserializer.luau's
-- deserializeParallel), per docs/superpowers/specs/2026-07-05-parallel-encoding-design.md.
--
-- Unlike scripts/SmokeTestSerializeParallel.luau / SmokeTestDeserializeParallel.luau
-- (standalone scripts, not wired into frktest), this IS a real frktest spec wired into
-- scripts/RunTests.luau. It still spawns real `lune run src/parallel/Worker.luau` child
-- processes (same as the smoke tests) - that's unavoidable since serializeParallel/
-- deserializeParallel always do this, but it fits frktest fine because frktest's model
-- is synchronous test *functions*, not synchronous *implementations*; the blocking
-- process.exec calls just make each test.case take a bit longer.
--
-- The correctness bar (per the parallel-encoding design doc): parallel execution must
-- be a pure execution-strategy change, not a semantics change. So the core assertion
-- here is that Serializer.serialize and Serializer.serializeParallel produce
-- BYTE-IDENTICAL buffers for the same input scene - not just "equivalent when
-- decoded". Weakening this to a decoded-equivalence check would hide any bug where
-- the parallel path picks a different (but still valid) encoding, orders class blocks
-- differently, etc.

local frktest = require("@packages/frktest")
local test = frktest.test
local check = frktest.assert.check

local roblox = require("@lune/roblox")
local serde = require("@src/serde")
local instance = require("@src/instance")

-- Three classes: Folder (structural, Parent-only), Model (adds a PrimaryPart-less
-- non-default property via Position on a dummy proxy - keeping to simple properties
-- backed by existing test artifacts elsewhere), and Part (the bulk class, 20+
-- instances with repeated-but-shuffled property values to exercise Dictionary/RLE).
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
			name = "Model",
			properties = {
				{
					name = "Parent",
					codecId = 26,
					codec = serde.codecIdToModule[26],
					default = 0,
				},
			},
		},
		[3] = {
			id = 3,
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
					name = "Size",
					codecId = 17,
					codec = serde.codecIdToModule[17],
					default = roblox.Vector3.new(0, 0, 0),
				},
				{
					name = "Position",
					codecId = 17,
					codec = serde.codecIdToModule[17],
					default = roblox.Vector3.new(0, 0, 0),
				},
				{
					name = "Color",
					codecId = 7,
					codec = serde.codecIdToModule[7],
					default = roblox.Color3.new(0, 0, 0),
				},
			},
		},
	},
}
mockArtifact.classByName["Folder"] = mockArtifact.classById[1]
mockArtifact.classByName["Model"] = mockArtifact.classById[2]
mockArtifact.classByName["Part"] = mockArtifact.classById[3]

-- Builds a multi-class scene:
--   root Folder
--     - Model (non-default Parent already implied by hierarchy)
--       - 25 Parts: Anchored/Size/Color drawn from small shuffled palettes
--         (Dictionary/RLE bait), Position fully unique per instance (forces
--         Raw/AllNonDefault on that column so not every column collapses).
--     - 3 bare Parts directly under the Folder with all-default properties
--       (AllDefault bait) mixed with one fully non-default Part (AllNonDefault bait).
local function buildScene(): { any }
	local root = roblox.Instance.new("Folder")
	local model = roblox.Instance.new("Model")
	model.Parent = root

	local sizes = { roblox.Vector3.new(4, 1, 4), roblox.Vector3.new(2, 1, 2), roblox.Vector3.new(6, 1, 6) }
	local colors = { roblox.Color3.new(1, 0, 0), roblox.Color3.new(0, 1, 0), roblox.Color3.new(0, 0, 1) }

	for i = 1, 25 do
		local part = roblox.Instance.new("Part")
		part.Parent = model
		part.Anchored = (i % 2 == 0)
		part.Size = sizes[((i * 7) % #sizes) + 1] -- shuffled repeats -> Dictionary bait
		part.Color = colors[((i * 3) % #colors) + 1] -- different shuffle pattern
		part.Position = roblox.Vector3.new(i, i * 2, i * 3) -- fully unique
	end

	-- All-default Parts (bare, still get an implicit Parent). Properties are
	-- explicitly set to their artifact-declared default values rather than left
	-- untouched: Lune's roblox binding can only resolve a property's *actual*
	-- default for instances rooted under a DataModel, and errors ("missing
	-- default value") when reading a never-set property on a standalone
	-- Instance like these. PropertyCompare.computeSerializedValue treats that
	-- read failure as val = nil, which is not equal to the artifact's declared
	-- default (a Vector3/Color3/etc) - so an unset property here would be
	-- wrongly bucketed as non-default with a nil serialized value, not
	-- genuinely exercise the AllDefault encoding path this section is meant to
	-- cover.
	for _ = 1, 3 do
		local part = roblox.Instance.new("Part")
		part.Anchored = false
		part.Size = roblox.Vector3.new(0, 0, 0)
		part.Position = roblox.Vector3.new(0, 0, 0)
		part.Color = roblox.Color3.new(0, 0, 0)
		part.Parent = root
	end

	-- One fully-non-default Part directly under root
	local special = roblox.Instance.new("Part")
	special.Parent = root
	special.Anchored = true
	special.Size = roblox.Vector3.new(100, 100, 100)
	-- Exact 8-bit-representable channels (128/255, 64/255, 191/255) so the
	-- Color3->u8 quantization documented in CLAUDE.md ("Color quantization")
	-- round-trips bit-for-bit and this test isn't comparing against a value
	-- Roblox itself will have already rounded away.
	special.Color = roblox.Color3.fromRGB(128, 64, 191)
	special.Position = roblox.Vector3.new(-1, -2, -3)

	return { root }
end

local function collectAllSorted(roots: { any }): { any }
	local list = {}
	local visited = {}
	local function dfs(inst: any)
		if not inst or visited[inst] then
			return
		end
		visited[inst] = true
		table.insert(list, inst)
		for _, child in inst:GetChildren() do
			dfs(child)
		end
	end
	for _, root in roots do
		dfs(root)
	end
	return list
end

return function()
	test.suite("parallel.integration", function()
		test.case("serializeParallel produces a byte-identical buffer to serialize for a multi-class scene", function()
			local sceneA = buildScene()
			local sceneB = buildScene()

			local bufSeq = instance.serialize(sceneA, mockArtifact :: any)
			local bufPar = instance.serializeParallel(sceneB, mockArtifact :: any)

			check.equal(buffer.len(bufSeq), buffer.len(bufPar))
			check.equal(buffer.tostring(bufSeq), buffer.tostring(bufPar))
		end)

		test.case("deserialize and deserializeParallel reconstruct equivalent instance trees from the same buffer", function()
			local scene = buildScene()
			local buf = instance.serialize(scene, mockArtifact :: any)

			local seqRoots = instance.deserialize(buf, mockArtifact :: any)
			local parRoots = instance.deserializeParallel(buf, mockArtifact :: any)

			check.equal(#seqRoots, 1)
			check.equal(#parRoots, 1)

			local seqAll = collectAllSorted(seqRoots)
			local parAll = collectAllSorted(parRoots)
			check.equal(#seqAll, #parAll)

			-- Compare by (ClassName, Position) since Position is unique per Part and
			-- default (0,0,0) for the handful of non-Part/default instances - stable
			-- enough as a join key for this scene.
			local function keyOf(inst: any): string
				local posOk, pos = pcall(function()
					return inst.Position
				end)
				local posStr = if posOk then tostring(pos) else "n/a"
				return inst.ClassName .. "|" .. posStr
			end

			local parByKey: { [string]: { any } } = {}
			for _, inst in parAll do
				local k = keyOf(inst)
				local bucket = parByKey[k]
				if not bucket then
					bucket = {}
					parByKey[k] = bucket
				end
				table.insert(bucket, inst)
			end

			for _, seqInst in seqAll do
				local k = keyOf(seqInst)
				local bucket = parByKey[k]
				check.equal(bucket ~= nil and #bucket > 0, true)
				if bucket and #bucket > 0 then
					local parInst = table.remove(bucket) :: any
					check.equal(parInst.ClassName, seqInst.ClassName)
					if seqInst.ClassName == "Part" then
						check.equal(parInst.Anchored, seqInst.Anchored)
						check.equal(parInst.Size, seqInst.Size)
						check.equal(parInst.Color, seqInst.Color)
						check.equal(parInst.Position, seqInst.Position)
					end
				end
			end
		end)

		test.case("full round trip through the parallel path alone (serializeParallel -> deserializeParallel)", function()
			local scene = buildScene()
			local buf = instance.serializeParallel(scene, mockArtifact :: any)
			local roots = instance.deserializeParallel(buf, mockArtifact :: any)

			check.equal(#roots, 1)
			local newRoot = roots[1]
			check.equal(newRoot.ClassName, "Folder")

			local all = collectAllSorted(roots)
			-- 1 Folder + 1 Model + 25 Parts (under Model) + 3 default Parts + 1 special Part
			check.equal(#all, 1 + 1 + 25 + 3 + 1)

			local specialFound = false
			for _, inst in all do
				if inst.ClassName == "Part" and inst.Position == roblox.Vector3.new(-1, -2, -3) then
					specialFound = true
					check.equal(inst.Anchored, true)
					check.equal(inst.Size, roblox.Vector3.new(100, 100, 100))
					check.equal(inst.Color, roblox.Color3.fromRGB(128, 64, 191))
				end
			end
			check.equal(specialFound, true)
		end)
	end)
end

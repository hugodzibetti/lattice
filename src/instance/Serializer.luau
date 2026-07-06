--!strict
--!native
--!optimize 2

local roblox = require("@lune/roblox")
local process = require("@lune/process")
local task = require("@lune/task")
local Types = require("@src/types")
local ArtifactTypes = require("@src/artifacts/types")
local FormatTypes = require("@src/format/types")
local FormatWriter = require("@src/format/Writer")
local BufferWriter = require("@src/buffer/Writer")
local BufferReader = require("@src/buffer/Reader")
local PropertyCompare = require("@src/instance/PropertyCompare")
local ColumnEncoder = require("@src/instance/ColumnEncoder")

type ArtifactData = ArtifactTypes.ArtifactData
type ClassBlock = FormatTypes.ClassBlock
type PropertyColumn = FormatTypes.PropertyColumn
type FormatData = FormatTypes.FormatData

local function collectAll(roots: { any }): { any }
	local list = {}
	local visited = {}

	local function dfs(inst: any)
		if not inst or visited[inst] then
			return
		end
		visited[inst] = true
		table.insert(list, inst)

		local children = inst:GetChildren()
		for _, child in children do
			dfs(child)
		end
	end

	for _, root in roots do
		dfs(root)
	end

	return list
end

type ClassStageAResult = {
	className: string,
	classMeta: any,
	numBucket: number,
	propsWithCodec: { any },
	serializedByProp: { { any } },
	isDefaultByProp: { { boolean } },
}

-- Stage A (sequential, parent-only): everything that touches a live Instance --
-- collectAll, class bucketing, global-id assignment, and
-- PropertyCompare.computeSerializedValue per property. Shared by both the
-- sequential serialize() and the parallel serializeParallel() so this logic
-- (and its behavior) is defined exactly once.
local function runStageA(roots: { any }, artifact: ArtifactData): { ClassStageAResult }
	local list = collectAll(roots)

	-- Bucket by ClassName
	local buckets: { [string]: { any } } = {}
	for _, inst in list do
		local className = inst.ClassName
		local bucket = buckets[className]
		if not bucket then
			bucket = {}
			buckets[className] = bucket
		end
		table.insert(bucket, inst)
	end

	-- Sort class names alphabetically
	local classNames = {}
	for name in buckets do
		table.insert(classNames, name)
	end
	table.sort(classNames)

	-- Assign implicit sequential 1-based global IDs
	local globalIdMap: { [string]: number } = {}
	local globalId = 0
	for _, className in classNames do
		local bucket = buckets[className]
		for _, inst in bucket do
			globalId += 1
			globalIdMap[inst:GetDebugId()] = globalId
		end
	end

	local results: { ClassStageAResult } = {}

	for _, className in classNames do
		local bucket = buckets[className]
		local classMeta = artifact.classByName[className]
		if not classMeta then
			warn("Class metadata not found in artifact for class: " .. className)
			continue
		end

		local numBucket = #bucket

		local propsWithCodec = {}
		for _, pm in classMeta.properties do
			if pm.codec then
				table.insert(propsWithCodec, pm)
			end
		end

		-- Pass A: compute serialized value + isDefault for every property/instance
		local serializedByProp = table.create(#propsWithCodec)
		local isDefaultByProp = table.create(#propsWithCodec)

		for pIdx, pm in propsWithCodec do
			local serializedVals = table.create(numBucket)
			local isDefaults = table.create(numBucket)

			for i, inst in bucket do
				local serializedVal, isDefault = PropertyCompare.computeSerializedValue(inst, pm, globalIdMap)
				serializedVals[i] = serializedVal
				isDefaults[i] = isDefault
			end

			serializedByProp[pIdx] = serializedVals
			isDefaultByProp[pIdx] = isDefaults
		end

		table.insert(results, {
			className = className,
			classMeta = classMeta,
			numBucket = numBucket,
			propsWithCodec = propsWithCodec,
			serializedByProp = serializedByProp,
			isDefaultByProp = isDefaultByProp,
		})
	end

	return results
end

local function serialize(roots: { any }, artifact: ArtifactData): buffer
	local stageAResults = runStageA(roots, artifact)

	local stringTable: { string } = {}
	local stringMap: { [string]: number } = {}
	local function getStringIndex(str: string): number
		local idx = stringMap[str]
		if not idx then
			table.insert(stringTable, str)
			idx = #stringTable
			stringMap[str] = idx
		end
		return idx
	end

	local classBlocks: { ClassBlock } = {}

	for _, sa in stageAResults do
		local effectiveCount = sa.numBucket
		local columns: { PropertyColumn } = {}

		for pIdx, pm in sa.propsWithCodec do
			local codec = pm.codec

			local serializedVals = sa.serializedByProp[pIdx]
			local isDefaults = sa.isDefaultByProp[pIdx]

			local result = ColumnEncoder.encodeColumn(codec, serializedVals, isDefaults, effectiveCount)

			table.insert(columns, {
				propertyNameIndex = getStringIndex(pm.name),
				encoding = result.encoding,
				bitmask = result.bitmask,
				values = result.values,
				dictIndices = result.dictIndices,
			})
		end

		table.insert(classBlocks, {
			classId = sa.classMeta.id,
			instanceCount = sa.numBucket,
			columns = columns,
		})
	end

	local formatData: FormatData = {
		version = 4,
		stringTable = stringTable,
		classBlocks = classBlocks,
	}

	return FormatWriter.write(formatData, artifact)
end

-- Builds the wire payload for one class block, per the "Worker protocol > Serialize"
-- section of docs/superpowers/specs/2026-07-05-parallel-encoding-design.md and the
-- exact format documented at the top of src/parallel/Worker.luau:
--   className: string
--   classId: varint
--   instanceCount: varint
--   columnCount: varint
--   per column: propertyName (string), propertyNameIndex (varint, REAL global index),
--     codecId (varint), packed bitmask, then each non-default value via codec.write
--     (transport encoding only - the worker picks the final on-disk encoding).
local function buildWorkerPayload(sa: ClassStageAResult, getStringIndex: (string) -> number): buffer
	local w = BufferWriter.new()

	w:string(sa.className)
	w:varint(sa.classMeta.id)
	w:varint(sa.numBucket)
	w:varint(#sa.propsWithCodec)

	local numBucket = sa.numBucket

	for pIdx, pm in sa.propsWithCodec do
		local codec = pm.codec
		local serializedVals = sa.serializedByProp[pIdx]
		local isDefaults = sa.isDefaultByProp[pIdx]

		w:string(pm.name)
		w:varint(getStringIndex(pm.name))
		w:varint(pm.codecId)

		-- Pack bitmask (1 = non-default, matches Worker.luau's unpacking)
		local numBytes = math.ceil(numBucket / 8)
		local maskBuf = buffer.create(numBytes)
		local byteIdx = 0
		local acc = 0
		local bitIdx = 0
		for i = 1, numBucket do
			if not isDefaults[i] then
				acc = bit32.bor(acc, bit32.lshift(1, bitIdx))
			end
			bitIdx += 1
			if bitIdx == 8 then
				buffer.writeu8(maskBuf, byteIdx, acc)
				byteIdx += 1
				acc = 0
				bitIdx = 0
			end
		end
		if bitIdx > 0 then
			buffer.writeu8(maskBuf, byteIdx, acc)
		end
		w:bytes(maskBuf)

		for i = 1, numBucket do
			if not isDefaults[i] then
				codec.write(w, serializedVals[i])
			end
		end
	end

	return w:toBuffer()
end

-- Parallel sibling of serialize(): Stage A runs sequentially in the parent (see
-- runStageA above), then each class block's Stage B work (final encoding choice +
-- byte writing) is delegated to a `lune run src/parallel/Worker.luau` child process,
-- one process per class block, per the parallel-encoding design doc.
--
-- Concurrency note: Lune 0.10.4's process.create + ChildProcessWriter:close() does
-- not reliably signal EOF to the child (a prior smoke test hung forever), so workers
-- are launched via the blocking process.exec, each wrapped in its own task.spawn
-- coroutine. Verified experimentally in this task: N concurrent task.spawn-wrapped
-- process.exec calls, each sleeping 1s in the child, complete together in ~1.1s wall
-- time (not ~N seconds), confirming Lune's scheduler actually interleaves the
-- blocking process.exec calls across coroutines - this is true concurrent execution,
-- not sequential-in-disguise.
local function serializeParallel(roots: { any }, artifact: ArtifactData): buffer
	local stageAResults = runStageA(roots, artifact)

	-- Precompute the full string table up front (step 2 of the worker protocol):
	-- hoists the existing lazy getStringIndex so every property name across every
	-- class gets a stable global index before any worker payload is built.
	local stringTable: { string } = {}
	local stringMap: { [string]: number } = {}
	local function getStringIndex(str: string): number
		local idx = stringMap[str]
		if not idx then
			table.insert(stringTable, str)
			idx = #stringTable
			stringMap[str] = idx
		end
		return idx
	end

	for _, sa in stageAResults do
		for _, pm in sa.propsWithCodec do
			getStringIndex(pm.name)
		end
	end

	local n = #stageAResults
	local blockBytes: { string? } = table.create(n)
	local errors: { string? } = table.create(n)
	local threads = table.create(n)

	for idx, sa in stageAResults do
		local payload = buildWorkerPayload(sa, getStringIndex)
		local payloadStr = buffer.tostring(payload)

		local thread = task.spawn(function()
			local result = process.exec("lune", { "run", "src/parallel/Worker.luau" }, {
				stdio = { stdin = payloadStr },
			})
			if result.ok then
				blockBytes[idx] = result.stdout
			else
				errors[idx] = string.format(
					"parallel encode failed for class %s: %s",
					sa.className,
					if result.stderr ~= "" then result.stderr else "exited with code " .. tostring(result.code)
				)
			end
		end)
		table.insert(threads, thread)
	end

	-- Wait for all workers to finish (each task.spawn'd thread completes when its
	-- blocking process.exec call returns).
	local remaining = n
	while remaining > 0 do
		remaining = 0
		for idx = 1, n do
			if blockBytes[idx] == nil and errors[idx] == nil then
				remaining += 1
			end
		end
		if remaining > 0 then
			task.wait(0.01)
		end
	end

	for idx = 1, n do
		if errors[idx] then
			error(errors[idx])
		end
	end

	-- Stage C (sequential, parent-only): stitch header + string table + each
	-- class block's already-length-prefixed bytes, in classId order.
	local headerWriter = BufferWriter.new()
	headerWriter:u8(0x4C)
	headerWriter:u8(0x41)
	headerWriter:u8(0x54)
	headerWriter:u8(0x46)
	headerWriter:u16(4)
	headerWriter:varint(#stringTable)
	for _, str in stringTable do
		headerWriter:string(str)
	end
	headerWriter:varint(n)

	local totalLen = headerWriter:len()
	for idx = 1, n do
		totalLen += #(blockBytes[idx] :: string)
	end

	local outBuf = buffer.create(totalLen)
	local headerBuf = headerWriter:toBuffer()
	buffer.copy(outBuf, 0, headerBuf, 0, headerWriter:len())
	local offset = headerWriter:len()
	for idx = 1, n do
		local bytes = blockBytes[idx] :: string
		buffer.writestring(outBuf, offset, bytes)
		offset += #bytes
	end

	return outBuf
end

return {
	serialize = serialize,
	serializeParallel = serializeParallel,
}

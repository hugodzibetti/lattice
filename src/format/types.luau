--!strict

export type Encoding = number
-- 0 = raw (bitmask + raw values)
-- 1 = RLE (bitmask + runCount + runs)
-- 2 = delta (reserved)
-- 3 = AllDefault (no bitmask, no values - all are default)
-- 4 = AllNonDefault (no bitmask, all raw values)

export type PropertyColumn = {
	propertyNameIndex: number, -- references string table for robustness
	encoding: Encoding,
	bitmask: { boolean },
	values: { any },
}

export type ClassBlock = {
	classId: number,
	instanceCount: number,
	columns: { PropertyColumn },
}

export type FormatData = {
	version: number,
	stringTable: { string },
	classBlocks: { ClassBlock },
}

return {}

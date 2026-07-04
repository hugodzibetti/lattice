# Format Layer — Design

## Context

The artifact system (`src/artifacts/`) gives us pre-computed class metadata: property
lists, codec assignments, and parsed default values. The format layer is the **binary
envelope** that surrounds serialized instance data — it's the container that holds the
output of the instance serializer.

Without a format layer, we'd have a raw stream of codec output with no structure —
no way to find where one class ends and another begins, no interning of repeated strings,
no default elision. The format layer adds the structural skeleton.

This design covers the format container, columnar data layout, default-value bitmasks,
and per-column encoding strategies.

## Goal

A `src/format/` module that:

1. **Defines the binary container** — header, string table, class blocks.
2. **Produces columnar class blocks** — groups same-class instances, stores properties
   as columns with per-instance bitmasks for default elision.
3. **Supports per-column encoding** — raw (codec-per-value), run-length, and future
   delta encoding, chosen per property column based on data patterns.
4. **Is format-versioned** — the header carries a version number; the artifact already
   carries one. They evolve independently.

## Non-goals

- The instance traversal logic (walking the tree, bucketing by class). That's
  `src/instance/`.
- Compression (gzip/zstd). The format is designed to be compression-friendly, but
  compression is applied at the file level after serialization.
- Cross-version compat translation (that's `src/compat/`).

## Key Concepts

### Varint (Variable-length Integer)

A LEB128 encoding where 7 bits carry data and the high bit signals more bytes follow.
Small numbers (0–127) cost 1 byte. Used pervasively: counts, IDs, lengths, bitmasks.

| Value | Bytes          |
| ----- | -------------- |
| 1     | `[0x01]`       |
| 127   | `[0x7F]`       |
| 128   | `[0x80, 0x01]` |
| 300   | `[0xAC, 0x02]` |

Zigzag variant (signed) maps negative numbers to small unsigned ints before LEB128.
See `src/buffer/Writer.luau` and `Reader.luau`.

### Columnar Layout (Structure of Arrays)

Instead of writing each instance as a complete row (AoS — Array of Structures):

```
Part #1: [Anchored][Position][Size]
Part #2: [Anchored][Position][Size]
Part #3: [Anchored][Position][Size]
```

Columns group the _same property_ across all instances (SoA):

```
Class "Part" (3 instances):
  Column "Anchored": [true, false, true]
  Column "Position": [(0,5,0), (10,5,0), (0,5,10)]
  Column "Size":     [(2,1,4), (1,1,1), (4,2,4)]
```

**Why it works**: the instance layer already buckets instances by class during its
index phase. Every instance of "Part" is collected together before serialization
begins. Columnar is just writing them grouped by property instead of by instance.

**Benefits**:

- Same codec in a tight loop — no codec switching, CPU branch predictor loves it.
- Enables per-column encoding strategies (RLE, delta).
- Bitmask default elision slots in naturally.

### Bitmask Default Elision

Each property has a default value stored in the artifact (parsed from the Roblox API
dump). During serialization, each instance's value is compared to the default. The
result is a bitmask — one bit per instance.

```
Part:     #0  #1  #2  #3  #4  #5  #6  #7
Anchored:  T   F   T   T   T   F   T   T    (default = true)
Non-def:   0   1   0   0   0   1   0   0   → bitmask byte = 0b00100010 = 34
```

**At write time**: the bitmask is written first (varint). Then only non-default
values are serialized, in order. If all bits are 0 (entirely default), zero value
bytes follow.

**At read time**: walk the bitmask bit by bit. For a 0-bit, yield the default value
from artifact. For a 1-bit, read the next value from the codec.

**Size**: a column of 500 instances where only 3 differ from default: 1 byte for
the bitmask (500 fits in 1 varint byte? No — 500 > 127, so 2 bytes) plus 3 values.
Without elision: 500 values.

### Run-Length Encoding (RLE)

When many instances share the **same non-default** value, RLE collapses runs.

Without RLE (5 Parts, all `Material = "Wood"`, default is `"Plastic"`):

```
[bitmask = 31 (all 5 non-default)]  [1 byte]
["Wood"] ["Wood"] ["Wood"] ["Wood"] ["Wood"]  [5 × 5 = 25 bytes]
Total: 26 bytes
```

With RLE:

```
[bitmask = 31]       [1 byte]
[encoding = 1 (RLE)] [1 byte]
[runCount = 1]       [1 byte]
[repeat = 5]         [1 byte]
["Wood"]             [5 bytes]
Total: 9 bytes (65% reduction)
```

#### Break-even analysis

RLE overhead is 3 bytes (encoding tag + runCount + repeat count). Raw baseline is
`N × S` where S is value size.

| Value type        | Bytes per value | RLE wins at N ≥ |
| ----------------- | --------------- | --------------- |
| `bool`            | 1               | 6               |
| `f32`             | 4               | 3               |
| `f64`             | 8               | 2               |
| `Vector3` (3×f32) | 12              | 2               |
| `string`          | 5+              | 2               |

RLE breaks even at 2–3 repeats for most types. The bitmask already handles the
"all default" case for free (1 byte total). RLE covers "all same non-default."

### Delta Encoding (Future)

Columns of related values (e.g. stacked-part positions) exhibit patterns: same X,
linearly increasing Y, same Z. Delta encoding stores the first value fully, then
stores only differences from the previous value.

```
Position column (3 parts stacked vertically):
  X: [0, 0, 0]     → all same
  Y: [5, 7, 9]     → base=5, stride=2, count=3
  Z: [0, 0, 0]     → all same
```

Not in V1 — the encoding tag byte reserves a slot for future delta.

### Per-Column Encoding Choice

Each property column declares its encoding independently. Some properties benefit
from RLE (Material, Color), others don't (Position, CFrame).

```
Property "Material":
  [encoding = 1 (RLE)]
  ...

Property "Position":
  [encoding = 0 (raw)]
  ...

Property "Anchored":
  [encoding = 0 (raw)]   ← bool column, RLE break-even is 6, raw is fine
  ...
```

The serializer (instance layer) picks the best encoding per column based on a quick
pass over the values. For V1: raw only, plus RLE when a single non-default value
repeats ≥ 3 times.

## Binary Container Format

```
[4 bytes]  magic:    0x4C 0x41 0x54 0x46  ("LATF" = Lattice Format)
[2 bytes]  version:  u16 (currently 1)
[varint]   stringTableCount

--- String table (interning) ---
for each entry:
  [string]  interned string

--- Tag table (class name → class ID mapping) ---
[varint]   tagCount
for each tag:
  [varint]  classId
  [varint]  stringIndex   → points into string table

--- Class blocks ---
[varint]   classBlockCount
for each block:
  [varint]  classId
  [varint]  instanceCount

  [varint]  propertyCount
  for each property:
    [varint]  propertyIndex    → points into artifact's class property list
    [varint]  encoding         → 0=raw, 1=RLE, 2=delta (reserved)
    [varint]  bitmask          → one bit per instance

    if encoding == 0 (raw):
      for each set bit in bitmask:
        [codec bytes]          → codec.write(value)

    if encoding == 1 (RLE):
      [varint]  runCount
      for each run:
        [varint]  repeatCount
        [codec bytes]          → the value repeated

    if encoding == 2 (delta, future):
      (reserved)
```

### String Table

Repeated strings (class names, property names, Material values) are interned into
a flat table at the top. References use a varint index into the table. This avoids
writing `"Part"` hundreds of times.

**Design decision**: property names reference the string table, not the artifact.
This means the format is self-describing for property order — you don't need the
artifact to know which property a column corresponds to. The artifact is an
optimization (pre-resolved codecs, defaults), not a requirement.

### Tag Table

Maps class IDs (from the artifact) to their string names (from the string table).
This lets a reader without the artifact at least identify which classes are present.

## Architecture

```
src/format/
  types.luau        — shared types (Encoding enum, ColumnBlock, FormatHeader, etc.)
  Writer.luau       — builds format container: string table, tag table, class blocks
  Reader.luau       — reads format container
  init.luau         — re-exports
```

### Types

```luau
export type Encoding = number  -- 0 = raw, 1 = RLE, 2 = delta (reserved)

export type PropertyColumn = {
    propertyIndex: number,     -- index into ClassMetadata.properties
    encoding: Encoding,
    bitmask: { boolean },      -- true = non-default (serialized)
    values: { any },           -- only non-default values, in order
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
```

### Writer flow

1. **Collect strings** — scan all class names, property names, and string values for
   candidates. Deduplicate. Build string table.
2. **Write header** — magic, version.
3. **Write string table** — varint count, then each string.
4. **Write tag table** — varint count, then (classId, stringIndex) pairs.
5. **Write class blocks** — for each class, write instance count, then each
   property column with bitmask and encoding-specific value data.

### Reader flow

1. Validate magic, check version.
2. Read string table into array.
3. Read tag table.
4. For each class block: read instance count, then walk columns. For each column,
   read property index, encoding, bitmask. Walk bitmask bits, reading codec values
   for set bits (or expanding RLE runs). Yield values in instance order.

## Integration with Artifact

The format layer does **not** duplicate the artifact. It stores:

- **Property index** (varint) — a pointer into that class's `ClassMetadata.properties`
  list in the artifact. The artifact provides the codec, codec params, and default
  value for that slot.

- **Encoding + bitmask + values** — the actual instance data.

At load time, the reader takes an artifact + a format buffer. For each property
column, it looks up the codec from the artifact, then reads values accordingly.

## Size estimates

For a typical Roblox place with 10,000 parts across 50 classes:

| Component       | Without format layer | With format layer                       |
| --------------- | -------------------- | --------------------------------------- |
| String overhead | Per-occurrence       | String table (shared)                   |
| Default values  | All written          | Bitmask elided (typically 80%+ default) |
| Property names  | Per-instance         | Indexed via artifact                    |
| Class names     | Per-instance         | In tag table only                       |

Expected reduction: 40–60% vs naive per-instance serialization, before compression.

## Next steps after this

- **Instance layer** (`src/instance/`): tree traversal, class bucketing, producing
  `FormatData` from live instances.
- **CLI round-trip**: `lune run src/serialize/Run.luau` that reads a place file,
  serializes, deserializes, and verifies.
- **Delta encoding**: implement encoding=2 when benchmarks show position/CFrame
  columns dominating output size.

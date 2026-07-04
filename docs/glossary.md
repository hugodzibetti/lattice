# Lattice — Glossary

## Binary encoding

### varint
A variable-length integer using LEB128 encoding. 7 bits of data per byte; the
high bit (0x80) signals "more bytes follow." Small numbers (0–127) cost 1 byte,
128–16383 cost 2 bytes, etc. Used for counts, IDs, lengths, and bitmasks throughout
the format.

**Signed variant** (zigzag): negative numbers are zigzag-mapped to unsigned before
LEB128, so small-magnitude negatives stay small.

→ [Varint Examples](../examples/varint.md) — byte-level encoding walkthrough, zigzag table, size comparison

### bitmask
An integer where each bit encodes a boolean for one instance. In Lattice, bit N = 1
means "instance N has a non-default value for this property." Used for default-value
elision. A column of 500 instances with only 3 non-defaults: 2 bytes for the bitmask
+ 3 serialized values, instead of 500.

→ [Bitmask Examples](../examples/bitmask.md) — bit numbering, reading algorithm, large-column walkthrough

### RLE (Run-Length Encoding)
A compression scheme where consecutive identical values are stored as `(repeatCount,
value)` pairs. In Lattice, RLE is a per-column encoding option. Applied when many
instances share the same non-default value (e.g. `Material = "Wood"` on 200 fence
parts). The bitmask already handles the "all default" case for free.

→ [RLE Examples](../examples/rle.md) — 500-part fence scenario, mixed materials, break-even table, when NOT to use RLE

### delta encoding
Stores only the *difference* from the previous value, rather than the full value.
Useful for columns with gradual changes (stacked-part Y-coordinates: `[5, 7, 9]` →
stored as `[base=5, stride=2, count=3]`). Not in V1 — encoding tag reserved.

## Data layout

### columnar layout (Structure of Arrays / SoA)
Instead of writing each instance as a complete record (all properties of Part #1,
then all properties of Part #2...), columnar layout groups the *same property* across
all instances. All `Anchored` values together, then all `Position` values, etc.

→ [Columnar vs Row-Oriented Examples](../examples/columnar-vs-row.md) — concrete 3-part wall scenario with byte counts

### row-oriented layout (Array of Structures / AoS)
The traditional layout: write instance #1 completely, then instance #2 completely.
Simple but prevents default elision, RLE, and delta encoding because values of the
same property aren't adjacent in the byte stream.

→ [Columnar vs Row-Oriented Examples](../examples/columnar-vs-row.md) — side-by-side comparison with byte counts

### encoding tag
A byte (or varint) per property column that declares how the column's values are
stored: `0` = raw (each value independently), `1` = RLE, `2+` = reserved for future
(delta, etc.). Allows per-column strategy selection.

## Project layers

### artifact
Build-time pre-computed class metadata: property lists, codec assignments, parsed
default values. Stored as a versioned binary (`LATA` magic). Generated from the
Roblox API dump JSON. Consumed by the format layer and instance layer at runtime.

### codec
A module implementing `{ write: (Writer, T) -> (), read: (Reader) -> T }`. One per
Roblox type (CFrame, Vector3, Color3, etc.). Codecs are independent leaves; two are
factory combinators (array, option) that take inner codecs as arguments.

### format layer
The binary container envelope: header, string table, tag table, columnar class blocks
with bitmasks. Defines how serialized data is structured on disk. Lives in
`src/format/`.

### instance layer
Tree traversal and indexing: walks a Roblox Instance hierarchy, buckets instances by
class, and drives the format writer. Separates the *what* (which instances exist)
from the *how* (columnar binary layout). Lives in `src/instance/`.

### compat layer
Versioned schema registry + translation maps. Handles forward/backward compatibility
when the Roblox API dump changes (properties added/removed/renamed). Not yet built.
Lives in `src/compat/`.

## Format details

→ [Format Binary Walkthrough](../examples/format-binary.md) — complete annotated hex dump of a minimal file, reading algorithm in pseudocode

### string table
A flat array of unique strings at the top of the format binary. Class names, property
names, and repeated string values are interned here. References use varint indices.
Avoids writing `"Part"` hundreds of times.

### tag table
Maps class IDs → string table indices. Lets a reader identify which classes are
present without the artifact. The artifact is optional for format inspection, required
for full deserialization.

### property index
A varint pointer into the artifact's `ClassMetadata.properties` list. Tells the reader
which property a column corresponds to, which codec to use, and what the default value
is. The format doesn't store property names directly — they're in the artifact.

### default elision
Skipping serialization of a property value when it equals the Roblox default. The
artifact stores parsed defaults; the format layer compares each instance's value
against the default to build the bitmask. At read time, 0-bits yield the cached
default without deserialization.

### never-elide
Properties whose default should never be elided even when they match. Currently:
`Name` (always unique in practice) and `UniqueId` (generated at creation, never
default in a meaningful way). Storing their defaults wastes artifact space and the
comparison is always false.

## Magic bytes

| Magic | Meaning | Location |
|-------|---------|----------|
| `LATA` (0x4C 0x41 0x54 0x41) | Lattice Artifact | Artifact binary header |
| `LATF` (0x4C 0x41 0x54 0x46) | Lattice Format | Format binary header |

→ [Format Binary Walkthrough](../examples/format-binary.md) — complete annotated hex dump, reading algorithm pseudocode

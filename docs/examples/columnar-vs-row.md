# Columnar vs Row-Oriented Examples

Supplementary examples for [columnar layout](../glossary.md#columnar-layout-structure-of-arrays--soa)
and [row-oriented layout](../glossary.md#row-oriented-layout-array-of-structures--aos).

## Concrete scenario

3 Parts forming a simple wall:

```
Part "A": Anchored=true,  Position=(0, 5, 0),  Size=(4, 1, 2),  Material="Wood"
Part "B": Anchored=true,  Position=(4, 5, 0),  Size=(4, 1, 2),  Material="Wood"
Part "C": Anchored=false, Position=(8, 5, 0),  Size=(4, 1, 2),  Material="Wood"
```

Defaults: Anchored=true, Material="Plastic".

## Row-oriented write

```
--- Part A ---
  [Anchored][Position=(0,5,0)][Size=(4,1,2)][Material="Wood"]
--- Part B ---
  [Anchored][Position=(4,5,0)][Size=(4,1,2)][Material="Wood"]
--- Part C ---
  [Anchored][Position=(8,5,0)][Size=(4,1,2)][Material="Wood"]
```

Properties interleaved. Codec switches every value: bool → Vector3 → Vector3 →
string → bool → Vector3 → ...

### What row-oriented prevents

1. **Default elision**: Anchored is `true` for A and B (default), `false` for C.
   But the values aren't adjacent — you can't build a bitmask because you'd need
   to jump back and forth between rows.

2. **RLE**: Size is identical for all three. But the Size values are separated by
   Anchored, Position, and Material bytes — no contiguous run to compress.

3. **Delta**: X-coordinates are 0, 4, 8 (linear). Can't delta-encode because the
   X values are interleaved with Y, Z, and other properties.

## Columnar write

```
Class "Part" (3 instances):

  Column "Anchored":
    bitmask: 0b100 = 4  (only instance C differs)
    values: [false]

  Column "Position":
    bitmask: 0b111 = 7  (all non-default at (0,5,0), (4,5,0), (8,5,0))
    values: [(0,5,0), (4,5,0), (8,5,0)]

  Column "Size":
    bitmask: 0b000 = 0  (all default)
    values: []           ← zero bytes, bitmask covers it

  Column "Material":
    bitmask: 0b111 = 7  (all non-default)
    encoding: RLE
    runCount: 1, repeat: 3, value: "Wood"
```

### What columnar enables

1. **Default elision**: Anchored column → 1 byte bitmask + 1 bool = 2 bytes.
   Row-oriented: 3 bytes (one bool per instance). Size column → 1 byte bitmask +
   zero values = 1 byte. Row-oriented: 36 bytes (3 × Vector3).

2. **RLE**: Material → 1 byte bitmask + 1 byte encoding + 1 byte runCount +
   1 byte repeat + 5 bytes string = 9 bytes. Row-oriented: 15 bytes.

3. **Delta-ready**: Positions → X column: `[0, 4, 8]`, Y column: `[5, 5, 5]`,
   Z column: `[0, 0, 0]`. Y and Z are all-same (bitmask or RLE). X is linear
   (future delta).

## Byte count comparison

| Layout              | Anchored | Position | Size | Material | Total  |
| ------------------- | -------- | -------- | ---- | -------- | ------ |
| Row-oriented        | 3        | 36       | 36   | 15       | **90** |
| Columnar (raw only) | 2        | 37       | 1    | 16       | **56** |
| Columnar (with RLE) | 2        | 37       | 1    | 9        | **49** |

Columnar alone (bitmask elision) gives 38% reduction. Adding RLE: 46%.

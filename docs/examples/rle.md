# RLE Examples

Supplementary examples for the [RLE glossary entry](../glossary.md#rle-run-length-encoding).

## Scenario: 500 Fence Parts, Material = "Wood"

Default `Material` for `Part` is `"Plastic"`. A fence builder set all 500 parts to
`"Wood"` (non-default).

### Without RLE (raw encoding)

```
[encoding=0]                         1 byte
[bitmask byteCount] [bitmask bytes]  ~63 bytes (500 bits)
["Wood"]["Wood"]...["Wood"]          500 × 5 bytes = 2500 bytes
Total: ~2564 bytes
```

### With RLE

```
[encoding=1]                         1 byte
[bitmask byteCount] [bitmask bytes]  ~63 bytes (all 1s — all non-default)
[runCount=1]                         1 byte
[repeat=500]                         2 bytes (varint: 500 > 127 → 2 bytes)
["Wood"]                             5 bytes
Total: ~72 bytes
```

**Reduction: 97%.**

## Scenario: Mixed Materials

50 Parts: 30 `"Plastic"` (default), 15 `"Wood"`, 5 `"Metal"`.

```
Bitmask: 50 bits → 7 bytes.
Bits for "Plastic" = 0 (default, elided).
Bits for "Wood" and "Metal" = 1.

Plastic instances don't contribute to the column — the bitmask covers them.
```

### Without RLE

```
[encoding=0]         1 byte
[bitmask bytes]      7 bytes
["Wood"]×15          75 bytes
["Metal"]×5          26 bytes
Total: 109 bytes
```

### With RLE (assuming "Wood" instances are contiguous)

If the serialization order puts all Wood parts together (same fence section)
and Metal parts together:

```
[encoding=1]         1 byte
[bitmask bytes]      7 bytes
[runCount=2]         1 byte
[repeat=15]          1 byte
["Wood"]             5 bytes
[repeat=5]           1 byte
["Metal"]            6 bytes
Total: 22 bytes
```

**Reduction: 80%.**

## RLE break-even table

RLE overhead per run: 1 byte (repeat count, if < 128). Raw cost: N × S.
Break-even: N × S > 1 + S → N > (1 + S) / S.

| Type          | S (bytes) | Break-even N | Example                           |
| ------------- | --------- | ------------ | --------------------------------- |
| bool          | 1         | > 2          | Need 3+ identical booleans        |
| f32           | 4         | > 1          | 2 identical f32s already win      |
| f64           | 8         | > 1          | 2 identical f64s already win      |
| Vector3       | 12        | > 1          | 2 identical positions already win |
| string "Wood" | 5         | > 1          | 2 identical strings already win   |

For anything larger than a bool, RLE wins at **2 repeats**.

## When NOT to use RLE

1. **Most values are default** — the bitmask already elides them. RLE adds
   overhead with no benefit.
2. **All values are unique or nearly unique** — `Position`, `CFrame`, `Name`.
   The encoding tag byte and runCount byte are wasted.
3. **Small columns** — a column of 3 instances where 1 differs. RLE overhead
   exceeds savings.

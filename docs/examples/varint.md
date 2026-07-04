# Varint Examples

Supplementary examples for the [varint glossary entry](../glossary.md#varint).

## Unsigned varint (LEB128)

Each byte: 7 bits data (low), 1 bit continuation (high). MSB first within each
7-bit group.

```
Value 0:
  Binary: 00000000
  Bytes:  [0x00]

Value 1:
  Binary: 00000001
  Bytes:  [0x01]

Value 127 (max 1-byte):
  Binary: 01111111
  Bytes:  [0x7F]

Value 128 (first 2-byte):
  Binary: 00000001 00000000
  Groups: (0000001) (0000000)   ← 7-bit groups, little-endian
  Bytes:   [0x80, 0x01]
  Why: 0x80 = 1xxxxxxx (continuation + low 7 bits of 128)
       0x01 = 0xxxxxxx (high 7 bits, no continuation)

Value 300:
  Binary: 00000010 01011000
  Groups: (0101100) (0000010)
  Bytes:   [0xAC, 0x02]
  Why: 0xAC = 10101100 (low 7 bits = 0101100 = 44)
       0x02 = 00000010 (high bit = 0, value = 2)
  Check: 44 + (2 << 7) = 44 + 256 = 300 ✓

Value 16383 (max 2-byte):
  Groups: 1111111 1111111
  Bytes:  [0xFF, 0x7F]

Value 16384 (first 3-byte):
  Groups: (0000000) (0000001) (0000001)
  Bytes:   [0x80, 0x80, 0x01]
```

## Zigzag (signed varint)

Maps signed integers to unsigned before LEB128. Formula:

- Encode: `unsigned = (signed << 1) ^ (signed >> 63)` (arithmetic shift)
- Decode: `signed = (unsigned >> 1) ^ -(unsigned & 1)`

In practice (Luau 32-bit equivalent):

```
 0 → 0    → [0x01]        (varint of 0)
-1 → 1    → [0x01]        (varint of 1)
 1 → 2    → [0x02]
-2 → 3    → [0x03]
 2 → 4    → [0x04]
-3 → 5    → [0x05]
 64 → 128 → [0x80, 0x01]
-64 → 127 → [0x7F]
```

Small-magnitude negatives stay small. -1 costs 1 byte, not ~10 bytes of a
two's-complement u64.

## Why Lattice uses varint everywhere

Typical values in a serialized place file:

| Field          | Typical value | Varint bytes | Fixed (u16) |
| -------------- | ------------- | ------------ | ----------- |
| Codec ID       | 0–25          | 1            | 2           |
| Property count | 3–30          | 1            | 2           |
| Instance count | 1–500         | 1–2          | 2           |
| String length  | 1–80          | 1            | 2           |
| Class ID       | 1–200         | 1–2          | 2           |

Over 10,000 properties × 1 byte saved each = ~10KB saved. Free compression.

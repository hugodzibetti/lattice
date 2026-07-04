# Bitmask Examples

Supplementary examples for the [bitmask glossary entry](../glossary.md#bitmask).

## Basic: 8 Parts, Anchored property

Default `Anchored = true`.

```
Instance:  #0   #1   #2   #3   #4   #5   #6   #7
Value:     true false true true true false true true
Default?    Y    N     Y    Y    Y    N     Y    Y
Bit:        0    1     0    0    0    1     0    0

Bitmask byte: 0b00100010 = 0x22 = 34
```

Wrote: 1 byte bitmask + 2 `false` booleans = 3 bytes.
Naive: 8 booleans = 8 bytes.

## Larger: 100 Parts, only 3 differ

```
Bitmask (100 bits = 13 bytes as varint? No — let's be precise):
100 bits → ceil(100/8) = 13 bytes for the raw bits.
But varint-encoded: 13 bytes with high bits mostly zero.
Actually for 100 bits, the value is < 2^100 which is gigantic.
We'd store the bitmask as a byte array, not a single varint integer.
```

**Correction**: In practice, Lattice stores the bitmask as a sequence of bytes
(varint-length-prefixed). For 100 instances:

```
[varint byteCount=13] [byte0] [byte1] ... [byte12]
```

Only 3 bits set → most bytes are 0x00. 13 bytes for the mask, then 3 serialized
values.

Naive: 100 values × average 4 bytes = 400 bytes.

## Bit numbering

Bit 0 (LSB) = instance 0, bit 1 = instance 1, etc.

```
Byte 0: [i7 i6 i5 i4 i3 i2 i1 i0]   ← instances 0–7
Byte 1: [i15 i14 i13 i12 i11 i10 i9 i8] ← instances 8–15
...
```

If instance 9 is non-default and instances 0–8 and 10+ are default:

```
Byte 0: 0b00000000 = 0x00  (instances 0–7, all default)
Byte 1: 0b00000010 = 0x02  (instance 9 = bit 1 set in byte 1)
```

## Walkthrough: reading a bitmask column

Buffer: `[varint byteCount=2] [0x00] [0x02] [value bytes...]`

Reader algorithm:

```
byteCount = read_varint()
valueIdx = 0
for b = 0, byteCount-1:
    byte = read_u8()
    for bit = 0, 7:
        if byte & (1 << bit):
            yield read_codec_value()   ← read from value bytes
            valueIdx += 1
        else:
            yield default_value
```

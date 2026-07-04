# Format Binary Walkthrough

Supplementary example for the [format layer design spec](../superpowers/specs/2026-07-04-format-layer-design.md).

## Complete format binary, annotated

A minimal serialized file: 1 class ("Part"), 2 instances, 2 properties (Anchored, Position).

```
┌── Header ──────────────────────────────────────────────────────────┐
│ 4C 41 54 46          Magic "LATF"                                   │
│ 00 01                Version u16 = 1                                │
│ 03                   String table count = 3                         │
└─────────────────────────────────────────────────────────────────────┘

┌── String Table ────────────────────────────────────────────────────┐
│ 04 50 61 72 74       [len=4] "Part"                                 │
│ 08 41 6E 63 68 6F    [len=8] "Anchored"                             │
│ 72 65 64                                                           │
│ 08 50 6F 73 69 74    [len=8] "Position"                             │
│ 69 6F 6E                                                           │
└─────────────────────────────────────────────────────────────────────┘

┌── Tag Table ───────────────────────────────────────────────────────┐
│ 01                   Tag count = 1                                  │
│ 01                   Class ID = 1                                   │
│ 00                   String index 0 → "Part"                        │
└─────────────────────────────────────────────────────────────────────┘

┌── Class Blocks ────────────────────────────────────────────────────┐
│ 01                   Class block count = 1                          │
│                                                                     │
│ ── Class 1 (Part) ──                                                │
│ 01                   Class ID = 1                                   │
│ 02                   Instance count = 2                             │
│ 02                   Property count = 2                             │
│                                                                     │
│   ── Property column 0 (Anchored, bool=2) ──                        │
│   01                 Property index = 1 (Anchored)                   │
│   00                 Encoding = 0 (raw)                              │
│   01                 Bitmask byte count = 1                          │
│   02                 Bitmask byte = 0b00000010 (only instance 1)     │
│   01                 Value: bool true (for instance 1)               │
│                                                                     │
│   ── Property column 1 (Position, Vector3=17) ──                     │
│   02                 Property index = 2 (Position)                   │
│   00                 Encoding = 0 (raw)                              │
│   01                 Bitmask byte count = 1                          │
│   03                 Bitmask = 0b00000011 (both instances differ)    │
│   00 00 00 00        Value 1 (instance 0): Vector3(0, 0, 0)         │
│   00 00 00 00                                                        │
│   00 00 00 00                                                        │
│   00 00 80 3F        Value 2 (instance 1): Vector3(1.0, 0, 0)       │
│   00 00 00 00                                                        │
│   00 00 00 00                                                        │
└─────────────────────────────────────────────────────────────────────┘
```

## The same file with RLE on Material

If we add a 3rd property "Material" (string, default="Plastic") and both
instances have "Wood":

```
  ── Property column 2 (Material, string=3) ──
  03                 Property index = 3 (Material)
  01                 Encoding = 1 (RLE)
  01                 Bitmask byte count = 1
  03                 Bitmask = 0b00000011 (both non-default)
  01                 Run count = 1
  02                 Repeat count = 2
  04 57 6F 6F 64     Value: "Wood" (len=4)
```

## Reading algorithm (pseudocode)

```
read_header()
string_table = read_string_table()
tag_table = read_tag_table()

for each class_block:
    class_meta = artifact.classById[class_block.classId]
    for each property_column:
        prop_meta = class_meta.properties[property_column.propertyIndex]
        codec = get_codec(prop_meta.codecId, prop_meta.codecParams)
        default_val = prop_meta.default

        encoding = read_varint()
        byte_count = read_varint()
        bitmask_bytes = read_bytes(byte_count)

        values = []
        if encoding == 0:  -- raw
            for each set bit in bitmask:
                values.push(codec.read(reader))

        elif encoding == 1:  -- RLE
            run_count = read_varint()
            for each run:
                repeat = read_varint()
                val = codec.read(reader)
                for _ = 1, repeat:
                    values.push(val)

        -- Expand bitmask into instance values
        instance_values = []
        value_idx = 0
        for instance = 0, instance_count-1:
            byte = bitmask_bytes[instance // 8]
            bit = (byte >> (instance % 8)) & 1
            if bit:
                instance_values[instance] = values[value_idx]
                value_idx += 1
            else:
                instance_values[instance] = default_val
```

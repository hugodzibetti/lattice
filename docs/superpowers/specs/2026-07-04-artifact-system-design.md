# Artifact System — Design

## Context

Lattice serializes Roblox Instance property values to compact binary. The
**artifact** is build-time pre-computed metadata that tells the serializer:
for a given class, which properties exist, what codec serializes each, what
the default value is (for elision), and where each property sits in the
bitmask.

Without artifacts, the serializer would need runtime reflection (iterate
every property, check its type, branch on type → slow, bloated). With
artifacts, the serializer does a straight-line sequence of codec calls
gated by a bitmask — no branching on type.

Phase 2 (codecs) and the benchmarks harness are done. This design covers the
next layer: building and loading class metadata.

## Goal

A `src/artifacts/` module that:
1. **Builds** compiled class metadata from a Roblox API dump JSON (offline,
   under Lune).
2. **Loads** that metadata at runtime as compact `ClassMetadata` tables with
   pre-resolved codec references and pre-deserialized default values.
3. **Gives the instance layer** everything it needs to serialize/deserialize
   without reflection: a sorted property list, a codec per property, and a
   native default value for elision.

## Non-goals

- Live API dump fetching from Roblox servers — the dump is a committed JSON
  file (or generated locally via `@lune/roblox` introspection).
- Handling classes that aren't in the API dump.
- Property types we don't have codecs for yet (`Vector3int16`, `Ray`,
  `Region3`, etc.) — these are skipped with a warning during the build.
- The binary container format (header, string table, tag table) — that's
  `src/format/`, the next layer.

## Architecture

```
src/artifacts/
  build/
    Run.luau            — entry point: reads API dump JSON, builds artifact binary
    parseDump.luau      — parses Roblox API dump JSON into ClassDef[]
    resolveType.luau    — maps Roblox type names → codec metadata (id + params)
    buildArtifact.luau  — assembles ClassMetadata[], serializes to binary
  Artifact.luau         — runtime loader: reads binary → ArtifactData
  types.luau            — shared types
```

### 1. Data structures — `src/artifacts/types.luau`

```luau
-- Describes how to serialize a single property.
export type PropertyMetadata = {
    name: string,              -- e.g. "CFrame", "Size", "Anchored"
    codecId: number,           -- leaf codec id (6 = cframe)
    codecParams: { number }?,  -- factory params: [3] means array(string)
    default: any?,             -- native Luau default value (nil if no default)
}

-- Describes a single serializable class.
export type ClassMetadata = {
    id: number,                -- numeric class ID (assigned at build time)
    name: string,              -- e.g. "Part", "Model", "Frame"
    properties: { PropertyMetadata }, -- ordered by bitmask position
}

-- The full loaded artifact.
export type ArtifactData = {
    version: number,           -- artifact format version
    classes: { ClassMetadata },
    classByName: { [string]: ClassMetadata },
    classById: { [number]: ClassMetadata },
}
```

### 2. API dump parsing — `src/artifacts/build/parseDump.luau`

Roblox API dumps are JSON files with a well-known structure. The relevant
part is the `Classes` array. Each class has:

```json
{
  "Name": "Part",
  "Superclass": "BasePart",
  "Members": [
    {
      "MemberType": "Property",
      "Name": "Anchored",
      "ValueType": { "Name": "bool" },
      "Tags": ["notScriptable"],
      "Serialization": { "CanSave": true, "CanLoad": true }
    }
  ]
}
```

Parsing rules:
- **Only `MemberType == "Property"`** — skip methods, events, callbacks.
- **Only `Serialization.CanSave == true`** (or absent — some old dumps don't
  have this field; in that case treat as saveable unless tagged).
- **Skip `notScriptable`** properties (can't be read from Luau).
- **Skip `Instance`-typed properties** (children are handled by the instance
  tree layer, not property serialization).
- **Skip `BinaryString`** (deprecated, not used in modern Roblox).
- **Inherited properties are included** — `Part` inherits from `BasePart`,
  which inherits from `PVInstance`, etc. The parser walks the class hierarchy
  and collects all properties. Properties defined on a parent class appear
  first (the instance layer must respect this ordering for stable bitmasks).
- **Property ordering**: inherited properties first (top of hierarchy),
  then own properties. Within each group, alphabetical by name. This is
  deterministic across API dump versions.

Output: `{ ClassDef }` where:
```luau
type ClassDef = {
    name: string,
    superclass: string?,
    properties: { PropertyDef },
}

type PropertyDef = {
    name: string,
    valueType: string,              -- "bool", "float", "CFrame", "Enum", etc.
    valueTypeParams: { string }?, -- e.g. { "string" } for {string}
    hasDefault: boolean,
    defaultRaw: string?,            -- raw default from the dump (e.g. "0, 0, 0" for Vector3)
}
```

### 3. Type resolution — `src/artifacts/build/resolveType.luau`

Maps Roblox type names to codec IDs and factory parameters.

```luau
type ResolvedType = {
    codecId: number,
    codecParams: { number }?,
}
```

Mapping table (exhaustive for current codecs):

| Roblox type name | Codec ID | Params |
|---|---|---|
| `float` | 0 (f32) | — |
| `double` | 1 (f64) | — |
| `bool` | 2 (bool) | — |
| `string` | 3 (string) | — |
| `CFrame` | 6 (cframe) | — |
| `Color3` | 7 (color3) | — |
| `BrickColor` | 8 (brickColor) | — |
| `ColorSequence` | 9 (colorSequence) | — |
| `NumberRange` | 11 (numberRange) | — |
| `NumberSequence` | 12 (numberSequence) | — |
| `UDim` | 14 (udim) | — |
| `UDim2` | 15 (udim2) | — |
| `Vector2` | 16 (vector2) | — |
| `Vector3` | 17 (vector3) | — |
| `Rect` | 18 (rect) | — |
| `Axes` | 19 (axes) | — |
| `Faces` | 20 (faces) | — |
| `PhysicalProperties` | 21 (physicalProperties) | — |
| `Font` | 22 (font) | — |
| `Content` | 23 (content) | — |
| `UniqueId` | 24 (uniqueId) | — |
| `Enum` | 25 (enumItem) | — |

**Generic/parametric types** — handled via factory codecs:

| Roblox type pattern | Factory ID | Inner resolution |
|---|---|---|
| `Array` / `{T}` | 4 (array) | resolve `T` recursively |
| `Optional<T>` | 5 (option) | resolve `T` recursively |

**Int handling**: Roblox `int` properties are 64-bit internally but f64 can
hold all integer values up to 2^53 exactly. Map `int` → f64 (codec 1).
A future `varint` codec could be slotted in for size reduction.

**Unresolvable types**: If a property type can't be mapped to any codec
(`Vector3int16`, `Ray`, `Region3`, `BinaryString`, `Instance`, etc.), the
property is **skipped** and a warning is printed during build:
`"WARNING: {ClassName}.{PropertyName} ({TypeName}) — no codec, skipping"`.

### 4. Default value extraction — `src/artifacts/build/buildArtifact.luau`

The API dump includes defaults as strings (e.g. `"0, 0, 0"` for Vector3,
`"0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0"` for CFrame, `"false"` for bool).

These must be parsed into native Luau values using `@lune/roblox` constructors:

| Type | Raw example | Parser |
|---|---|---|
| `float`/`double`/`int` | `"0"` | `tonumber` |
| `bool` | `"false"` | `== "true"` |
| `string` | `""` | literal (with quotes stripped) |
| `Vector2` | `"0, 0"` | `Vector2.new(parseFloat, parseFloat)` |
| `Vector3` | `"0, 0, 0"` | `Vector3.new(...)` |
| `CFrame` | `"0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1"` | `CFrame.fromMatrix(...)` |
| `Color3` | `"0.639216, 0.635294, 0.647059"` | `Color3.fromRGB(*255)` |
| `BrickColor` | `"Medium stone grey"` | `BrickColor.new(name)` |
| `Enum` | varies | `Enum.{EnumType}.{ItemName}` parsed from metadata |
| `UDim2` | `"0, 0, 0, 0"` | `UDim2.new(...)` |
| and so on... | | |

Defaults are stored as **pre-serialized codec bytes** in the artifact binary.
At load time, `Artifact.luau` deserializes each default via the appropriate
codec to produce the native Luau value. This way the instance layer can do
`value == default` directly (with deep equality where needed).

Defaults that can't be parsed (malformed dump entry, unknown format) result
in no default (`nil`) — the property is always serialized (never elided),
which is safe, just suboptimal.

**Some properties have no meaningful default to elide** — e.g. `Name` (string)
is never at a "default" value in practice. The build allows tagging
properties as "never elide" (hardcoded list: `Name`, `UniqueId`, maybe
`CFrame` since position always differs). This avoids storing and comparing
defaults that will never match. The binary format stores 0-length default
for these cases.

### 5. Binary artifact format

A compact binary encoding of the compiled class metadata. Designed for fast
single-pass loading with minimal memory overhead.

```
[4 bytes]  magic:  0x4C 0x41 0x54 0x41  ("LATA" = Lattice Artifact)
[2 bytes]  version: u16 (currently 1)
[varint]   classCount

for each class:
  [varint]  classId          — numeric ID assigned at build time
  [string]  className         — e.g. "Part"
  [varint]  propertyCount

  for each property:
    [string]  propertyName    — e.g. "CFrame"
    [varint]  codecId         — 0-25 (references serde registry)
    [varint]  paramCount      — 0 for leaf codecs, >0 for factories
    [varint]* codecParams     — one varint per paramCount
    [varint]  defaultLen      — serialized default byte length (0 = no default)
    [bytes]   defaultBytes    — codec-serialized default (only if defaultLen > 0)
```

**Design decisions**:
- Class IDs are assigned sequentially by the build tool (starting at 1).
  IDs are not stable across builds — they're an internal index, not a
  cross-version identifier. The format layer handles cross-version class
  identification via the string name table (in `src/format/`).
- Property names and class names use the buffer's length-prefixed string
  encoding (varint length + UTF-8 bytes). A future format layer may add
  interning via a global string table; that's out of scope here.
- Codec params use varint for compactness — arrays of numbers are always
  varints (they're codec IDs, so always < 128 → 1 byte each).
- Default bytes are raw codec output — loaded by running the codec's `read`
  at artifact load time.

### 6. Runtime loader — `src/artifacts/Artifact.luau`

```luau
--!strict

local function load(buffer: buffer): ArtifactData
```

Reads the binary format described above. For each property:
1. Read property name, codec ID, params, default bytes.
2. Look up the codec (from `codecIdToModule` or apply factory).
3. If default bytes exist, run `codec.read(reader)` to get native default.
4. Build `PropertyMetadata` and insert into `ClassMetadata`.

Returns `ArtifactData` with `classes`, `classByName`, `classById` for O(1)
lookup by either key.

**Factory codec resolution**: when `codecId` is `4` (array) with params `[3]`,
the loader does `array(stringCodec)` where `stringCodec` comes from
`codecIdToModule[3]`. Same for `option`. This mirrors the pattern in
`src/serde/init.luau`.

**Validation**: checks magic bytes and version. Rejects unknown versions
with a clear error: `"Unsupported artifact version: {version}"`.

### 7. Build entry point — `src/artifacts/build/Run.luau`

```bash
lune run src/artifacts/build/Run.luau [--dump path/to/api-dump.json] [--out path/to/artifact.bin]
```

Steps:
1. Read API dump JSON (default: `data/api-dump.json`).
2. `parseDump.luau` → `ClassDef[]`.
3. `resolveType.luau` + `buildArtifact.luau` → `ClassMetadata[]`.
4. Serialize to binary artifact (default: `data/artifact.bin`).
5. Print summary: class count, property count, warnings for skipped types.

**No external dependencies beyond what the project already uses.**
API dump JSON parsing uses Lua's built-in JSON support or a minimal parser.
(If Lune's built-in JSON isn't available, a small vendored parser is
acceptable — but check first; Lune likely has `json.decode`.)

### 8. Project integration

**New dependency**: a committed API dump JSON file at `data/api-dump.json`.
This is regenerated periodically (manually) from Roblox's API dump endpoint
or via `@lune/roblox` introspection. Not part of this task — the build
step just reads whatever dump is present.

**`.gitignore`**: add `data/artifact.bin` (built artifact; regenerable).

**`src/init.luau`**: no changes needed yet — the artifact is consumed by
the instance layer, which doesn't exist. `src/artifacts/Artifact.luau` is
`require`d directly by tests and the future instance layer.

## Testing

Tests live in `tests/Artifact.spec.luau`. Since there's no committed API dump
yet, the test strategy is:

1. **Unit tests** for `resolveType.luau` — given a Roblox type name, does it
   return the correct codec ID and params? Test all 24 leaf types + array,
   option, and a few unresolvable types.

2. **Unit tests** for `parseDump.luau` — given a minimal hand-crafted JSON
   snippet (2-3 classes, a few properties each, one with inheritance), does it
   produce correct `ClassDef` output?

3. **Round-trip test** for the binary artifact format: build a small
   `ClassMetadata[]` by hand (2 classes, 3 properties), serialize, load,
   assert the loaded data matches.

4. **No** test for the full build pipeline (`Run.luau`) until a committed
   API dump exists. That's a follow-up task.

## Next steps after this

- **Format/Container** (`src/format/`): binary envelope with header, string
  table, tag table, columnar class blocks. This is where the artifact's class
  IDs and property layouts get used.
- **Instance layer** (`src/instance/`): traverse instance tree, index by
  class, serialize/deserialize using artifact metadata + codecs.
- **API dump acquisition**: script or manual step to get a current
  `data/api-dump.json` committed to the repo.

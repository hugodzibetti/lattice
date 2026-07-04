# Lattice

Blazing-fast, size-efficient, backward-compatible serializer for Roblox Instance property values to compact binary format.

## Design Goals

- **Speed** — maximal optimizations; varint encoding, default-value elision, columnar layouts
- **Backward compatibility** — versioned schema registry with translation maps for API-dump changes
- **Polished** — strict types, `--!native --!optimize 2` on hot paths, organized modules

## Architecture

Three layers:

| Layer      | Path          | Purpose                                                                             |
| ---------- | ------------- | ----------------------------------------------------------------------------------- |
| Buffer I/O | `src/buffer/` | `Writer` / `Reader` — growable binary buffer with varint, zigzag, float, string ops |
| Codecs     | `src/serde/`  | 26+ leaf modules implementing `Codec<T>`: `write(writer, value)` / `read(reader)`   |
| Container  | (planned)     | Header, string table, tag table, columnar class blocks                              |

### Codec interface

```luau
export type Codec<T> = {
    write: (writer: Writer.Writer, value: T) -> (),
    read: (reader: Reader.Reader) -> T,
}
```

### Key optimizations

- **Varint (LEB128)** for counts, ids, indices — small numbers compress to 1 byte
- **No per-value type tags** — artifact (build-time metadata) already knows types, codecs run branchless
- **Default-value elision** — instance layer compares `value == artifactDefault` directly
- **CFrame** — 24 axis-aligned rotations map to 1-byte index; arbitrary rotations use 9×f32
- **Color3** — channels → u8 each (matches Roblox's 8-bit internal storage, zero precision loss)
- **EnumItem** — serializes `.Value` (Roblox's backward-compat guarantee), not position or name

## Commands

```bash
# Requires rokit + PATH
export PATH="$HOME/.rokit/bin:$HOME/.local/bin:$PATH"

# Install dependencies
pesde install

# Run all tests
pesde run test

# Run tests directly (verbose)
lune run scripts/RunTests.luau
```

## Require Aliases

Defined in `.luaurc`:

| Alias        | Path             |
| ------------ | ---------------- |
| `@src/`      | `src/`           |
| `@packages/` | `lune_packages/` |
| `@tests/`    | `tests/`         |

## Testing

Unit tests are round-trip: serialize value → read back → assert equality. Uses [`frktest`](https://github.com/boatbomber/frktest) via Lune. Roblox types tested with `@lune/roblox` (standalone, no place file needed).

## Roadmap

1. **Artifact system** (`src/artifacts/`) — pre-compute class metadata from Roblox API dump
2. **Format/Container** (`src/format/`) — header, string table, tag table, columnar class blocks
3. **Instance layer** (`src/instance/`) — traverse → index, serialize/deserialize, optimize
4. **Compat system** (`src/compat/`) — versioned schema registry + translation maps
5. **Integration** — wire all specs, central serde registry, publishing pipeline

## Code Style

- `--!strict` at top of every module
- `--!native --!optimize 2` on hot-path serde modules
- No comments unless the _why_ is non-obvious
- Explicit type signatures; `local x: Type = ...`

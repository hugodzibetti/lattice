# Lattice — Agent Instructions

## Quick Start

```bash
# One-time: add rokit bin to PATH
export PATH="$HOME/.rokit/bin:$HOME/.local/bin:$PATH"

# Install toolchain (lune, pesde, darklua) and dependencies
pesde install

# Run all tests
pesde run test
# or equivalent:
lune run scripts/RunTests.luau
```

## Commands

| Command                                                      | Purpose                                         |
| ------------------------------------------------------------ | ----------------------------------------------- |
| `pesde install`                                              | Install toolchain + dependencies                |
| `pesde run test`                                             | Run all tests via frktest/Lune                  |
| `lune run scripts/RunTests.luau`                             | Run all tests (same as above, verbose)          |
| `lune run bench/Run.luau`                                    | Run performance benchmarks                      |
| `lune run src/artifacts/build/Run.luau [dumpPath] [outPath]` | Build binary artifact from Roblox API dump JSON |

### Artifact generation note

`pesde.toml` references `scripts/GenerateArtifacts.luau` in its `[scripts]` block, but that file does **not** exist. The actual artifact build entry point is `src/artifacts/build/Run.luau`.

## Key Architecture

### Directory layout

```
lattice/
├── src/
│   ├── init.luau              # Public API: Writer, Reader, serde
│   ├── types.luau             # Shared Codec<T> type
│   ├── buffer/
│   │   ├── Writer.luau         # Growable binary writer (u8/u16/u32, f32/f64, varint, zigzag, string, bytes)
│   │   └── Reader.luau         # Mirror of Writer
│   ├── serde/                  # 27 codec modules (leaf modules + 2 combinators)
│   │   ├── init.luau           # Registry: codecIdToModule, codecIdToFactory, codecNameToId
│   │   ├── f32.luau, f64.luau, bool.luau, string.luau  # primitives
│   │   ├── array.luau, option.luau  # combinators (factories)
│   │   └── [type].luau         # cframe, color3, brickColor, vector2/3, udim/udim2, enumItem, etc.
│   └── artifacts/
│       ├── types.luau          # PropertyMetadata, ClassMetadata, ArtifactData, etc.
│       ├── Artifact.luau       # Runtime loader: Artifact.load(artifactBuffer) -> ArtifactData
│       └── build/
│           ├── parseDump.luau   # Parse Roblox API dump JSON -> ClassDef[]
│           ├── resolveType.luau # Map Roblox type name -> codec ID
│           ├── buildArtifact.luau # ClassDef[] -> binary artifact buffer (magic "LATA")
│           └── Run.luau         # CLI: lune run ... [dumpPath] [outPath]
├── tests/                      # 16 spec files (frktest framework)
├── bench/                      # Performance benchmarking
├── scripts/
│   └── RunTests.luau           # Test runner (requires all * .spec.luau)
├── docs/
│   ├── glossary.md             # Terminology reference (varint, bitmask, RLE, columnar, etc.)
│   ├── examples/               # Supplementary examples (varint, bitmask, RLE, columnar-vs-row, format-binary)
│   └── superpowers/
│       └── specs/              # Design documents (ADRs)
├── pesde.toml                  # Package manifest (pesde, not wally)
├── rokit.toml                  # Toolchain: lune, pesde, darklua
└── .luaurc                     # Strict mode + require aliases (@src, @packages, @tests)
```

### Layers

1. **Buffer I/O** (`src/buffer/`) — fixed-width, varint (LEB128), zigzag, float, string, bytes
2. **Codecs** (`src/serde/`) — each module exports `{ write: (Writer, T) -> (), read: (Reader) -> T }`. Leaves are independent; combinators (`array`, `option`) are factories.
3. **Artifacts** (`src/artifacts/`) — pre-compute class metadata (properties, defaults, codec IDs) from Roblox API dump, store as versioned binary (`LATA` magic + u16 version=1).
4. **Format** (`src/format/`) — [next] binary container: string table, tag table, columnar class blocks with per-column encoding (raw, RLE). See `docs/superpowers/specs/2026-07-04-format-layer-design.md`.
5. **Instance** (`src/instance/`) — [next] tree traversal, class bucketing, drives format writer/reader.

### Require aliases (from `.luaurc`)

| Alias       | Resolves to     |
| ----------- | --------------- |
| `@src`      | `src`           |
| `@packages` | `lune_packages` |
| `@tests`    | `tests`         |

Use these everywhere: `require("@src/buffer/Writer")`, `require("@packages/frktest")`, `require("@tests/SerdeCFrame.spec")`.

### Codec ID registry (`src/serde/init.luau`)

| ID  | Codec                  | Type    |
| --- | ---------------------- | ------- |
| 0   | f32                    | leaf    |
| 1   | f64                    | leaf    |
| 2   | bool                   | leaf    |
| 3   | string                 | leaf    |
| 4   | array                  | factory |
| 5   | option                 | factory |
| 6   | cframe                 | leaf    |
| 7   | color3                 | leaf    |
| 8   | brickColor             | leaf    |
| 9   | colorSequence          | leaf    |
| 10  | colorSequenceKeypoint  | leaf    |
| 11  | numberRange            | leaf    |
| 12  | numberSequence         | leaf    |
| 13  | numberSequenceKeypoint | leaf    |
| 14  | udim                   | leaf    |
| 15  | udim2                  | leaf    |
| 16  | vector2                | leaf    |
| 17  | vector3                | leaf    |
| 18  | rect                   | leaf    |
| 19  | axes                   | leaf    |
| 20  | faces                  | leaf    |
| 21  | physicalProperties     | leaf    |
| 22  | font                   | leaf    |
| 23  | content                | leaf    |
| 24  | uniqueId               | leaf    |
| 25  | enumItem               | leaf    |

### Code style conventions

- `--!strict` at top of **every** module
- `--!native --!optimize 2` on hot-path serde modules
- No comments unless the **why** is non-obvious (hidden constraint, workaround, subtle invariant)
- Explicit type annotations in function signatures
- One codec per file; codecs never depend on other codecs (except combinators which take codecs as arguments)

### Testing patterns

- **Round-trip**: serialize value → read back → assert equality
- **Framework**: frktest (`@packages/frktest`) — `test.suite()`, `test.case()`, `check.equal()`
- **Roblox types**: use `require("@lune/roblox")` (Lune's built-in binding, standalone, no place file needed)
- **Combinator tests**: use inline dummy codecs to avoid cross-PR dependencies

## Verification commands available

| Category                   | Command                                             | Status                                     |
| -------------------------- | --------------------------------------------------- | ------------------------------------------ |
| Test                       | `pesde run test` / `lune run scripts/RunTests.luau` | ✅ Working                                 |
| Benchmark                  | `lune run bench/Run.luau`                           | ✅ Working                                 |
| Artifact build             | `lune run src/artifacts/build/Run.luau`             | ✅ Working                                 |
| Lint                       | —                                                   | ❌ **Missing**                             |
| Typecheck (standalone CLI) | —                                                   | ❌ **Missing** (only via VS Code Luau LSP) |
| Format                     | —                                                   | ❌ **Missing**                             |

### Gaps

1. **No linting**: `.vscode/extensions.json` recommends `selene-vscode` but there is no `selene.toml` configuration in the project. No luacheck, stylua, or any other linter configured.
2. **No standalone typecheck**: Luau strict mode is enabled (`.luaurc` has `languageMode: strict`, all files have `--!strict`), but there is no `luau analyze` or equivalent CLI command to verify the codebase. Type checking only happens via the VS Code Luau LSP extension interactively.
3. **No code formatter**: No stylua or equivalent configured.
4. **Dead script reference**: `pesde.toml` line 20 references `scripts/GenerateArtifacts.luau` in the `[scripts]` block, but that file does not exist. The actual artifact builder is `src/artifacts/build/Run.luau`.

## Pitfalls

- **Path must include rokit**: `export PATH="$HOME/.rokit/bin:$HOME/.local/bin:$PATH"` is required before running any command. VS Code tasks handle this via `options.env`.
- **`@lune/*` requires work only under Lune**: `@lune/roblox`, `@lune/process`, etc. are Lune built-in modules. They will not work in Roblox Studio directly.
- **`@src/...` aliases are Lune-only**: For Roblox deployment, use `darklua` to convert aliases to relative paths. This has not been set up yet.
- **frktest requires calling the returned function**: Test modules return a function — e.g. `require("@tests/Buffer.spec")()`. Forgetting the `()` call means tests silently don't run.
- **`lune_packages/` is gitignored**: After cloning, always run `pesde install` to regenerate the `lune_packages/` directory from the lockfile.
- **Default elision is the instance layer's job**: Codecs never see defaults; they only handle wire format serialization. The comparison `value == artifactDefault` happens above the codec layer.
- **No per-value type tags in property blocks**: The artifact already knows types at build time, so codecs run without branching — each property has a fixed codec assigned at artifact-build time.
- **CFrame uses 24-axis optimization**: Axis-aligned rotations (90-degree multiples) map to a 1-byte index; arbitrary rotations use 9 f32 components.
- **Color3 channels are u8**: This matches Roblox's 8-bit internal storage, meaning zero precision loss.
- **EnumItem serializes `.Value`**, not position or name, relying on Roblox's backward-compatibility guarantee.

## Design Docs

| Document                                                       | Topic                                             |
| -------------------------------------------------------------- | ------------------------------------------------- |
| `docs/superpowers/specs/2026-07-02-codec-benchmarks-design.md` | Codec design & benchmarks                         |
| `docs/superpowers/specs/2026-07-04-artifact-system-design.md`  | Artifact system (✅ implemented)                  |
| `docs/superpowers/specs/2026-07-04-format-layer-design.md`     | Format container, columnar blocks, bitmasks, RLE  |
| `docs/glossary.md`                                             | Terminology: varint, bitmask, RLE, columnar, etc. |
| `docs/examples/`                                               | Supplementary examples for each concept           |

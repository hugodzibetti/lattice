# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: Lattice (Roblox Instance Serializer)

A blazing-fast, size-efficient, backward-compatible serializer for Roblox Instance property values to compact binary format. Three core non-negotiables: **speed** (max optimizations), **backward compatibility** (versionable schema), **polished** (strict types, organized modules).

## Commands

```bash
# Requires rokit + PATH setup
export PATH="$HOME/.rokit/bin:$HOME/.local/bin:$PATH"

# Install dependencies
pesde install

# Run all tests via frktest/Lune
pesde run test
lune run scripts/RunTests.luau  # same thing, verbose

# Run a single test file (for development)
lune run tests/_scratch_run.luau  # see tests/*.spec.luau for pattern
```

## Architecture

### Three layers

**Buffer I/O (`src/buffer/`)**

- `Writer.luau`: growable binary writer. Wraps Luau's `buffer` type with auto-doubling capacity.
  - Methods: `u8/u16/u32`, `i8/i16/i32`, `f32/f64`, `bool`, `varint` (unsigned LEB128), `varintSigned` (zigzag), `string`, `bytes`.
  - Key insight: varint is used for counts, ids, indices; small numbers compress to 1 byte.
- `Reader.luau`: mirrors Writer exactly. Tracks position; exposes `remaining()`.

**Codecs (`src/serde/`)**

- All 26+ modules (e.g. `f32.luau`, `cframe.luau`, `enumItem.luau`) implement the `Codec<T>` interface:
  ```luau
  export type Codec<T> = {
    write: (writer: Writer.Writer, value: T) -> (),
    read: (reader: Reader.Reader) -> T,
  }
  ```
- Each codec is leaf: no dependencies on other codecs (design choice for parallelization).
- **Exception**: combinators (`array.luau`, `option.luau`) are factories: `array(elemCodec) -> Codec<{T}>`.

**Serialization patterns**

- **No per-value type tags in property blocks**: the artifact (build-time metadata) already knows types. Codecs run without branching.
- **Default-value elision**: instance layer compares `value == artifactDefault` directly; codecs never see defaults.
- **Float precision**: f32 for bulk numeric properties (position, size, scale); f64 only where required (override flag in artifact, not yet built).
- **CFrame optimization**: the 24 axis-aligned (90° rotations) map to a 1-byte index (matching Roblox's `.rbxm` trick); arbitrary rotations use 9 f32 components.
- **Color quantization**: Color3 channels → u8 each (8-bit internal storage in Roblox, zero precision loss).
- **Stable enum values**: EnumItem serializes `.Value` (Roblox's backward-compat guarantee), not position or name.

### Testing

**Patterns**:

- Unit tests are round-trip: serialize value → read back → assert equality.
- Tests for Roblox types use `require("@lune/roblox")` (Lune's built-in binding; works standalone, no place file needed).
- For generic combinators (array, option), tests include an inline dummy codec to avoid cross-PR dependencies.

**Running**:

- `pesde run test` loads all 20 test specs and runs them via frktest's lune reporter.
- All specs wired into `scripts/RunTests.luau`: Buffer, Serde (11 types + Referent), Artifact, Format, Instance, Compat.

## Require Aliases

Defined in `.luaurc`:

```json
"aliases": {
  "src": "src",
  "packages": "lune_packages",
  "tests": "tests"
}
```

Use `@src/buffer/Writer`, `@packages/frktest`, `@tests/SomeName` everywhere. This works natively under Lune; publishing to Roblox uses darklua to convert `@src/...` to relative paths.

## Code Style

- `--!strict` at top of every module (type checking).
- `--!native --!optimize 2` on hot-path serde modules (codec implementations).
- No comments unless the **why** is non-obvious (hidden constraint, workaround, subtle invariant).
- Prefer explicit types in function signatures; use `local x: Type = ...` for clarity.

## Key Design Decisions

1. **Modularity**: each codec is a small (~20–50 line), independent file. Enables parallel development and clean merges.
2. **Varint for variable-length data**: ids, counts, indices use LEB128 (zigzag for signed). Huge win for small values.
3. **No runtime reflection**: all type information is resolved at artifact-build time or codecs are written with knowledge of their type.
4. **Columnar/SoA for class blocks**: ✅ instances grouped by class, properties stored as columns with per-column encoding (raw, RLE, AllDefault, AllNonDefault). Enables compression and delta encoding.
5. **Backward compat via versioned schema**: ✅ files include schemaVersion in header; migration registry in `src/compat/` provides hooks for future API-dump changes.

## Design Docs

- `docs/superpowers/specs/2026-07-02-codec-benchmarks-design.md` — codec design & benchmarks ✅ (benchmark harness complete)
- `docs/superpowers/specs/2026-07-04-artifact-system-design.md` — artifact system design ✅ (fully implemented)
- `docs/superpowers/specs/2026-07-04-format-layer-design.md` — format container, columnar layout, bitmasks, RLE ✅ (fully implemented)
- `docs/glossary.md` — terminology reference (varint, bitmask, RLE, columnar, etc.)
- `docs/examples/` — supplementary examples (varint, bitmask, RLE, columnar-vs-row, format-binary)

## Completed Milestones

1. ✅ **Artifact system** — `src/artifacts/` fully functional, includes build/parse/resolve/load.
2. ✅ **Format/Container** — `src/format/` implements header, string table, columnar class blocks with 4 encodings (raw, RLE, AllDefault, AllNonDefault).
3. ✅ **Instance layer** — `src/instance/` serializes/deserializes Roblox instances with default elision, instance dedup, and template detection.
4. ✅ **Compat system** — `src/compat/` provides versioned schema registry with migration hooks.
5. ✅ **Integration** — all 20 test specs wired; central serde registry at `src/serde/init.luau` (27 codecs + factories).
6. ✅ **Roblox Package Polish** — darklua wired for `@src/...` → relative path conversion; standalone Roblox package export ready.
7. ✅ **Performance Tuning** — profiled benchmarks; 14 serializations/sec, 5 deserializations/sec on 500-instance models; 16 bytes/instance avg with dedup.
8. ✅ **Documentation & Examples** — user guide (serialize/deserialize API), end-to-end example, supplementary examples (varint, bitmask, RLE, columnar layout, binary format).

## Current Work

Lattice is feature-complete for core use cases (serialize/deserialize instance trees, dedup, compress). Five design specs are written and ready to build (each self-contained enough to hand to a separate session/`batch`). Recommended build order, with rationale:

1. **Extended Codec Coverage** — `docs/superpowers/specs/2026-07-05-extended-codec-coverage-design.md`. No dependencies. Grounded in the real `data/api-dump.json` gap (not guesswork): `ProtectedString`/`ContentId` are one-line string-codec aliases, `Ray` is a small new codec (for `RayValue.Value`). **`SecurityCapabilities` (89% of the gap by count) is blocked upstream by Lune** — it can't read the property at all — documented as a known limitation, not attempted.
2. **Column Dictionary Encoding** — `docs/superpowers/specs/2026-07-05-column-dictionary-encoding-design.md`. Adds a 5th column encoding mode that captures repeated-but-shuffled values RLE misses (measured 69–87.5% smaller in realistic cases). Also the vehicle for evaluating whether whole-instance dedup (`templateRefs`) is still worth its O(n²) scan + per-instance overhead once this lands — likely removable, pending the benchmark the spec calls for.
3. **Schema Evolution Design** — `docs/superpowers/specs/2026-07-05-schema-evolution-design.md`. Wires the existing `src/compat/` registry into the actual read path for the first time (`Reader.luau` currently hard-asserts `version == 1` and never calls `compat.migrate`). Uses the already-flagged templateRefs-raw-varints-to-RLE change as the first real version bump.
4. **CLI Tooling** — `docs/superpowers/specs/2026-07-05-cli-tooling-design.md`. `lattice dump`/`stats`/`diff` as Lune scripts. Shares an instance-identity-matching problem with #5 below — whichever lands second should reuse the matching function, not reimplement it.
5. **Incremental/Delta Encoding** — `docs/superpowers/specs/2026-07-05-incremental-delta-encoding-design.md`. Most architecturally open-ended; scoped to a bounded MVP (baseline + one patch, property-level granularity, no chained history/conflict resolution). Best done last since it benefits from the wire format being settled by 1–3.

Each spec's own "Non-goals" and "Open decisions for the implementer" sections are load-bearing — read those before implementing, not just the summary above.

## Implementation Notes

- **frktest**: the test framework; minimal but effective. Tests are plain Luau functions that call `test.case()` and `check.equal()`.
- **pesde**: Luau package manager; replaces wally for this project.
- **lune**: Lua/Luau runtime; runs tests and build scripts outside of Roblox Studio.
- **darklua**: AST processor; converts Luau `@alias/...` requires to relative paths for Roblox deployment. Config at `.darklua.json` (PR #17).
- **`SecurityCapabilities` cannot be serialized**: Lune's `roblox` binding errors (`Failed to convert from 'SecurityCapabilities' into 'userdata' - Type not supported`) just reading `Instance.Capabilities` — this is 866 of 971 codec-coverage warnings from a real artifact build, all from one property inherited by every class. Not fixable in this repo; it's an upstream Lune limitation. See `docs/superpowers/specs/2026-07-05-extended-codec-coverage-design.md`.

## Updating This File

After completing work, update CLAUDE.md to reflect:
- Completed milestones moved to "Completed Milestones" section with ✅ checkmarks.
- Current/in-progress work listed under "Current Work" with clear scope & rationale.
- Design decisions or architectural changes documented in the relevant section.
- New gotchas or gotcha resolutions added to "Implementation Notes" for future context.

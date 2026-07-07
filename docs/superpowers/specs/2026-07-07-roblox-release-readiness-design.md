# Roblox Release Readiness Design

## Problem

Lattice is feature-complete on `develop`, but nothing has verified that the published output actually runs inside real Roblox (Studio or a live server/client) rather than just under Lune. Two categories of bugs currently make that untrue:

1. **`@lune/*` requires leak into shipped code.** `src/serde/*.luau` codecs, `src/instance/Serializer.luau`, `src/instance/Deserializer.luau`, and `src/patch/apply.luau` do `require("@lune/roblox")` (and `Serializer`/`Deserializer` also `require("@lune/task")`) to get `Color3`/`Vector3`/`Instance`/`Enum`/`task`, because Lune has no game engine underneath and needs an explicit binding for these. Real Roblox has no `@lune/*` require namespace at all — these are ambient globals there instead. Confirmed live in `dist/lattice/` today (27 files still reference `@lune`); `tests/studio-test.server.luau` (added by the new Rojo/Studio test setup) would fail immediately on `Lattice.Serde.vector3.write(...)`.
2. **Dev-only tooling ships in the package.** `scripts/BuildPackage.luau` runs darklua over all of `src/`, which sweeps in `src/artifacts/build/` (artifact-generation tooling: `@lune/process`, `@lune/fs`, `@lune/serde`) and `src/parallel/Worker.luau` (the superseded Lune-child-process parallel backend: `@lune/process`, `@lune/stdio`). Neither is library code; neither should be in `dist/lattice/`.

Additionally, `origin/master` is currently missing `cli/`, `src/patch/`, and `src/serde/ray.luau` relative to `develop` (an unintentional regression from PR #33, flagged in `docs/branch-cleanup-plan.md`). Releasing from `master` today would ship an incomplete package.

## Goals

- The exact same `src/` source continues to run correctly under Lune (`pesde run test`, CLI) with zero edits.
- The built package (`dist/lattice/`) loads and runs correctly inside real Roblox, verified concretely via the Rojo project + `tests/studio-test.server.luau` in Studio.
- The package is releasable via two channels: a manual/Rojo-syncable folder, and a `pesde publish`-able package.
- `master` is brought back in parity with `develop` before any release is cut from it.

## Non-goals

- No changes to parallel-encoding behavior — the Roblox Actor backend (`src/parallel/RobloxBackend.luau`) and its Lune-fallback path are already correct and out of scope here; this design only concerns build/packaging around them (excluding the now-superseded `Worker.luau`).
- No new CI/automation for cutting releases — this design covers making a release buildable and correct, not automating when/how often one is cut.

## Design

### 1. `@lune/roblox` and `@lune/task` shim via darklua

`.darklua.json`'s existing `convert_require` rule already maps the `@src` alias prefix to a real directory (`sources: { "@src": "./src" }`). The same `path`-mode `sources` mechanism accepts additional prefixes, so `require("@lune/roblox")` (parsed as package `@lune`, subpath `roblox`) can be redirected the same way:

```json
sources: { "@src": "./src", "@lune": "./release-shims" }
```

Two new checked-in files, used only by the darklua build (never touched by Lune, which resolves `@lune/*` natively on its own):

- `release-shims/roblox.luau` — returns a table of the real Roblox engine globals the codecs/instance layer actually use: `{ Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Instance = Instance, Enum = Enum, UDim = UDim, UDim2 = UDim2, Rect = Rect, ... }` (exact field list = whatever `roblox.X` accesses currently exist across the codecs). Since every current use is `roblox.X.new(...)` or `roblox.Enum`, a flat table of globals slots in transparently — no call-site rewrites needed.
- `release-shims/task.luau` — `return task` (already an ambient global in real Roblox).

No edits to any file under `src/`. `pesde run test` and the CLI are unaffected because Lune resolves `@lune/roblox`/`@lune/task` through its own builtin binding, never through `.darklua.json`.

### 2. Exclude dev-only trees from the build

`scripts/BuildPackage.luau` currently runs `darklua process src dist/lattice`. Change it to process only the publishable subset — exclude `src/artifacts/build/` and `src/parallel/Worker.luau` before invoking darklua (e.g. copy `src/` minus those paths into a staging dir, or pass explicit include paths if darklua's CLI supports it) — mirroring how `cli/` is already excluded by simply not being under `src/`.

### 3. Two release channels from one build

- **Manual / Rojo**: `dist/lattice/` as built above; already wired into `default.project.json` (`ReplicatedStorage.Lattice`). No further work needed once (1) and (2) land.
- **pesde publish**: pesde has no build/prepare hook — `pesde publish` packages whatever matches `includes` verbatim from the working directory. Raw `src/` (with `@src/...` / `@lune/...` requires) can't be published as-is. `BuildPackage.luau` additionally writes a minimal `pesde.toml` into `dist/lattice/` (name/version/license/description copied from the root manifest, `target = { environment = "roblox", lib = "init.luau" }`, `includes` covering the built files), and `pesde publish` is run with `dist/lattice/` as the working directory, not the repo root.

### 4. Master reconciliation

Before cutting any release from `master`: reconcile `develop` → `master` per `docs/branch-cleanup-plan.md` Phase 3, Option A (PR merging reconciled `develop` into `master`), so `master` regains `cli/`, `src/patch/`, and `src/serde/ray.luau`. This is a prerequisite, not part of the build-pipeline work itself.

### 5. Verification

Rebuild `dist/lattice/` with the above changes, sync via the existing Rojo project into a real Roblox Studio session, and confirm `tests/studio-test.server.luau` prints all three `✓` lines with no errors. This is the concrete pass/fail signal for the whole design — static analysis (grepping for `@lune` in `dist/`) is a useful intermediate check but Studio execution is what actually proves it.

## Testing

- Existing `pesde run test` suite must stay green (proves `src/` is untouched and still correct under Lune).
- New: a lightweight check (script or manual step) that `dist/lattice/` contains zero `@lune` references after build, catching future regressions if a new codec/module adds an unshimmed `@lune/*` require.
- `tests/studio-test.server.luau` passing in actual Studio is the release-readiness acceptance criterion.

# Lattice Benchmark Results

Real-world serialization performance data for the Lattice Roblox Instance serializer.

## Quick View

**Tiny Scene** (835 instances)
- Size: 28 KB
- Serialization: 146 ms
- Deserialization: 2.3 ms

**Large Scene** (17,762 instances)
- Size: 372 KB
- Serialization: 3.1 sec
- Deserialization: 46 ms

## Files

- `SUMMARY.txt` - Quick reference of key metrics
- `BENCHMARK_REPORT.md` - Detailed analysis with methodology
- `tiny-scene.lattice` - Serialized benchmark model (29 KB)
- `large-scene.lattice` - Serialized benchmark model (373 KB)

## Analyze Generated Data

View size breakdown by class:
```bash
lune run cli/Main.luau stats bench/results/tiny-scene.lattice data/artifact.bin
lune run cli/Main.luau stats bench/results/large-scene.lattice data/artifact.bin
```

View encoding decisions per property:
```bash
lune run cli/Main.luau dump bench/results/tiny-scene.lattice data/artifact.bin
```

Compare two versions (before/after optimization):
```bash
lune run cli/Main.luau diff before.lattice after.lattice data/artifact.bin
```

## Regenerate Benchmarks

To create new benchmark data:
```bash
lune run bench/RealWorldBench.luau
```

This will generate fresh `.lattice` files in `bench/results/` with current timing data.

## Key Insights

✅ **Size efficiency**: 21-34 bytes per instance (improves with property repetition)
✅ **Deserialization**: 70x faster than serialization (nearly I/O-bound)
✅ **Scaling**: Linear throughput ~5,600 instances/sec serialization
✅ **Format**: v2 with RLE, Dictionary, AllDefault, AllNonDefault encodings
✅ **Verified**: Round-trip deserialize confirms data integrity

See `BENCHMARK_REPORT.md` for full analysis, methodology, and future work.

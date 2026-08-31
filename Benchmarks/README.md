# Wift benchmarks

This directory contains local end-to-end benchmarks for the user-visible cost of running a Swift script through `wift`. The suite uses [Ordo One Benchmark](https://github.com/ordo-one/benchmark) for iteration control, percentiles, filtering, baselines, comparisons, and result export. A separate process harness launches the commands being measured.

The suite is intentionally local-only. It does not define performance thresholds or gate CI.

## What the suite answers

The benchmarks are organized around four questions:

1. How much startup latency does `wift` add over an already cached executable?
2. How expensive are the different cache transitions?
3. What peak resident memory does the launched process tree require?
4. How much logical and allocated disk space does each cache transition add?

All commands use a release build of `wift`. Before a run, the wrapper prints the Git revision, architecture, macOS version, Xcode version, and Swift toolchain so results can be compared under equivalent conditions.

## Running benchmarks

Install the pinned development tools, then list or run the suite:

```bash
mise install
mise run benchmark -- list
mise run benchmark
```

Arguments after `--` are passed to `swift package benchmark`. Filter by benchmark name to keep development runs short:

```bash
mise run benchmark -- --filter 'Latency/Startup'
mise run benchmark -- --filter 'Latency/Cache'
mise run benchmark -- --filter 'Latency/Contention'
mise run benchmark -- --filter 'Resource/RSS'
mise run benchmark -- --filter 'Footprint'
```

The benchmark command first builds the `wift` product in release mode, exports its path as `WIFT_BENCHMARK_BINARY`, prints the environment, and then runs only the `WiftBenchmarks` target.

## Scenario catalogue

### Startup latency

These scenarios use a minimal script that produces no output. Standard output and standard error are redirected to `/dev/null` by the process harness.

| Benchmark | State being measured | Purpose |
| --- | --- | --- |
| `Latency/Startup/wift-cache-hit` | Executable and canonical-path association already exist | Measures the complete common `wift` path, including CLI startup, source/toolchain fingerprinting, cache lookup, and `exec` |
| `Latency/Startup/cached-executable` | The executable produced by `wift` is launched directly | Lower bound for Swift executable startup and the reference for `wift` overhead |
| `Latency/Startup/swift-warm` | The isolated Swift module cache is prepared once and reused | Comparison with repeated `swift script.swift` launches |
| `Latency/Startup/swift-cold` | A new isolated Swift module cache is created for every sample | Cost of ordinary Swift without a prepared module cache |
| `Latency/Startup/shell` | Equivalent no-output `/bin/sh` script | Process-startup reference only; it is not a language-performance comparison |

Frequent startup scenarios perform three warmup iterations and collect up to 1,000 samples or three seconds. Their most useful values are p50, p90, and p99. The cold Swift scenario collects five samples without benchmark warmup; inspect min, median, p90, and max.

### Cache transitions

| Benchmark | Prepared state | Expected result |
| --- | --- | --- |
| `Latency/Cache/full-cold-miss` | Empty `WIFT_CACHE_DIR` | Support module and script are compiled; exactly one executable remains |
| `Latency/Cache/support-warm-script-miss` | Support and module caches are populated by another script | Only the new script executable is compiled; two executables remain |
| `Latency/Cache/new-path-association` | The same content is already cached under another canonical path | A path association is added without creating another executable |
| `Latency/Cache/source-invalidation` | The original script is cached, then its bytes change | A new executable is published while the old content-addressed entry remains |

Cold and source-mutating scenarios create a private fixture for each of five samples. The association scenario keeps one prepared fixture across frequent iterations and writes a new path with identical source bytes for every sample.

### Contention

`Latency/Contention/2-callers-same-cold-key` and `Latency/Contention/8-callers-same-cold-key` launch all callers before waiting for any of them. Every process targets the same script and empty cache.

The scenario succeeds only when every caller exits successfully and the cache contains one completed executable. It therefore measures both elapsed contention cost and the observable single-publication contract.

### Process-tree peak RSS

The `Resource/RSS/*` group repeats the startup comparisons and the full cold miss using the custom `Process tree peak RSS (bytes)` metric.

The process harness samples the root process and all discoverable descendants every millisecond and records the maximum simultaneous sum of their resident sizes. The root process's `ru_maxrss` is used as a lower-bound safeguard for commands that finish between samples.

RSS is intentionally measured in a separate group. Sampling is not enabled for latency scenarios because it changes their timing. Benchmark's built-in process memory, allocation, ARC, CPU, and syscall metrics are also not used: for these end-to-end cases they describe the benchmark host process rather than the launched process tree.

### Cache footprint

The `Footprint/*` group records the resulting cache state or its delta after a transition:

| Metric | Meaning |
| --- | --- |
| `Cache logical size` | Sum of file lengths |
| `Cache allocated size` | Blocks allocated on disk |
| `Executable cache size` | Cached executable bytes |
| `Support cache size` | Compiled support-module bytes |
| `Module cache size` | Swift/Clang module-cache bytes |
| `Metadata size` | Entry metadata, path associations, and other managed files |
| `Executable count` | Number of completed cached executables |
| `Support context count` | Number of compiled support contexts |
| `Module context count` | Number of immediate module-cache contexts |
| `Path association count` | Number of canonical-path association records |

`Footprint/full-cold-cache` reports the complete first-run cache. The incremental executable, path association, and source invalidation scenarios report the difference from their prepared state, making the marginal storage cost visible.

The existing `mise run support-size` task remains the fast deterministic report for embedded source and artifact sizes. Statistical footprint benchmarks do not replace it.

## Isolation and validation

Each fixture lives in a mode-`0700` `wift-benchmark-<UUID>` directory under the system temporary directory. It contains source fixtures, an isolated `WIFT_CACHE_DIR`, and an isolated Swift module cache. Fixtures are removed by benchmark teardown or `defer`, including failure paths.

Measured commands are passed directly to `posix_spawn`; arguments and environment values are never interpreted by a shell. Standard input, output, and error point to `/dev/null`. `wait4` supplies termination status and root resource usage. A non-zero exit status fails the benchmark.

Scenarios also validate the cache state implied by their names. For example, a cache hit must not create another executable, an association-only transition must retain one executable, and concurrent misses must publish one completed entry.

## Interpreting results

`cold` means a new managed `wift` cache or Swift module cache. The suite does not flush the macOS filesystem page cache and does not attempt to reproduce a rebooted machine.

Only compare runs made with the same macOS, architecture, Xcode/Swift toolchain, power mode, and broadly equivalent system load. Prefer percentiles to averages for startup latency. Small changes should be confirmed with repeated baselines before being treated as regressions or improvements.

## Baselines and exports

Create two local baselines and compare them on the same machine:

```bash
git switch main
mise run benchmark -- baseline update main

git switch my-change
mise run benchmark -- baseline update candidate
mise run benchmark -- baseline compare candidate main
```

Delete local baselines when they are no longer useful:

```bash
mise run benchmark -- baseline delete main candidate
```

`.benchmarkBaselines/` is intentionally ignored. Benchmark does not consider its internal baseline representation a stable storage format. Export a standardized or raw format for long-lived results, for example:

```bash
mkdir -p BenchmarkResults
mise run benchmark -- run --format histogramPercentiles --path BenchmarkResults --no-progress
```

`histogramSamples` is also available when downstream processing needs the raw samples.

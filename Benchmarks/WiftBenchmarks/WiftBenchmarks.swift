import Benchmark

let benchmarks: @Sendable () -> Void = {
    let runtime = BenchmarkRuntime()

    StartupBenchmarks.register(in: runtime)
    CacheBenchmarks.register(in: runtime)
    ContentionBenchmarks.register(in: runtime)
    ResourceBenchmarks.register(in: runtime)
    FootprintBenchmarks.register(in: runtime)
}

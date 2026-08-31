import Benchmark

enum ContentionBenchmarks {
    static func register(in runtime: BenchmarkRuntime) {
        for callerCount in [2, 8] {
            Benchmark(
                "Latency/Contention/\(callerCount)-callers-same-cold-key",
                configuration: BenchmarkConfigurations.cold
            ) { benchmark in
                try runtime.withFixture { fixture in
                    let commands = Array(
                        repeating: fixture.wiftCommand(script: fixture.primaryScript),
                        count: callerCount
                    )
                    benchmark.startMeasurement()
                    let measurements = try runtime.runner.runConcurrently(commands)
                    benchmark.stopMeasurement()
                    try runtime.require(measurements.count == callerCount, "not every concurrent caller completed")
                    try runtime.require(fixture.executableCount() == 1, "concurrent miss published multiple executables")
                }
            }
        }
    }
}

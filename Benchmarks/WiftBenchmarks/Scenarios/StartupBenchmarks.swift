import Benchmark

enum StartupBenchmarks {
    static func register(in runtime: BenchmarkRuntime) {
        runtime.frequentCommandBenchmark(
            "Latency/Startup/wift-cache-hit",
            prepare: { fixture in
                try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            },
            command: { fixture in
                fixture.wiftCommand(script: fixture.primaryScript)
            },
            validate: { fixture in
                try runtime.require(fixture.executableCount() == 1, "cache hit created an executable")
            }
        )

        runtime.frequentCommandBenchmark(
            "Latency/Startup/cached-executable",
            prepare: { fixture in
                try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            },
            command: { fixture in
                try BenchmarkCommand(executable: fixture.cachedExecutable().path)
            }
        )

        runtime.frequentCommandBenchmark(
            "Latency/Startup/swift-warm",
            prepare: { fixture in
                try runtime.runner.run(fixture.swiftCommand(script: fixture.primaryScript))
            },
            command: { fixture in
                fixture.swiftCommand(script: fixture.primaryScript)
            }
        )

        runtime.frequentCommandBenchmark(
            "Latency/Startup/shell",
            command: { fixture in
                fixture.shellCommand
            }
        )

        Benchmark("Latency/Startup/swift-cold", configuration: BenchmarkConfigurations.cold) { benchmark in
            try runtime.withFixture { fixture in
                benchmark.startMeasurement()
                try runtime.runner.run(fixture.swiftCommand(script: fixture.primaryScript))
                benchmark.stopMeasurement()
            }
        }
    }
}

import Benchmark
import Foundation

enum CacheBenchmarks {
    static func register(in runtime: BenchmarkRuntime) {
        Benchmark("Latency/Cache/full-cold-miss", configuration: BenchmarkConfigurations.cold) { benchmark in
            try runtime.withFixture { fixture in
                benchmark.startMeasurement()
                try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
                benchmark.stopMeasurement()
                try runtime.require(fixture.executableCount() == 1, "cold miss did not create one executable")
            }
        }

        Benchmark("Latency/Cache/support-warm-script-miss", configuration: BenchmarkConfigurations.cold) { benchmark in
            try runtime.withFixture { fixture in
                try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
                try fixture.write(FixtureSource.alternate, to: fixture.secondaryScript)
                benchmark.startMeasurement()
                try runtime.runner.run(fixture.wiftCommand(script: fixture.secondaryScript))
                benchmark.stopMeasurement()
                try runtime.require(fixture.executableCount() == 2, "script miss did not create a second executable")
            }
        }

        registerPathAssociationBenchmark(in: runtime)

        Benchmark("Latency/Cache/source-invalidation", configuration: BenchmarkConfigurations.cold) { benchmark in
            try runtime.withFixture { fixture in
                try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
                try fixture.write(FixtureSource.alternate, to: fixture.primaryScript)
                benchmark.startMeasurement()
                try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
                benchmark.stopMeasurement()
                try runtime.require(fixture.executableCount() == 2, "source invalidation did not retain two variants")
            }
        }
    }

    private static func registerPathAssociationBenchmark(in runtime: BenchmarkRuntime) {
        let holder = FixtureHolder()
        Benchmark(
            "Latency/Cache/new-path-association",
            configuration: BenchmarkConfigurations.frequent,
            closure: { benchmark in
                let fixture = try holder.requireFixture()
                let script = fixture.root.appendingPathComponent("association-\(benchmark.currentIteration).swift")
                try fixture.write(FixtureSource.minimal, to: script)
                benchmark.startMeasurement()
                try runtime.runner.run(fixture.wiftCommand(script: script))
                benchmark.stopMeasurement()
                try runtime.require(fixture.executableCount() == 1, "association-only hit compiled another executable")
            },
            setup: {
                let fixture = try BenchmarkFixture()
                do {
                    try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
                    holder.store(fixture)
                } catch {
                    fixture.remove()
                    throw error
                }
            },
            teardown: {
                holder.removeFixture()
            }
        )
    }
}

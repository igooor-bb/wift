enum FootprintBenchmarks {
    static func register(in runtime: BenchmarkRuntime) {
        runtime.footprintBenchmark("Footprint/full-cold-cache") { fixture in
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            return try CacheFootprint.capture(cache: fixture.cache)
        }
        runtime.footprintBenchmark("Footprint/incremental-executable") { fixture in
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            let before = try CacheFootprint.capture(cache: fixture.cache)
            try fixture.write(FixtureSource.alternate, to: fixture.secondaryScript)
            try runtime.runner.run(fixture.wiftCommand(script: fixture.secondaryScript))
            return try CacheFootprint.capture(cache: fixture.cache).subtracting(before)
        }
        runtime.footprintBenchmark("Footprint/incremental-path-association") { fixture in
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            let before = try CacheFootprint.capture(cache: fixture.cache)
            try runtime.runner.run(fixture.wiftCommand(script: fixture.secondaryScript))
            let after = try CacheFootprint.capture(cache: fixture.cache)
            try runtime.require(
                after.executableCount == 1,
                "association footprint found \(after.executableCount) executables"
            )
            return after.subtracting(before)
        }
        runtime.footprintBenchmark("Footprint/source-invalidation") { fixture in
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            let before = try CacheFootprint.capture(cache: fixture.cache)
            try fixture.write(FixtureSource.alternate, to: fixture.primaryScript)
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            return try CacheFootprint.capture(cache: fixture.cache).subtracting(before)
        }
    }
}

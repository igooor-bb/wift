enum ResourceBenchmarks {
    static func register(in runtime: BenchmarkRuntime) {
        runtime.resourceBenchmark("Resource/RSS/wift-cache-hit") { fixture in
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            return fixture.wiftCommand(script: fixture.primaryScript)
        }
        runtime.resourceBenchmark("Resource/RSS/wift-full-cold-miss") { fixture in
            fixture.wiftCommand(script: fixture.primaryScript)
        }
        runtime.resourceBenchmark("Resource/RSS/cached-executable") { fixture in
            try runtime.runner.run(fixture.wiftCommand(script: fixture.primaryScript))
            return try BenchmarkCommand(executable: fixture.cachedExecutable().path)
        }
        runtime.resourceBenchmark("Resource/RSS/swift-warm") { fixture in
            let command = fixture.swiftCommand(script: fixture.primaryScript)
            try runtime.runner.run(command)
            return command
        }
        runtime.resourceBenchmark("Resource/RSS/swift-cold") { fixture in
            fixture.swiftCommand(script: fixture.primaryScript)
        }
        runtime.resourceBenchmark("Resource/RSS/shell") { fixture in
            fixture.shellCommand
        }
    }
}

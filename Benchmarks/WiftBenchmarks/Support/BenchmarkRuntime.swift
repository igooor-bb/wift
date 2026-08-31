import Benchmark
import Foundation

struct BenchmarkRuntime: Sendable {
    let runner = ProcessRunner()

    func frequentCommandBenchmark(
        _ name: String,
        prepare: @escaping (BenchmarkFixture) throws -> Void = { _ in },
        command: @escaping (BenchmarkFixture) throws -> BenchmarkCommand,
        validate: @escaping (BenchmarkFixture) throws -> Void = { _ in }
    ) {
        let holder = FixtureHolder()
        Benchmark(
            name,
            configuration: BenchmarkConfigurations.frequent,
            closure: { benchmark in
                let fixture = try holder.requireFixture()
                let measuredCommand = try command(fixture)
                benchmark.startMeasurement()
                try runner.run(measuredCommand)
                benchmark.stopMeasurement()
                try validate(fixture)
            },
            setup: {
                let fixture = try BenchmarkFixture()
                do {
                    try prepare(fixture)
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

    func resourceBenchmark(
        _ name: String,
        prepare: @escaping (BenchmarkFixture) throws -> BenchmarkCommand
    ) {
        Benchmark(name, configuration: BenchmarkConfigurations.resource) { benchmark in
            try withFixture { fixture in
                let command = try prepare(fixture)
                let measurement = try runner.run(command, measurePeakRSS: true)
                benchmark.measurement(BenchmarkMetrics.peakRSS, Int(measurement.peakResidentBytes))
            }
        }
    }

    func footprintBenchmark(
        _ name: String,
        operation: @escaping (BenchmarkFixture) throws -> CacheFootprint
    ) {
        Benchmark(name, configuration: BenchmarkConfigurations.footprint) { benchmark in
            try withFixture { fixture in
                try record(operation(fixture), in: benchmark)
            }
        }
    }

    func withFixture(_ body: (BenchmarkFixture) throws -> Void) throws {
        let fixture = try BenchmarkFixture()
        defer { fixture.remove() }
        try body(fixture)
    }

    func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else {
            throw FixtureError(message)
        }
    }

    private func record(_ footprint: CacheFootprint, in benchmark: Benchmark) {
        benchmark.measurement(BenchmarkMetrics.totalLogical, footprint.total.logical)
        benchmark.measurement(BenchmarkMetrics.totalAllocated, footprint.total.allocated)
        benchmark.measurement(BenchmarkMetrics.executableLogical, footprint.executable.logical)
        benchmark.measurement(BenchmarkMetrics.supportLogical, footprint.support.logical)
        benchmark.measurement(BenchmarkMetrics.moduleLogical, footprint.module.logical)
        benchmark.measurement(BenchmarkMetrics.metadataLogical, footprint.metadata.logical)
        benchmark.measurement(BenchmarkMetrics.executableCount, footprint.executableCount)
        benchmark.measurement(BenchmarkMetrics.supportContextCount, footprint.supportContextCount)
        benchmark.measurement(BenchmarkMetrics.moduleContextCount, footprint.moduleContextCount)
        benchmark.measurement(BenchmarkMetrics.pathAssociationCount, footprint.pathAssociationCount)
    }
}

enum BenchmarkConfigurations {
    static var frequent: Benchmark.Configuration {
        Benchmark.Configuration(
            metrics: [.wallClock],
            timeUnits: .microseconds,
            warmupIterations: 3,
            maxDuration: .seconds(3),
            maxIterations: 1000
        )
    }

    static var cold: Benchmark.Configuration {
        Benchmark.Configuration(
            metrics: [.wallClock],
            timeUnits: .milliseconds,
            warmupIterations: 0,
            maxDuration: .seconds(300),
            maxIterations: 5
        )
    }

    static var resource: Benchmark.Configuration {
        Benchmark.Configuration(
            metrics: [BenchmarkMetrics.peakRSS],
            warmupIterations: 0,
            maxDuration: .seconds(60),
            maxIterations: 10
        )
    }

    static var footprint: Benchmark.Configuration {
        Benchmark.Configuration(
            metrics: BenchmarkMetrics.footprint,
            warmupIterations: 0,
            maxDuration: .seconds(300),
            maxIterations: 5
        )
    }
}

enum BenchmarkMetrics {
    static let peakRSS = BenchmarkMetric.custom("Process tree peak RSS (bytes)", useScalingFactor: false)
    static let totalLogical = BenchmarkMetric.custom("Cache logical size (bytes)", useScalingFactor: false)
    static let totalAllocated = BenchmarkMetric.custom("Cache allocated size (bytes)", useScalingFactor: false)
    static let executableLogical = BenchmarkMetric.custom("Executable cache size (bytes)", useScalingFactor: false)
    static let supportLogical = BenchmarkMetric.custom("Support cache size (bytes)", useScalingFactor: false)
    static let moduleLogical = BenchmarkMetric.custom("Module cache size (bytes)", useScalingFactor: false)
    static let metadataLogical = BenchmarkMetric.custom("Metadata size (bytes)", useScalingFactor: false)
    static let executableCount = BenchmarkMetric.custom("Executable count", useScalingFactor: false)
    static let supportContextCount = BenchmarkMetric.custom("Support context count", useScalingFactor: false)
    static let moduleContextCount = BenchmarkMetric.custom("Module context count", useScalingFactor: false)
    static let pathAssociationCount = BenchmarkMetric.custom("Path association count", useScalingFactor: false)

    static let footprint = [
        totalLogical,
        totalAllocated,
        executableLogical,
        supportLogical,
        moduleLogical,
        metadataLogical,
        executableCount,
        supportContextCount,
        moduleContextCount,
        pathAssociationCount,
    ]
}

final class FixtureHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var fixture: BenchmarkFixture?

    func store(_ fixture: BenchmarkFixture) {
        lock.withLock {
            self.fixture = fixture
        }
    }

    func requireFixture() throws -> BenchmarkFixture {
        try lock.withLock {
            guard let fixture else {
                throw FixtureError("benchmark fixture is not prepared")
            }
            return fixture
        }
    }

    func removeFixture() {
        let fixture = lock.withLock {
            defer { self.fixture = nil }
            return self.fixture
        }
        fixture?.remove()
    }
}

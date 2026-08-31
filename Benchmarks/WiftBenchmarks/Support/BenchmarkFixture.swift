import Foundation

struct BenchmarkFixture {
    let root: URL
    let cache: URL
    let swiftModuleCache: URL
    let primaryScript: URL
    let secondaryScript: URL
    let shellScript: URL

    private let fileManager = FileManager.default

    init(primarySource: String = FixtureSource.minimal) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wift-benchmark-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(root.path, 0o700) == 0 else {
            throw FixtureError("unable to create temporary directory: \(String(cString: strerror(errno)))")
        }
        self.root = root
        cache = root.appendingPathComponent("wift-cache", isDirectory: true)
        swiftModuleCache = root.appendingPathComponent("swift-module-cache", isDirectory: true)
        primaryScript = root.appendingPathComponent("primary.swift")
        secondaryScript = root.appendingPathComponent("secondary.swift")
        shellScript = root.appendingPathComponent("startup.sh")
        do {
            try write(primarySource, to: primaryScript)
            try write(primarySource, to: secondaryScript)
            try write(":\n", to: shellScript)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    func remove() {
        guard root.lastPathComponent.hasPrefix("wift-benchmark-") else {
            return
        }
        try? fileManager.removeItem(at: root)
    }

    func write(_ source: String, to url: URL) throws {
        try Data(source.utf8).write(to: url, options: .atomic)
    }

    func wiftCommand(script: URL) -> BenchmarkCommand {
        var environment = ProcessInfo.processInfo.environment
        environment["WIFT_CACHE_DIR"] = cache.path
        return BenchmarkCommand(
            executable: BenchmarkEnvironment.wiftBinary,
            arguments: [script.path],
            environment: environment
        )
    }

    func swiftCommand(script: URL) -> BenchmarkCommand {
        BenchmarkCommand(
            executable: "/usr/bin/swift",
            arguments: ["-module-cache-path", swiftModuleCache.path, script.path]
        )
    }

    var shellCommand: BenchmarkCommand {
        BenchmarkCommand(executable: "/bin/sh", arguments: [shellScript.path])
    }

    func cachedExecutable() throws -> URL {
        let executableRoot = cache.appendingPathComponent("executables", isDirectory: true)
        let executables = try regularFiles(below: executableRoot)
            .filter { $0.lastPathComponent == "executable" }
        guard executables.count == 1, let executable = executables.first else {
            throw FixtureError("expected one cached executable, found \(executables.count)")
        }
        return executable
    }

    func executableCount() throws -> Int {
        let executableRoot = cache.appendingPathComponent("executables", isDirectory: true)
        return try regularFiles(below: executableRoot)
            .count { $0.lastPathComponent == "executable" }
    }

    func pathAssociationCount() throws -> Int {
        let executableRoot = cache.appendingPathComponent("executables", isDirectory: true)
        return try regularFiles(below: executableRoot)
            .count { $0.path.contains("/paths/") && $0.pathExtension == "json" }
    }

    private func regularFiles(below directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw FixtureError("unable to enumerate \(directory.path)")
        }
        return try enumerator.compactMap { item in
            guard let url = item as? URL else {
                return nil
            }
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true ? url : nil
        }
    }
}

enum FixtureSource {
    static let minimal = """
    let argumentCount = CommandLine.arguments.count
    if argumentCount == .min {
        print(argumentCount)
    }
    """

    static let alternate = """
    let values = (0..<256).map { $0 &* 2 }
    let sum = values.reduce(0, &+)
    if sum == .min {
        print(sum)
    }
    """
}

enum BenchmarkEnvironment {
    static let wiftBinary: String = {
        guard let path = ProcessInfo.processInfo.environment["WIFT_BENCHMARK_BINARY"], !path.isEmpty else {
            fatalError("WIFT_BENCHMARK_BINARY must point to a release wift executable")
        }
        return path
    }()
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

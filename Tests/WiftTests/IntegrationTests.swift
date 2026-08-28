import Foundation
import Testing
@testable import Wift

@Suite(.serialized) struct IntegrationTests {
    @Test func firstAndSecondRunUseTheSameCachedExecutable() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(\"hello\")")

            let first = try fixture.run(script)
            #expect(first.exitCode == 0)
            #expect(first.standardOutput == "hello\n")
            let executable = try #require(fixture.cachedExecutables().only)
            #expect(try fixture.cachedMetadata().count == 1)
            let oldDate = Date(timeIntervalSinceReferenceDate: 1)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: executable.path)

            let second = try fixture.run(script)
            #expect(second.exitCode == 0)
            #expect(second.standardOutput == "hello\n")
            let attributes = try FileManager.default.attributesOfItem(atPath: executable.path)
            #expect(attributes[.modificationDate] as? Date == oldDate)
        }
    }

    @Test func sourceModificationCreatesANewEntry() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(\"hello\")")
            #expect(try fixture.run(script).standardOutput == "hello\n")

            try Data("print(\"world\")".utf8).write(to: script)
            #expect(try fixture.run(script).standardOutput == "world\n")
            #expect(try fixture.cachedExecutables().count == 2)
        }
    }

    @Test func verboseSeparatesDiagnosticsFromScriptOutput() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(\"hello\")")

            let miss = try fixture.run(script, wiftArguments: ["--verbose"])
            #expect(miss.standardOutput == "hello\n")
            #expect(miss.standardError.contains("wift: cache miss\n"))
            #expect(miss.standardError.contains("wift: compiling\n"))
            #expect(miss.standardError.contains("wift: exec\n"))

            let hit = try fixture.run(script, wiftArguments: ["--verbose"])
            #expect(hit.standardOutput == "hello\n")
            #expect(hit.standardError.contains("wift: cache hit\n"))
            #expect(!hit.standardError.contains("wift: compiling\n"))

            let silent = try fixture.run(script)
            #expect(silent.standardOutput == "hello\n")
            #expect(silent.standardError.isEmpty)
        }
    }

    @Test func preservesArgumentsEnvironmentAndWorkingDirectory() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript(
                """
                import Foundation
                print(CommandLine.arguments[0])
                print(CommandLine.arguments.dropFirst().joined(separator: ","))
                print(ProcessInfo.processInfo.environment["WIFT_FIXTURE"] ?? "missing")
                print(FileManager.default.fileExists(atPath: "cwd-marker"))
                """
            )
            let workingDirectory = directory.appendingPathComponent("working", isDirectory: true)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            try Data().write(to: workingDirectory.appendingPathComponent("cwd-marker"))

            let result = try fixture.run(
                script,
                arguments: ["one", "--two", "three"],
                environment: ["WIFT_FIXTURE": "visible"],
                currentDirectory: workingDirectory
            )

            #expect(result.exitCode == 0)
            let canonicalScriptPath = try Script.resolve(script.path).path
            #expect(result.standardOutput == "\(canonicalScriptPath)\none,--two,three\nvisible\ntrue\n")
        }
    }

    @Test func reportsMissingScript() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let missing = directory.appendingPathComponent("missing.swift")
            let result = try fixture.run(missing)

            #expect(result.exitCode == 1)
            #expect(result.standardError == "wift: script not found: \(missing.path)\n")
        }
    }

    @Test func preservesExitCode() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("import Darwin\nexit(23)")

            #expect(try fixture.run(script).exitCode == 23)
        }
    }

    @Test func supportsShebangExecution() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("#!/usr/bin/env wift\nprint(\"shebang\")", executable: true)
            let result = try fixture.runDirectly(script)

            #expect(result.exitCode == 0)
            #expect(result.standardOutput == "shebang\n")
        }
    }

    @Test func compileFailureDoesNotCreateACacheEntry() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("this is not valid Swift")
            let result = try fixture.run(script)

            #expect(result.exitCode != 0)
            #expect(result.standardError.contains("error:"))
            #expect(try fixture.cachedExecutables().isEmpty)
        }
    }

    @Test func concurrentInvocationCompilesOnlyOnce() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory, instrumentCompiler: true)
            let script = try fixture.writeScript("print(\"concurrent\")")
            let results = try fixture.runConcurrently(script, count: 4)

            for result in results {
                #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
                #expect(result.standardOutput == "concurrent\n")
            }
            #expect(try fixture.compilationCount() == 1)
            #expect(try fixture.cachedExecutables().count == 1)
        }
    }
}

private struct Fixture {
    let directory: URL
    let cacheDirectory: URL
    let wiftExecutable: URL
    let environment: [String: String]
    let compilerCountURL: URL?

    init(directory: URL, instrumentCompiler: Bool = false) throws {
        self.directory = directory
        cacheDirectory = directory.appendingPathComponent("cache", isDirectory: true)
        wiftExecutable = try Self.findWiftExecutable()
        var environment = ProcessInfo.processInfo.environment
        environment["WIFT_CACHE_DIR"] = cacheDirectory.path

        if instrumentCompiler {
            let compilerDirectory = directory.appendingPathComponent("compiler", isDirectory: true)
            try FileManager.default.createDirectory(at: compilerDirectory, withIntermediateDirectories: true)
            let countURL = compilerDirectory.appendingPathComponent("count")
            let wrapperURL = compilerDirectory.appendingPathComponent("swiftc")
            let wrapper = """
            #!/bin/sh
            case "$1" in
              --version|-print-target-info) exec "$WIFT_REAL_SWIFTC" "$@" ;;
              *) printf 'compile\\n' >> "$WIFT_COMPILER_COUNT"; exec "$WIFT_REAL_SWIFTC" "$@" ;;
            esac
            """
            try Data(wrapper.utf8).write(to: wrapperURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
            let realSwiftCompiler = try #require(ExecutableLookup.find("swiftc", environment: environment))
            environment["PATH"] = "\(compilerDirectory.path):\(environment["PATH", default: ""])"
            environment["WIFT_REAL_SWIFTC"] = realSwiftCompiler
            environment["WIFT_COMPILER_COUNT"] = countURL.path
            compilerCountURL = countURL
        } else {
            compilerCountURL = nil
        }

        self.environment = environment
    }

    func writeScript(_ source: String, executable: Bool = false) throws -> URL {
        let script = directory.appendingPathComponent("script.swift")
        try Data(source.utf8).write(to: script)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        return script
    }

    func run(
        _ script: URL,
        arguments: [String] = [],
        wiftArguments: [String] = [],
        environment additions: [String: String] = [:],
        currentDirectory: URL? = nil
    ) throws -> CommandResult {
        var environment = environment
        environment.merge(additions) { _, new in new }
        return try Self.runProcess(
            executable: wiftExecutable,
            arguments: wiftArguments + [script.path] + arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }

    func runDirectly(_ script: URL) throws -> CommandResult {
        var environment = environment
        environment["PATH"] = "\(wiftExecutable.deletingLastPathComponent().path):\(environment["PATH", default: ""])"
        return try Self.runProcess(executable: script, arguments: [], environment: environment)
    }

    func runConcurrently(_ script: URL, count: Int) throws -> [CommandResult] {
        let executions = try (0 ..< count).map { _ in
            try RunningProcess(
                executable: wiftExecutable,
                arguments: [script.path],
                environment: environment
            )
        }
        return executions.map { $0.wait() }
    }

    func cachedExecutables() throws -> [URL] {
        try cachedFiles(named: "executable")
    }

    func cachedMetadata() throws -> [URL] {
        try cachedFiles(named: "metadata.json")
    }

    private func cachedFiles(named name: String) throws -> [URL] {
        let root = cacheDirectory.appendingPathComponent("executables", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.lastPathComponent == name else {
                return nil
            }
            return url
        }
    }

    func compilationCount() throws -> Int {
        let countURL = try #require(compilerCountURL)
        let data = try Data(contentsOf: countURL)
        return data.split(separator: Character("\n").asciiValue!).count
    }

    private static func findWiftExecutable() throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = packageRoot.appendingPathComponent(".build/debug/wift")
        return try #require(
            FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil,
            "wift executable was not built at \(executable.path)"
        )
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil
    ) throws -> CommandResult {
        let running = try RunningProcess(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
        return running.wait()
    }
}

private final class RunningProcess {
    private let process = Process()
    private let standardOutput = Pipe()
    private let standardError = Pipe()

    init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil
    ) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
    }

    func wait() -> CommandResult {
        process.waitUntilExit()
        return CommandResult(
            standardOutput: String(
                data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            standardError: String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

private struct CommandResult {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

import Darwin
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

    @Test func verboseReportsRealLockContention() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory, instrumentCompiler: true, gateCompiler: true)
            let script = try fixture.writeScript("print(\"contended\")")
            let builder = try fixture.start(script)
            try fixture.waitForCompilerStart()

            let waiter = try fixture.start(script, wiftArguments: ["--verbose"])
            let diagnostics = waiter.readStandardError(until: "wift: waiting for cache lock\n")
            #expect(diagnostics.contains("wift: waiting for cache lock\n"))

            try fixture.releaseCompiler()
            let builderResult = builder.wait()
            let waiterResult = waiter.wait()
            #expect(builderResult.exitCode == 0)
            #expect(waiterResult.exitCode == 0)
            #expect(waiterResult.standardError.contains("wift: cache populated by another process\n"))
            #expect(waiterResult.standardOutput == "contended\n")
        }
    }

    @Test func reportsHelpAndVersion() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)

            let help = try fixture.runWift(["--help"])
            #expect(help.exitCode == 0)
            #expect(help.standardOutput.contains("USAGE: wift [options] <script.swift> [arguments...]"))
            #expect(help.standardOutput.contains("wift cache info <script.swift>"))

            let version = try fixture.runWift(["--version"])
            #expect(version.exitCode == 0)
            #expect(version.standardOutput == "wift 0.1.0\n")
        }
    }

    @Test func inspectsCacheWithoutCompiling() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(\"hello\")")

            let path = try fixture.runWift(["cache", "path"])
            #expect(path.exitCode == 0)
            #expect(path.standardOutput == "\(fixture.cacheDirectory.path)\n")
            #expect(!FileManager.default.fileExists(atPath: fixture.cacheDirectory.path))

            let miss = try fixture.runWift(["cache", "info", script.path])
            #expect(miss.exitCode == 0)
            #expect(miss.standardOutput.contains("Cache status: miss\n"))
            #expect(try fixture.cachedExecutables().isEmpty)

            _ = try fixture.run(script)
            let hit = try fixture.runWift(["cache", "info", script.path])
            #expect(hit.exitCode == 0)
            #expect(hit.standardOutput.contains("Cache status: hit\n"))
            #expect(hit.standardOutput.contains("Cache key: "))
            #expect(hit.standardOutput.contains("Created: "))
        }
    }

    @Test func summarizesValidCacheEntries() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(1)")
            _ = try fixture.run(script)
            try Data("print(2)".utf8).write(to: script)
            _ = try fixture.run(script)

            let summary = try fixture.runWift(["cache"])
            #expect(summary.exitCode == 0)
            #expect(summary.standardOutput.contains("Executables: 2\n"))
            #expect(summary.standardOutput.contains("Module cache: "))
            #expect(summary.standardOutput.contains("Support cache: "))
            #expect(summary.standardOutput.contains("Total: "))
        }
    }

    @Test func cleansCurrentEntryAndRecompiles() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory, instrumentCompiler: true)
            let script = try fixture.writeScript("print(\"clean\")")
            _ = try fixture.run(script)
            #expect(try fixture.compilationCount() == 1)

            let clean = try fixture.runWift(["cache", "clean", script.path])
            #expect(clean.exitCode == 0)
            #expect(clean.standardOutput.contains("Removed 1 cache variant(s) for "))
            #expect(try fixture.cachedExecutables().isEmpty)

            _ = try fixture.run(script)
            #expect(try fixture.compilationCount() == 2)
        }
    }

    @Test func cleansEntireCache() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(\"clean all\")")
            _ = try fixture.run(script)
            let abandoned = fixture.cacheDirectory.appendingPathComponent("staging/abandoned/file")
            try FileManager.default.createDirectory(
                at: abandoned.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("temporary".utf8).write(to: abandoned)

            let clean = try fixture.runWift(["cache", "clean"])
            #expect(clean.exitCode == 0)
            #expect(!FileManager.default.fileExists(atPath: fixture.cacheDirectory.path))

            let summary = try fixture.runWift(["cache"])
            #expect(summary.standardOutput.contains("Executables: 0\n"))
            #expect(summary.standardOutput.contains("Total: 0 B\n"))
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

    @Test func supportsExtensionlessShebangExecution() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript(
                "#!/usr/bin/env wift\nimport Wift\nprint(Script.path.path)",
                name: "add",
                executable: true
            )
            let result = try fixture.runDirectly(script)

            #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
            #expect(try result.standardOutput == "\(Script.resolve(script.path).path)\n")
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
            #expect(try fixture.supportCompilationCount() == 1)
            #expect(try fixture.cachedExecutables().count == 1)
        }
    }

    @Test func importsWiftAndUsesProcessHelpers() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript(
                """
                import Foundation
                import Wift

                print(try run("/bin/sh", "-c", "exit 0"))
                print(try run("/bin/sh", arguments: ["-c", "exit 0"]))
                print(try run("/bin/sh", "-c", "exit 9"))
                do {
                    try checkRun("/bin/sh", "-c", "exit 7")
                } catch let error as CommandFailure {
                    print("failure=\\(error.executable),\\(error.arguments.joined(separator: ",")),\\(error.status)")
                }
                let output = try capture("/bin/sh", "-c", "printf 'out\\n\\n'; printf 'err\\n' >&2")
                print("capture=\\(output.status):\\(output.stdout.debugDescription):\\(output.stderr.debugDescription)")
                print("which=\\(which("sh") != nil),\\(which("definitely-not-a-wift-command") == nil),\\(which("/bin/sh") != nil)")
                print("path=\\(Script.path.path)")
                print("directory=\\(Script.directory.path)")
                """
            )

            let result = try fixture.run(script)
            let canonicalPath = try Script.resolve(script.path).path
            #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
            #expect(result.standardOutput.contains("0\n0\n9\n"))
            #expect(result.standardOutput.contains("failure=/bin/sh,-c,exit 7,7\n"))
            #expect(result.standardOutput.contains("capture=0:\"out\\n\\n\":\"err\\n\"\n"))
            #expect(result.standardOutput.contains("which=true,true,true\n"))
            #expect(result.standardOutput.contains("path=\(canonicalPath)\n"))
            #expect(result.standardOutput.contains("directory=\(directory.path)\n"))
        }
    }

    @Test func capturesLargeStdoutAndStderrWithoutDeadlock() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript(
                """
                import Wift
                let output = try capture(
                    "/bin/sh",
                    "-c",
                    "yes o | head -c 200000 & yes e | head -c 200000 >&2 & wait"
                )
                print("\\(output.status),\\(output.stdout.utf8.count),\\(output.stderr.utf8.count)")
                """
            )

            let result = try fixture.run(script)
            #expect(result.exitCode == 0, Comment(rawValue: result.standardError))
            #expect(result.standardOutput == "0,200000,200000\n")
        }
    }

    @Test func eprintAndDieWriteToStandardError() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript(
                """
                import Wift
                eprint("before")
                die("fatal", status: 7)
                """
            )

            let result = try fixture.run(script)
            #expect(result.exitCode == 7)
            #expect(result.standardError == "before\nfatal\n")
        }
    }

    @Test func reusesSupportCacheAcrossScriptVariants() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory, instrumentCompiler: true)
            let script = try fixture.writeScript("import Wift\nprint(which(\"sh\") != nil)")
            let first = try fixture.run(script, wiftArguments: ["--verbose"])
            try Data("import Wift\nprint(which(\"swiftc\") != nil)".utf8).write(to: script)
            let second = try fixture.run(script, wiftArguments: ["--verbose"])

            #expect(first.standardError.contains("wift: support cache miss\n"))
            #expect(second.standardError.contains("wift: support cache hit\n"))
            #expect(second.standardError.contains("wift: support module: "))
            #expect(try fixture.supportCompilationCount() == 1)
            #expect(try fixture.compilationCount() == 2)
            #expect(try fixture.compilerModuleContextDirectories().count == 1)
        }
    }

    @Test func cachedExecutableDoesNotRequireSupportArtifacts() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory, instrumentCompiler: true)
            let script = try fixture.writeScript("import Wift\nprint(\"standalone\")")
            #expect(try fixture.run(script).standardOutput == "standalone\n")
            try FileManager.default.removeItem(
                at: fixture.cacheDirectory.appendingPathComponent("support", isDirectory: true)
            )

            let cached = try fixture.run(script)
            #expect(cached.exitCode == 0, Comment(rawValue: cached.standardError))
            #expect(cached.standardOutput == "standalone\n")
            #expect(try fixture.compilationCount() == 1)
            #expect(try fixture.supportCompilationCount() == 1)
        }
    }

    @Test func cacheInfoAndCleanCoverEveryScriptVariant() throws {
        try withTemporaryDirectory { directory in
            let fixture = try Fixture(directory: directory)
            let script = try fixture.writeScript("print(1)")
            _ = try fixture.run(script)
            try Data("print(2)".utf8).write(to: script)
            _ = try fixture.run(script)

            let info = try fixture.runWift(["cache", "info", script.path])
            #expect(info.standardOutput.contains("Variants: 2\n"))
            #expect(info.standardOutput.contains(" ACTIVE\n"))
            #expect(info.standardOutput.contains("Source current: no\n"))
            #expect(info.standardOutput.contains("Support fingerprint: "))

            let clean = try fixture.runWift(["cache", "clean", script.path])
            #expect(clean.standardOutput.contains("Removed 2 cache variant(s)"))
            #expect(try fixture.cachedExecutables().isEmpty)
            #expect(try fixture.cachedSupportModules().count == 1)
        }
    }
}

private struct Fixture {
    let directory: URL
    let cacheDirectory: URL
    let wiftExecutable: URL
    let environment: [String: String]
    let compilerCountURL: URL?
    let supportCompilerCountURL: URL?
    let compilerStartedFIFO: URL?
    let compilerReleaseFIFO: URL?

    init(
        directory: URL,
        instrumentCompiler: Bool = false,
        gateCompiler: Bool = false
    ) throws {
        self.directory = directory
        cacheDirectory = directory.appendingPathComponent("cache", isDirectory: true)
        wiftExecutable = try Self.findWiftExecutable()
        var environment = ProcessInfo.processInfo.environment
        environment["WIFT_CACHE_DIR"] = cacheDirectory.path

        if instrumentCompiler || gateCompiler {
            let compilerDirectory = directory.appendingPathComponent("compiler", isDirectory: true)
            try FileManager.default.createDirectory(at: compilerDirectory, withIntermediateDirectories: true)
            let countURL = compilerDirectory.appendingPathComponent("count")
            let supportCountURL = compilerDirectory.appendingPathComponent("support-count")
            let wrapperURL = compilerDirectory.appendingPathComponent("swiftc")
            let wrapper = """
            #!/bin/sh
            case "$1" in
              --version|-print-target-info) exec "$WIFT_REAL_SWIFTC" "$@" ;;
              *)
                is_support=false
                previous=''
                for argument in "$@"; do
                  if [ "$previous" = '-module-name' ] && [ "$argument" = 'Wift' ]; then
                    is_support=true
                  fi
                  previous="$argument"
                done
                if [ "$is_support" = true ]; then
                  printf 'compile\\n' >> "$WIFT_SUPPORT_COMPILER_COUNT"
                else
                  printf 'compile\\n' >> "$WIFT_COMPILER_COUNT"
                  if [ -n "${WIFT_COMPILER_STARTED_FIFO:-}" ]; then
                    printf 'started\\n' > "$WIFT_COMPILER_STARTED_FIFO"
                    read -r _ < "$WIFT_COMPILER_RELEASE_FIFO"
                  fi
                fi
                exec "$WIFT_REAL_SWIFTC" "$@"
                ;;
            esac
            """
            try Data(wrapper.utf8).write(to: wrapperURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
            let realSwiftCompiler = try #require(ExecutableLookup.find("swiftc", environment: environment))
            environment["PATH"] = "\(compilerDirectory.path):\(environment["PATH", default: ""])"
            environment["WIFT_REAL_SWIFTC"] = realSwiftCompiler
            environment["WIFT_COMPILER_COUNT"] = countURL.path
            environment["WIFT_SUPPORT_COMPILER_COUNT"] = supportCountURL.path
            compilerCountURL = countURL
            supportCompilerCountURL = supportCountURL
            if gateCompiler {
                let startedFIFO = compilerDirectory.appendingPathComponent("started.fifo")
                let releaseFIFO = compilerDirectory.appendingPathComponent("release.fifo")
                try Self.createFIFO(at: startedFIFO)
                try Self.createFIFO(at: releaseFIFO)
                environment["WIFT_COMPILER_STARTED_FIFO"] = startedFIFO.path
                environment["WIFT_COMPILER_RELEASE_FIFO"] = releaseFIFO.path
                compilerStartedFIFO = startedFIFO
                compilerReleaseFIFO = releaseFIFO
            } else {
                compilerStartedFIFO = nil
                compilerReleaseFIFO = nil
            }
        } else {
            compilerCountURL = nil
            supportCompilerCountURL = nil
            compilerStartedFIFO = nil
            compilerReleaseFIFO = nil
        }

        self.environment = environment
    }

    func writeScript(
        _ source: String,
        name: String = "script.swift",
        executable: Bool = false
    ) throws -> URL {
        let script = directory.appendingPathComponent(name)
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

    func runWift(_ arguments: [String]) throws -> CommandResult {
        try Self.runProcess(
            executable: wiftExecutable,
            arguments: arguments,
            environment: environment
        )
    }

    func start(
        _ script: URL,
        wiftArguments: [String] = []
    ) throws -> RunningProcess {
        try RunningProcess(
            executable: wiftExecutable,
            arguments: wiftArguments + [script.path],
            environment: environment
        )
    }

    func waitForCompilerStart() throws {
        let fifo = try #require(compilerStartedFIFO)
        let handle = try FileHandle(forReadingFrom: fifo)
        defer { try? handle.close() }
        let signal = handle.readDataToEndOfFile()
        guard signal == Data("started\n".utf8) else {
            throw WiftError("compiler gate did not start")
        }
    }

    func releaseCompiler() throws {
        let fifo = try #require(compilerReleaseFIFO)
        let handle = try FileHandle(forWritingTo: fifo)
        defer { try? handle.close() }
        handle.write(Data("continue\n".utf8))
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

    func cachedSupportModules() throws -> [URL] {
        let root = cacheDirectory.appendingPathComponent("support", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
    }

    func compilerModuleContextDirectories() throws -> [URL] {
        let root = cacheDirectory.appendingPathComponent("module-cache", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        return try contents.filter { url in
            try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
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

    func supportCompilationCount() throws -> Int {
        let countURL = try #require(supportCompilerCountURL)
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

    private static func createFIFO(at url: URL) throws {
        let result = url.path.withCString { path in
            mkfifo(path, S_IRUSR | S_IWUSR)
        }
        guard result == 0 else {
            throw WiftError("unable to create compiler gate: \(String(cString: strerror(errno)))")
        }
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
    private var standardErrorPrefix = Data()

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
        let remainingStandardError = standardError.fileHandleForReading.readDataToEndOfFile()
        standardErrorPrefix.append(remainingStandardError)
        return CommandResult(
            standardOutput: String(
                data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            standardError: String(
                data: standardErrorPrefix,
                encoding: .utf8
            ) ?? "",
            exitCode: process.terminationStatus
        )
    }

    func readStandardError(until expected: String) -> String {
        while !standardErrorText.contains(expected) {
            let data = standardError.fileHandleForReading.availableData
            guard !data.isEmpty else {
                break
            }
            standardErrorPrefix.append(data)
        }
        return standardErrorText
    }

    private var standardErrorText: String {
        String(data: standardErrorPrefix, encoding: .utf8) ?? ""
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

import Foundation
import Testing
@testable import Wift

@Suite(.serialized) struct EditorIntegrationTests {
    @Test func customEditorReplacesProcessAndReceivesOriginalPath() throws {
        try withTemporaryDirectory { directory in
            let fixture = try EditorFixture(directory: directory)
            var environment = fixture.environment
            environment["PATH"] = ""
            environment["WIFT_EDITOR"] = fixture.editor.path
            let running = try fixture.start(["edit", fixture.script.path], environment: environment)
            let result = try running.finish()
            #expect(result.exitCode == 0)
            let editorPID = try String(contentsOf: directory.appendingPathComponent("editor-pid"), encoding: .utf8)
            #expect(editorPID == String(running.process.processIdentifier))
            #expect(try fixture.editorArguments() == [fixture.script.resolvingSymlinksInPath().path])
            #expect(!FileManager.default.fileExists(atPath: fixture.storage.path))
            environment["EDITOR_STATUS"] = "7"
            #expect(try fixture.run(["edit", fixture.script.path], environment: environment).exitCode == 7)
        }
    }

    @Test func missingSwiftExtensionWarnsButStillOpensOriginalFile() throws {
        try withTemporaryDirectory { directory in
            let fixture = try EditorFixture(directory: directory)
            let result = try fixture.run(["edit", "--editor", "vscode", fixture.script.path])
            #expect(result.exitCode == 0)
            #expect((String(data: result.standardError, encoding: .utf8) ?? "").contains("code --install-extension swiftlang.swift-vscode"))
            let arguments = try fixture.editorArguments()
            #expect(arguments.first == "--new-window")
            #expect(arguments.last == fixture.script.resolvingSymlinksInPath().path)
            let workspace = try URL(fileURLWithPath: #require(arguments.dropFirst().first))
            let database = try Data(contentsOf: workspace.deletingLastPathComponent().appendingPathComponent("compile_commands.json"))
            #expect((String(data: database, encoding: .utf8) ?? "").contains(fixture.script.lastPathComponent))
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("runtime").path))
            #expect(try String(contentsOf: fixture.script, encoding: .utf8) == EditorFixture.source)

            var environment = fixture.environment
            environment["EDITOR_EXTENSIONS"] = "swiftlang.swift-vscode"
            try Data("import Wift\ntry cmd(\"true\").run()\n".utf8).write(to: fixture.script, options: .atomic)
            let repeated = try fixture.run(["edit", "--editor", "vscode", fixture.script.path], environment: environment)
            #expect(repeated.exitCode == 0)
            #expect(repeated.standardError.isEmpty)
            #expect(try fixture.editorArguments() == arguments)
        }
    }

    @Test func concurrentEditPublishesOneCompleteWorkspace() throws {
        try withTemporaryDirectory { directory in
            let fixture = try EditorFixture(directory: directory)
            let arguments = ["edit", "--editor", "vscode", fixture.script.path]
            let first = try fixture.start(arguments, environment: fixture.environment)
            let second = try fixture.start(arguments, environment: fixture.environment)
            #expect(try first.finish().exitCode == 0)
            #expect(try second.finish().exitCode == 0)
            let environments = fixture.storage.appendingPathComponent("environments")
            let identities = try FileManager.default.contentsOfDirectory(at: environments, includingPropertiesForKeys: nil)
            #expect(identities.count == 1)
            let revisions = try FileManager.default.contentsOfDirectory(at: #require(identities.first), includingPropertiesForKeys: nil)
            #expect(revisions.count == 1)
            let revision = try #require(revisions.first)
            #expect(FileManager.default.fileExists(atPath: revision.appendingPathComponent("compile_commands.json").path))
            #expect(FileManager.default.fileExists(atPath: revision.appendingPathComponent("script.code-workspace").path))
        }
    }

    @Test func scriptNamedWiftCanImportSupportModule() throws {
        try withTemporaryDirectory { directory in
            let fixture = try EditorFixture(directory: directory)
            let script = directory.appendingPathComponent("Wift.swift")
            let example = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Examples/Wift.swift")
            try Data(contentsOf: example).write(to: script)
            let result = try fixture.run(["edit", "--editor", "vscode", script.path])
            #expect(result.exitCode == 0)
            let workspace = try URL(fileURLWithPath: #require(fixture.editorArguments().dropFirst().first))
            let database = try Data(contentsOf: workspace.deletingLastPathComponent().appendingPathComponent("compile_commands.json"))
            let commands = try #require(JSONSerialization.jsonObject(with: database) as? [[String: Any]])
            let arguments = try #require(commands.first?["arguments"] as? [String])
            let compiler = try #require(arguments.first)
            let checked = try ProcessExecution.capture(executable: compiler, arguments: Array(arguments.dropFirst()) + ["-typecheck"])
            #expect(checked.exitCode == 0)
            #expect(checked.standardError.isEmpty)
        }
    }

    @Test func editHelpAndErrorsUseEditUsage() throws {
        try withTemporaryDirectory { directory in
            let fixture = try EditorFixture(directory: directory)
            let help = try fixture.run(["edit", "--help"])
            #expect(help.exitCode == 0)
            #expect((String(data: help.standardOutput, encoding: .utf8) ?? "").contains("wift edit"))
            let invalid = try fixture.run(["edit", "--unknown"])
            #expect(invalid.exitCode != 0)
            #expect((String(data: invalid.standardError, encoding: .utf8) ?? "").contains("wift edit"))
        }
    }
}

private struct EditorFixture {
    static let source = "#!/usr/bin/env wift\nimport Wift\nlet invalid: Int = \"unfinished\"\n"
    let directory: URL
    let script: URL
    let editor: URL
    let storage: URL
    let environment: [String: String]

    init(directory: URL) throws {
        self.directory = directory
        script = directory.appendingPathComponent("space ' quote; юникод.swift")
        editor = directory.appendingPathComponent("code")
        storage = directory.appendingPathComponent("editor")
        try Data(Self.source.utf8).write(to: script)
        let stub = """
        #!/bin/sh
        if [ "$1" = '--list-extensions' ]; then
            printf '%s\\n' "$EDITOR_EXTENSIONS"
            exit 0
        fi
        printf '%s\\0' "$@" > "$EDITOR_ARGUMENTS"
        printf '%s' "$$" > "$EDITOR_PID"
        exit "${EDITOR_STATUS:-0}"
        """
        try Data(stub.utf8).write(to: editor)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: editor.path)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.path + ":" + environment["PATH", default: ""]
        environment["WIFT_EDITOR"] = nil
        environment["WIFT_EDITOR_DIR"] = storage.path
        environment["WIFT_CACHE_DIR"] = directory.appendingPathComponent("runtime").path
        environment["EDITOR_ARGUMENTS"] = directory.appendingPathComponent("arguments").path
        environment["EDITOR_PID"] = directory.appendingPathComponent("editor-pid").path
        environment["EDITOR_EXTENSIONS"] = ""
        self.environment = environment
    }

    func editorArguments() throws -> [String] {
        let data = try Data(contentsOf: directory.appendingPathComponent("arguments"))
        return try data.split(separator: 0).map { try #require(String(bytes: $0, encoding: .utf8)) }
    }

    func run(_ arguments: [String], environment: [String: String]? = nil) throws -> ProcessOutput {
        try start(arguments, environment: environment ?? self.environment).finish()
    }

    func start(_ arguments: [String], environment: [String: String]) throws -> EditorProcess {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = packageRoot.appendingPathComponent(".build/debug/wift")
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let stdout = directory.appendingPathComponent(UUID().uuidString)
        let stderr = directory.appendingPathComponent(UUID().uuidString)
        _ = FileManager.default.createFile(atPath: stdout.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: stdout)
        let errorHandle = try FileHandle(forWritingTo: stderr)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        return EditorProcess(process: process, stdout: stdout, stderr: stderr)
    }
}

private struct EditorProcess {
    let process: Process
    let stdout: URL
    let stderr: URL

    func finish() throws -> ProcessOutput {
        process.waitUntilExit()
        return try ProcessOutput(
            standardOutput: Data(contentsOf: stdout),
            standardError: Data(contentsOf: stderr),
            exitCode: process.terminationStatus
        )
    }
}

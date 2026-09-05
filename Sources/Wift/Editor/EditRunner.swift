import Foundation

struct EditRunner {
    let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func run(scriptPath: String, editorName: String?) throws {
        let script = try Script.resolve(scriptPath)
        let editor = try EditorSelection.resolve(
            requested: editorName, environment: environment,
            find: { ExecutableLookup.find($0, environment: environment) }
        )
        let workspace: URL?
        if editor.kind == .custom {
            // Terminal editors need the foreground process group and job control of wift.
            try Exec.replaceCurrentProcess(
                executable: URL(fileURLWithPath: editor.executable),
                argumentZero: editor.executable,
                arguments: [script.path]
            )
        } else {
            guard URL(fileURLWithPath: script.path).pathExtension == "swift" else {
                throw WiftError("Swift editor integration requires a .swift file; use --editor /path/to/editor to open it as text")
            }
            if editor.kind == .vscode {
                let extensions = try? ProcessExecution.capture(executable: editor.executable, arguments: ["--list-extensions"])
                if let warning = EditorSelection.extensionWarning(extensions) {
                    FileHandle.standardError.write(Data("wift: warning: \(warning)\n".utf8))
                }
            }
            workspace = try prepareWorkspace(script: script, editor: editor.kind)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: editor.executable)
        process.arguments = try editor.arguments(scriptPath: script.path, workspace: workspace)
        process.environment = environment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            throw WiftError("unable to open editor: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let status = process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
            throw WiftError("editor exited unsuccessfully", exitCode: status)
        }
    }

    private func prepareWorkspace(script: Script, editor: EditorSelection.Kind) throws -> URL {
        let storage = try EditorWorkspace(environment: environment)
        let cache = try storage.prepare()
        return try cache.withAccessLock(mode: .shared) {
            let toolchain = try Toolchain.resolve(environment: environment, cache: cache)
            let swiftDirectory = try resolveSwiftDirectory(toolchain: toolchain, editor: editor)
            let module = SupportModule.resolve(
                toolchain: toolchain, moduleCacheContext: toolchain.moduleCacheContext(moduleCachePath: cache.moduleCacheDirectory.path),
                cache: cache
            )
            try SupportModuleBuilder(diagnostics: Diagnostics(isVerbose: false)).prepare(
                module, cache: cache, compiler: SwiftCompiler(toolchain: toolchain)
            )
            let configuration = EditorConfiguration(
                scriptPath: script.path, toolchain: toolchain, module: module, swiftDirectory: swiftDirectory
            )
            let files = try editor == .vscode ? configuration.vscodeFiles() : configuration.xcodeFiles()
            return try storage.publish(scriptPath: script.path, editor: editor.rawValue, files: files, cache: cache)
        }
    }

    private func resolveSwiftDirectory(toolchain: Toolchain, editor: EditorSelection.Kind) throws -> String {
        let selected = try ProcessExecution.capture(executable: "/usr/bin/xcrun", arguments: ["--find", "swiftc"])
        guard selected.exitCode == 0, let text = String(data: selected.standardOutput, encoding: .utf8) else {
            throw WiftError("unable to locate the selected Xcode compiler")
        }
        let selectedPath = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compilerPath = toolchain.compilerPath == "/usr/bin/swiftc" ? selectedPath : toolchain.compilerPath
        let compiler = URL(fileURLWithPath: compilerPath).standardizedFileURL.resolvingSymlinksInPath()
        let directory = compiler.deletingLastPathComponent()
        guard FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("swift").path),
              FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("sourcekit-lsp").path)
        else {
            throw WiftError("editor integration requires a complete Swift toolchain with swift and sourcekit-lsp beside swiftc")
        }
        if editor == .xcode, compiler != URL(fileURLWithPath: selectedPath).standardizedFileURL.resolvingSymlinksInPath() {
            throw WiftError("Xcode and PATH select different Swift toolchains; align them with xcode-select/TOOLCHAINS or use VS Code")
        }
        return directory.path
    }
}

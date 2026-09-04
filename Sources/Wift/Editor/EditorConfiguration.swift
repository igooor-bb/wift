import Foundation

struct EditorConfiguration {
    let scriptPath: String
    let toolchain: Toolchain
    let module: SupportModule
    let swiftDirectory: String

    var analysisArguments: [String] {
        module.moduleCacheContext.arguments + ["-I", module.directory.path]
    }

    func vscodeFiles() throws -> [String: Data] {
        let commands: [[String: Any]] = [[
            "directory": URL(fileURLWithPath: scriptPath).deletingLastPathComponent().path,
            "file": scriptPath,
            "arguments": [toolchain.compilerPath] + analysisArguments + [scriptPath],
        ]]
        let workspace: [String: Any] = [
            "folders": [["path": ".", "name": URL(fileURLWithPath: scriptPath).lastPathComponent]],
            "settings": [
                "swift.path": swiftDirectory,
                "swift.sourcekit-lsp.serverArguments": ["--default-workspace-type", "compilationDatabase"],
                "swift.disableAutoResolve": true,
            ],
            "extensions": ["recommendations": ["swiftlang.swift-vscode"]],
        ]
        return try [
            "script.code-workspace": json(workspace),
            "compile_commands.json": json(commands),
        ]
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

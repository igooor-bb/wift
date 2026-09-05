import Foundation

struct EditorSelection: Equatable {
    enum Kind: String {
        case vscode
        case xcode
        case custom
    }

    let kind: Kind
    let executable: String

    static func resolve(
        requested: String?,
        environment: [String: String],
        find: (String) -> String? = { ExecutableLookup.find($0) },
        application: (String) -> String? = applicationExecutable
    ) throws -> EditorSelection {
        if let name = requested ?? environment["WIFT_EDITOR"], !name.isEmpty {
            switch name {
            case "vscode":
                guard let executable = find("code") ?? application("vscode") else {
                    throw WiftError("VS Code was not found; install it or put its code command on PATH")
                }
                return EditorSelection(kind: .vscode, executable: executable)

            case "xcode":
                guard let executable = application("xcode") else {
                    throw WiftError("Xcode was not found; select a full Xcode installation with xcode-select")
                }
                return EditorSelection(kind: .xcode, executable: executable)

            default:
                guard let executable = find(name) else {
                    throw WiftError("editor not found: \(name); use vscode, xcode, or an executable path without arguments")
                }
                return EditorSelection(kind: .custom, executable: executable)
            }
        }
        if let executable = find("code") ?? application("vscode") {
            return EditorSelection(kind: .vscode, executable: executable)
        }
        if let executable = application("xcode") {
            return EditorSelection(kind: .xcode, executable: executable)
        }
        throw WiftError("no editor found; pass --editor vscode, --editor xcode, or an executable path, or set WIFT_EDITOR")
    }

    func arguments(scriptPath: String, workspace: URL?) throws -> [String] {
        switch kind {
        case .custom:
            return [scriptPath]

        case .vscode:
            guard let workspace else { throw WiftError("missing VS Code workspace") }
            return ["--new-window", workspace.appendingPathComponent("script.code-workspace").path, "--goto", scriptPath]

        case .xcode:
            guard let workspace else { throw WiftError("missing Xcode project") }
            return ["--project", workspace.appendingPathComponent("Script.xcodeproj").path, "--line", "1", scriptPath]
        }
    }

    static func extensionWarning(_ output: ProcessOutput?) -> String? {
        guard let output, output.exitCode == 0, let text = String(data: output.standardOutput, encoding: .utf8) else {
            return "could not check VS Code extensions; for Swift completion and diagnostics install Swift (swiftlang.swift-vscode)"
        }
        let extensions = text.split(whereSeparator: \.isNewline)
        guard !extensions.contains(where: { $0.lowercased() == "swiftlang.swift-vscode" }) else { return nil }
        return "VS Code Swift extension is missing; install Swift (swiftlang.swift-vscode)"
            + " or run: code --install-extension swiftlang.swift-vscode"
    }

    private static func applicationExecutable(_ name: String) -> String? {
        if name == "xcode" {
            guard let output = try? ProcessExecution.capture(executable: "/usr/bin/xcrun", arguments: ["--find", "xed"]),
                  output.exitCode == 0
            else { return nil }
            guard let text = String(data: output.standardOutput, encoding: .utf8) else { return nil }
            let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExecutableLookup.find(path)
        }
        let fileManager = FileManager.default
        for directory in [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ] {
            guard let applications = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for application in applications.sorted(by: { $0.path < $1.path })
                where application.pathExtension == "app" && Bundle(url: application)?.bundleIdentifier == "com.microsoft.VSCode"
            {
                if let executable = ExecutableLookup.find(application.appendingPathComponent("Contents/Resources/app/bin/code").path) {
                    return executable
                }
            }
        }
        return nil
    }
}

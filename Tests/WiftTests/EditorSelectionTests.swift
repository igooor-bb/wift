import Foundation
import Testing
@testable import Wift

struct EditorSelectionTests {
    @Test func explicitEditorOverridesEnvironment() throws {
        let selected = try EditorSelection.resolve(
            requested: "vscode", environment: ["WIFT_EDITOR": "xcode"],
            find: { $0 == "code" ? "/code" : nil }, application: { _ in "/xed" }
        )
        #expect(selected == EditorSelection(kind: .vscode, executable: "/code"))
        let custom = try EditorSelection.resolve(
            requested: nil, environment: ["WIFT_EDITOR": "/my editor"], find: { $0 }, application: { _ in nil }
        )
        #expect(custom.kind == .custom)
        #expect(try custom.arguments(scriptPath: "/space ' ; $(data).swift", workspace: nil) == ["/space ' ; $(data).swift"])
    }

    @Test func defaultsToVSCodeThenXcode() throws {
        let vscode = try EditorSelection.resolve(requested: nil, environment: [:], find: { _ in "/code" }, application: { _ in "/xed" })
        #expect(vscode.kind == .vscode)
        let xcode = try EditorSelection.resolve(
            requested: nil, environment: [:], find: { _ in nil }, application: { $0 == "xcode" ? "/xed" : nil }
        )
        #expect(xcode.kind == .xcode)
        #expect(throws: WiftError.self) {
            try EditorSelection.resolve(requested: nil, environment: [:], find: { _ in nil }, application: { _ in nil })
        }
    }

    @Test func missingOrUnqueryableExtensionProducesInstruction() {
        let present = ProcessOutput(
            standardOutput: Data("another.extension\nswiftlang.swift-vscode\n".utf8),
            standardError: Data(),
            exitCode: 0
        )
        #expect(EditorSelection.extensionWarning(present) == nil)
        let missing = ProcessOutput(standardOutput: Data(), standardError: Data(), exitCode: 0)
        #expect(EditorSelection.extensionWarning(missing)?.contains("code --install-extension swiftlang.swift-vscode") == true)
        #expect(EditorSelection.extensionWarning(nil)?.contains("swiftlang.swift-vscode") == true)
    }

    @Test func parsesEditWithoutChangingScriptPassthrough() throws {
        #expect(try WiftInvocation.parse(commandOrScript: "edit", trailingArguments: ["--editor", "xcode", "script.swift"], verbose: false)
            == .edit(scriptPath: "script.swift", editor: "xcode"))
        #expect(try WiftInvocation.parse(commandOrScript: "./edit", trailingArguments: ["--editor", "xcode"], verbose: false)
            == .run(scriptPath: "./edit", arguments: ["--editor", "xcode"], verbose: false))
        #expect(throws: (any Error).self) {
            try WiftInvocation.parse(commandOrScript: "edit", trailingArguments: ["script.swift", "extra.swift"], verbose: false)
        }
    }
}

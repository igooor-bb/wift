import Foundation
import Testing
@testable import Wift

struct EditorWorkspaceTests {
    @Test func revisionsAreReusableAndIndependentOfRuntimeCache() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("editor")
            let workspace = try EditorWorkspace(environment: ["WIFT_EDITOR_DIR": root.path])
            let cache = try workspace.prepare()
            let files = ["script.code-workspace": Data("original".utf8)]
            let first = try workspace.publish(scriptPath: "/script.swift", editor: "vscode", files: files, cache: cache)
            let second = try workspace.publish(scriptPath: "/script.swift", editor: "vscode", files: files, cache: cache)
            #expect(first == second)
            let changed = try workspace.publish(
                scriptPath: "/script.swift", editor: "vscode", files: ["script.code-workspace": Data("new toolchain".utf8)], cache: cache
            )
            #expect(changed != first)
            #expect(changed.deletingLastPathComponent() == first.deletingLastPathComponent())
            #expect(try Data(contentsOf: first.appendingPathComponent("script.code-workspace")) == files["script.code-workspace"])
            let runtime = try Cache(root: directory.appendingPathComponent("runtime"))
            try runtime.prepare()
            try runtime.withAccessLock(mode: .exclusive) { try runtime.removeAll() }
            #expect(FileManager.default.fileExists(atPath: first.path))
        }
    }

    @Test func rejectsSymlinkRootAndConfiguration() throws {
        try withTemporaryDirectory { directory in
            let target = directory.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let link = directory.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let unsafe = try EditorWorkspace(environment: ["WIFT_EDITOR_DIR": link.path])
            #expect(throws: WiftError.self) { try unsafe.prepare() }

            let workspace = try EditorWorkspace(environment: ["WIFT_EDITOR_DIR": directory.appendingPathComponent("safe").path])
            let cache = try workspace.prepare()
            let files = ["config": Data("hello".utf8)]
            let location = try workspace.publish(scriptPath: "/script.swift", editor: "vscode", files: files, cache: cache)
            let config = location.appendingPathComponent("config")
            try FileManager.default.removeItem(at: config)
            try FileManager.default.createSymbolicLink(at: config, withDestinationURL: target)
            #expect(throws: WiftError.self) {
                try workspace.publish(scriptPath: "/script.swift", editor: "vscode", files: files, cache: cache)
            }
            #expect(FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test func rejectsModifiedConfigurationWithoutOverwritingIt() throws {
        try withTemporaryDirectory { directory in
            let workspace = try EditorWorkspace(environment: ["WIFT_EDITOR_DIR": directory.appendingPathComponent("editor").path])
            let cache = try workspace.prepare()
            let files = ["config": Data("hello".utf8)]
            let location = try workspace.publish(scriptPath: "/script.swift", editor: "vscode", files: files, cache: cache)
            let config = location.appendingPathComponent("config")
            try Data("modified".utf8).write(to: config)
            #expect(throws: WiftError.self) {
                try workspace.publish(scriptPath: "/script.swift", editor: "vscode", files: files, cache: cache)
            }
            #expect(try String(contentsOf: config, encoding: .utf8) == "modified")
        }
    }
}

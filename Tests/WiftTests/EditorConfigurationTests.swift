import Foundation
import Testing
@testable import Wift

struct EditorConfigurationTests {
    @Test func compilationDatabaseRefersToOriginalFileWithoutLinkerFlags() throws {
        let config = try configuration(script: "/original/space ' quote; юникод.swift")
        let files = try config.vscodeFiles()
        let commandData = try #require(files["compile_commands.json"])
        let commands = try #require(JSONSerialization.jsonObject(with: commandData) as? [[String: Any]])
        let command = try #require(commands.first)
        #expect(command["file"] as? String == config.scriptPath)
        let arguments = try #require(command["arguments"] as? [String])
        #expect(arguments.last == config.scriptPath)
        #expect(arguments.contains(config.module.directory.path))
        #expect(!arguments.contains(config.module.objectURL.path))
        #expect(!arguments.contains("-parse-as-library"))
        let workspaceData = try #require(files["script.code-workspace"])
        let workspace = try #require(JSONSerialization.jsonObject(with: workspaceData) as? [String: Any])
        let settings = try #require(workspace["settings"] as? [String: Any])
        #expect(settings["swift.sourcekit-lsp.serverArguments"] as? [String] == ["--default-workspace-type", "compilationDatabase"])
    }

    @Test func xcodeReferencesOriginalFileAndAllowsTopLevelCode() throws {
        let config = try configuration(script: "/original/space ' quote; юникод.swift")
        let files = try config.xcodeFiles()
        let data = try #require(files["Script.xcodeproj/project.pbxproj"])
        let project = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let objects = try #require(project["objects"] as? [String: [String: Any]])
        let source = try #require(objects.values.first { $0["path"] as? String == config.scriptPath })
        #expect(source["sourceTree"] as? String == "<absolute>")
        let settings = try #require(objects.values.compactMap { $0["buildSettings"] as? [String: Any] }
            .first { $0["SWIFT_DISABLE_PARSE_AS_LIBRARY"] != nil })
        #expect(try config.xcodeFiles() == files)
        #expect(settings["SWIFT_DISABLE_PARSE_AS_LIBRARY"] as? String == "YES")
        #expect(settings["MACOSX_DEPLOYMENT_TARGET"] as? String == "13.0")
        #expect(settings["ARCHS"] as? String == "arm64")
    }

    @Test func rejectsXcodeBuildSettingExpansion() throws {
        let config = try configuration(script: "/original/$(HOME).swift")
        #expect(throws: WiftError.self) { try config.xcodeFiles() }
        #expect(try !config.vscodeFiles().isEmpty)
    }

    private func configuration(script: String) throws -> EditorConfiguration {
        let toolchain = Toolchain(
            compilerPath: "/toolchain/usr/bin/swiftc", compilerVersion: "Swift 6.2",
            target: "arm64-apple-macosx13.0", sdkPath: "/SDKs/MacOSX.sdk"
        )
        let cache = try Cache(root: URL(fileURLWithPath: "/editor/cache"))
        return EditorConfiguration(
            scriptPath: script, toolchain: toolchain,
            module: SupportModule.resolve(
                toolchain: toolchain, moduleCacheContext: toolchain.moduleCacheContext(moduleCachePath: cache.moduleCacheDirectory.path),
                cache: cache
            ),
            swiftDirectory: "/toolchain/usr/bin"
        )
    }
}

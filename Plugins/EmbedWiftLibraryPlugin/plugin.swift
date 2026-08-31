import Foundation
import PackagePlugin

@main
struct EmbedWiftLibraryPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target _: any Target
    ) async throws -> [Command] {
        let tool = try context.tool(named: "EmbedWiftLibraryTool").url
        let libraryInput = context.package.directoryURL.appendingPathComponent("Sources/WiftLibrary/Wift.swift")
        let versionInput = context.package.directoryURL.appendingPathComponent("VERSION")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("EmbeddedWiftLibrarySource.swift")
        return [
            .buildCommand(
                displayName: "Embed Wift scripting library and version",
                executable: tool,
                arguments: [libraryInput.path, versionInput.path, output.path],
                inputFiles: [libraryInput, versionInput],
                outputFiles: [output]
            ),
        ]
    }
}

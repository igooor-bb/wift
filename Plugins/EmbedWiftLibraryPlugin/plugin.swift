import Foundation
import PackagePlugin

@main
struct EmbedWiftLibraryPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target _: any Target
    ) async throws -> [Command] {
        let tool = try context.tool(named: "EmbedWiftLibraryTool").url
        let input = context.package.directoryURL.appendingPathComponent("Sources/WiftLibrary/Wift.swift")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("EmbeddedWiftLibrarySource.swift")
        return [
            .buildCommand(
                displayName: "Embed Wift scripting library",
                executable: tool,
                arguments: [input.path, output.path],
                inputFiles: [input],
                outputFiles: [output]
            ),
        ]
    }
}

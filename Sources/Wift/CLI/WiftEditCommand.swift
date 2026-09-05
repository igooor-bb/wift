import ArgumentParser

struct WiftEditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wift edit",
        abstract: "Open an existing script with Swift completion and diagnostics.",
        discussion: """
        Supports VS Code with the Swift extension and Xcode. An executable path opens
        the original file as text. Choose an editor with --editor or WIFT_EDITOR;
        otherwise VS Code is preferred, followed by the selected Xcode installation.
        """
    )

    @Option(name: .long, help: "vscode, xcode, or an editor executable without arguments.")
    var editor: String?

    @Argument(help: "Existing Swift script to edit. The script is never executed.")
    var scriptPath: String
}

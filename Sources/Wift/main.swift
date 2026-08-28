import ArgumentParser

struct WiftCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wift",
        abstract: "Run a cached single-file Swift script.",
    )

    @Argument(help: "Path to a Swift script.")
    var scriptPath: String

    @Argument(parsing: .captureForPassthrough, help: "Arguments passed to the script.")
    var scriptArguments: [String] = []

    mutating func run() throws {}
}

WiftCommand.main()

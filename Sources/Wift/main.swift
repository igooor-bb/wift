import ArgumentParser
import Foundation

struct WiftCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wift",
        abstract: "Run a cached single-file Swift script."
    )

    @Argument(help: "Path to a Swift script.")
    var scriptPath: String

    @Argument(parsing: .captureForPassthrough, help: "Arguments passed to the script.")
    var scriptArguments: [String] = []

    mutating func run() throws {
        do {
            try Runner().run(scriptPath: scriptPath, arguments: scriptArguments)
        } catch let failure as CompilerFailure {
            throw ExitCode(failure.exitCode)
        } catch let error as WiftError {
            FileHandle.standardError.write(Data("wift: \(error.description)\n".utf8))
            throw ExitCode(error.exitCode)
        }
    }
}

WiftCommand.main()

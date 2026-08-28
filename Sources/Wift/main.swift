import ArgumentParser
import Foundation

struct WiftCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wift",
        abstract: "Run a cached single-file Swift script.",
        usage: "[options] <script.swift> [arguments...]",
        discussion: """
        Cache commands:
          wift cache
          wift cache path
          wift cache info <script.swift>
          wift cache clean [script.swift]
        """,
        version: "wift \(WiftVersion.current)"
    )

    @Flag(name: [.short, .long], help: "Show diagnostic information.")
    var verbose = false

    @Argument(help: "Path to a Swift script or cache command.")
    var commandOrScript: String?

    @Argument(parsing: .captureForPassthrough, help: "Arguments passed to the script or cache command.")
    var trailingArguments: [String] = []

    mutating func run() throws {
        do {
            let invocation = try WiftInvocation.parse(
                commandOrScript: commandOrScript,
                trailingArguments: trailingArguments,
                verbose: verbose
            )
            switch invocation {
            case let .run(scriptPath, arguments, verbose):
                try Runner(diagnostics: Diagnostics(isVerbose: verbose))
                    .run(scriptPath: scriptPath, arguments: arguments)

            case .cacheSummary:
                try CacheAdministration().printSummary()

            case .cachePath:
                try CacheAdministration().printPath()

            case let .cacheInfo(scriptPath):
                try CacheAdministration().printInfo(scriptPath: scriptPath)

            case .cacheClean:
                throw CLIError("cache administration is not available")
            }
        } catch let failure as CompilerFailure {
            throw ExitCode(failure.exitCode)
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("wift: \(error.description)\n".utf8))
            throw ExitCode(2)
        } catch let error as WiftError {
            FileHandle.standardError.write(Data("wift: \(error.description)\n".utf8))
            throw ExitCode(error.exitCode)
        }
    }
}

WiftCommand.main()

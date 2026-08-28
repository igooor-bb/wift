import Testing
@testable import Wift

struct WiftInvocationTests {
    @Test(arguments: [false, true])
    func parsesScriptRun(verbose: Bool) throws {
        let invocation = try WiftInvocation.parse(
            commandOrScript: "script.swift",
            trailingArguments: [],
            verbose: verbose
        )

        #expect(invocation == .run(scriptPath: "script.swift", arguments: [], verbose: verbose))
    }

    @Test func stopsParsingAfterScriptPath() throws {
        let command = try WiftCommand.parse(["--verbose", "script.swift", "one", "--verbose", "three"])
        let invocation = try WiftInvocation.parse(
            commandOrScript: command.commandOrScript,
            trailingArguments: command.trailingArguments,
            verbose: command.verbose
        )

        #expect(
            invocation == .run(
                scriptPath: "script.swift",
                arguments: ["one", "--verbose", "three"],
                verbose: true
            )
        )
    }

    @Test(
        arguments: [
            ([], WiftInvocation.cacheSummary),
            (["path"], .cachePath),
            (["info", "script.swift"], .cacheInfo(scriptPath: "script.swift")),
            (["clean"], .cacheClean(scriptPath: nil)),
            (["clean", "script.swift"], .cacheClean(scriptPath: "script.swift")),
        ]
    )
    func parsesCacheCommands(arguments: [String], expected: WiftInvocation) throws {
        let invocation = try WiftInvocation.parse(
            commandOrScript: "cache",
            trailingArguments: arguments,
            verbose: false
        )

        #expect(invocation == expected)
    }

    @Test(
        arguments: [
            (nil, [String](), false),
            ("cache", ["unknown"], false),
            ("cache", ["info"], false),
            ("cache", [String](), true),
        ]
    )
    func rejectsInvalidSyntax(
        commandOrScript: String?,
        trailingArguments: [String],
        verbose: Bool
    ) {
        #expect(throws: CLIError.self) {
            try WiftInvocation.parse(
                commandOrScript: commandOrScript,
                trailingArguments: trailingArguments,
                verbose: verbose
            )
        }
    }
}

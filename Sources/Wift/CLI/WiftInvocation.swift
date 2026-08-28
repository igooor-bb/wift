enum WiftInvocation: Equatable {
    case run(scriptPath: String, arguments: [String], verbose: Bool)
    case cacheSummary
    case cachePath
    case cacheInfo(scriptPath: String)
    case cacheClean(scriptPath: String?)

    static func parse(
        commandOrScript: String?,
        trailingArguments: [String],
        verbose: Bool
    ) throws -> WiftInvocation {
        guard let commandOrScript else {
            throw CLIError("missing script path or command")
        }
        guard commandOrScript == "cache" else {
            return .run(
                scriptPath: commandOrScript,
                arguments: trailingArguments,
                verbose: verbose
            )
        }
        guard !verbose else {
            throw CLIError("--verbose is only valid when running a script")
        }

        guard let cacheCommand = trailingArguments.first else {
            return .cacheSummary
        }

        switch cacheCommand {
        case "path" where trailingArguments.count == 1:
            return .cachePath

        case "info":
            guard trailingArguments.count == 2 else {
                throw CLIError("cache info requires exactly one script path")
            }
            return .cacheInfo(scriptPath: trailingArguments[1])

        case "clean":
            guard trailingArguments.count <= 2 else {
                throw CLIError("cache clean accepts at most one script path")
            }
            return .cacheClean(scriptPath: trailingArguments.dropFirst().first)

        default:
            throw CLIError("invalid cache command")
        }
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

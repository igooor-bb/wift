import Foundation

struct CacheAdministration {
    let environment: [String: String]
    let fileManager: FileManager
    let standardOutput: FileHandle

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        standardOutput: FileHandle = .standardOutput
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.standardOutput = standardOutput
    }

    func printPath() throws {
        let cache = try Cache(environment: environment, fileManager: fileManager)
        write("\(cache.root.path)\n")
    }

    func printSummary() throws {
        let cache = try Cache(environment: environment, fileManager: fileManager)
        let statistics = try cache.statistics()
        write(
            """
            Cache: \(cache.root.path)
            Executables: \(statistics.executableCount)
            Executable cache: \(ByteSizeFormatter.string(fromByteCount: statistics.executableBytes))
            Module cache: \(ByteSizeFormatter.string(fromByteCount: statistics.moduleCacheBytes))
            Total: \(ByteSizeFormatter.string(fromByteCount: statistics.totalBytes))

            """
        )
    }

    func printInfo(scriptPath: String) throws {
        let context = try ScriptContext.resolve(
            scriptPath: scriptPath,
            environment: environment,
            fileManager: fileManager
        )
        let executable = context.cache.cachedExecutable(for: context.key)
        var lines = [
            "Script: \(context.script.path)",
            "Cache status: \(executable == nil ? "miss" : "hit")",
            "Cache key: \(context.key.rawValue)",
        ]
        if let executable {
            lines.append("Executable: \(executable.path)")
        }
        lines.append("Compiler: \(context.toolchain.compilerPath)")
        lines.append("Swift: \(compilerVersionLine(context.toolchain.compilerVersion))")

        if executable != nil {
            if let metadata = CacheMetadata.read(from: context.cache.metadataURL(for: context.key)) {
                lines.append("Created: \(formatDate(metadata.createdAt))")
            } else {
                lines.append("Metadata: unavailable")
            }
        }
        write(lines.joined(separator: "\n") + "\n")
    }

    private func compilerVersionLine(_ version: String) -> String {
        version.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? version
    }

    private func write(_ string: String) {
        standardOutput.write(Data(string.utf8))
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

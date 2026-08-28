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
        let statistics = try cache.withAccessLock(mode: .shared) {
            try cache.statistics()
        }
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
        let output = try context.cache.withAccessLock(mode: .shared) {
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
            return lines.joined(separator: "\n") + "\n"
        }
        write(output)
    }

    func clean(scriptPath: String?) throws {
        if let scriptPath {
            try cleanScript(scriptPath)
        } else {
            try cleanAll()
        }
    }

    private func cleanScript(_ scriptPath: String) throws {
        let context = try ScriptContext.resolve(
            scriptPath: scriptPath,
            environment: environment,
            fileManager: fileManager
        )
        let removed = try context.cache.withAccessLock(mode: .shared) {
            guard fileManager.fileExists(atPath: context.cache.root.path) else {
                return false
            }
            try context.cache.prepare()
            let entryLock = try CacheLock(url: context.cache.lockURL(for: context.key))
            return try entryLock.whileHeld {
                try context.cache.removeEntry(for: context.key)
            }
        }
        if removed {
            write("Removed cache entry for \(context.script.path)\n")
        } else {
            write("No cache entry for \(context.script.path)\n")
        }
    }

    private func cleanAll() throws {
        let cache = try Cache(environment: environment, fileManager: fileManager)
        try cache.withAccessLock(mode: .exclusive) {
            try cache.removeAll()
        }
        write("Cleaned cache: \(cache.root.path)\n")
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

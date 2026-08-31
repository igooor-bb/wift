import CryptoKit
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
            Support cache: \(ByteSizeFormatter.string(fromByteCount: statistics.supportModuleBytes))
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
            let entries = try context.cache.metadataEntries(associatedWith: context.script.path)
                .sorted { $0.metadata.createdAt > $1.metadata.createdAt }
            let activeExecutable = context.cache.hasPathAssociation(for: context.script.path, key: context.key)
                ? context.cache.cachedExecutable(for: context.key)
                : nil
            var lines = [
                "Script: \(context.script.path)",
                "Cache status: \(activeExecutable == nil ? "miss" : "hit")",
                "Cache key: \(context.key.rawValue)",
                "Variants: \(entries.count)",
            ]
            for entry in entries {
                let isActive = entry.key == context.key && context.cache.cachedExecutable(for: entry.key) != nil
                let sourceIsCurrent = entry.metadata.sourceHash == SHA256.hexDigest(of: context.script.contents)
                lines += [
                    "",
                    "Variant: \(entry.key.rawValue)\(isActive ? " ACTIVE" : "")",
                    "Cache key: \(entry.key.rawValue)",
                    "Compiler version: \(compilerVersionLine(entry.metadata.compilerVersion))",
                    "Compiler path: \(entry.metadata.compilerPath)",
                    "Target: \(entry.metadata.target)",
                    "SDK: \(entry.metadata.sdk ?? "none")",
                    "Support fingerprint: \(entry.metadata.supportFingerprint)",
                    "Source current: \(sourceIsCurrent ? "yes" : "no")",
                    "Active: \(isActive ? "yes" : "no")",
                    "Created: \(formatDate(entry.metadata.createdAt))",
                ]
                if let executable = context.cache.cachedExecutable(for: entry.key) {
                    lines.append("Executable: \(executable.path)")
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
        let script = try Script.resolve(scriptPath, fileManager: fileManager)
        let cache = try Cache(environment: environment, fileManager: fileManager)
        let removedCount = try cache.withAccessLock(mode: .shared) {
            guard fileManager.fileExists(atPath: cache.root.path) else {
                return 0
            }
            try cache.prepare()
            let keys = try cache.metadataEntries(associatedWith: script.path)
                .map(\.key)
            var count = 0
            for key in keys {
                let entryLock = try CacheLock(url: cache.lockURL(for: key))
                if try entryLock.whileHeld({ try cache.removePathAssociation(for: script.path, key: key) }) {
                    count += 1
                }
            }
            return count
        }
        if removedCount > 0 {
            write("Removed \(removedCount) cache association(s) for \(script.path)\n")
        } else {
            write("No cache entry for \(script.path)\n")
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

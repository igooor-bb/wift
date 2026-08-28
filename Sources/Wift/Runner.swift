import Foundation

struct Runner {
    let environment: [String: String]
    let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    func run(
        scriptPath: String,
        arguments: [String]
    ) throws -> Never {
        let script = try Script.resolve(scriptPath, fileManager: fileManager)
        let cache = try Cache(environment: environment, fileManager: fileManager)
        try cache.prepare()
        let toolchain = try Toolchain.resolve(environment: environment)
        let compilerArguments = toolchain.compilerArguments(moduleCachePath: cache.moduleCacheDirectory.path)
        let key = FingerprintInput(
            script: script,
            toolchain: toolchain,
            compilerArguments: compilerArguments
        ).cacheKey()

        if let executable = cache.cachedExecutable(for: key) {
            try Exec.replaceCurrentProcess(
                executable: executable,
                scriptPath: script.path,
                arguments: arguments
            )
        }

        let executable: URL
        let lock = try CacheLock(url: cache.lockURL(for: key))
        executable = try lock.whileHeld {
            if let cached = cache.cachedExecutable(for: key) {
                return cached
            }

            try cache.removeInvalidEntryIfPresent(for: key)
            let stagingEntry = try cache.makeStagingEntry(for: key)
            defer { cache.removeStagingEntryIfPresent(stagingEntry) }
            let stagedExecutable = stagingEntry.appendingPathComponent("executable", isDirectory: false)
            try SwiftCompiler(toolchain: toolchain).compile(
                script: script,
                compilerArguments: compilerArguments,
                outputURL: stagedExecutable
            )
            try CacheMetadata(
                script: script,
                key: key,
                toolchain: toolchain,
                compilerArguments: compilerArguments
            ).write(to: stagingEntry.appendingPathComponent("metadata.json", isDirectory: false))
            try cache.install(stagingEntry: stagingEntry, for: key)
            return cache.executableURL(for: key)
        }

        try Exec.replaceCurrentProcess(
            executable: executable,
            scriptPath: script.path,
            arguments: arguments
        )
    }
}

import Foundation

struct Runner {
    let environment: [String: String]
    let fileManager: FileManager
    let diagnostics: Diagnostics

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        diagnostics: Diagnostics = Diagnostics(isVerbose: false)
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.diagnostics = diagnostics
    }

    func run(
        scriptPath: String,
        arguments: [String]
    ) throws -> Never {
        let context = try ScriptContext.resolve(
            scriptPath: scriptPath,
            environment: environment,
            fileManager: fileManager
        )
        let script = context.script
        let cache = context.cache
        try cache.prepare()
        let toolchain = context.toolchain
        let compilerArguments = context.compilerArguments
        let key = context.key
        diagnostics.log("script: \(script.path)")
        diagnostics.log("compiler: \(toolchain.compilerPath)")
        diagnostics.log("cache key: \(key.rawValue)")

        if let executable = cache.cachedExecutable(for: key) {
            diagnostics.log("cache hit")
            diagnostics.log("executable: \(executable.path)")
            diagnostics.log("exec")
            try Exec.replaceCurrentProcess(
                executable: executable,
                scriptPath: script.path,
                arguments: arguments
            )
        }

        diagnostics.log("cache miss")
        let executable: URL
        let lock = try CacheLock(
            url: cache.lockURL(for: key),
            onContention: { diagnostics.log("waiting for cache lock") }
        )
        executable = try lock.whileHeld {
            if let cached = cache.cachedExecutable(for: key) {
                diagnostics.log("cache populated by another process")
                return cached
            }

            try cache.removeInvalidEntryIfPresent(for: key)
            let stagingEntry = try cache.makeStagingEntry(for: key)
            defer { cache.removeStagingEntryIfPresent(stagingEntry) }
            let stagedExecutable = stagingEntry.appendingPathComponent("executable", isDirectory: false)
            diagnostics.log("compiling")
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

        diagnostics.log("executable: \(executable.path)")
        diagnostics.log("exec")
        try Exec.replaceCurrentProcess(
            executable: executable,
            scriptPath: script.path,
            arguments: arguments
        )
    }
}

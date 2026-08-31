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
        try context.cache.withAccessLock(mode: .shared) {
            try run(context: context, arguments: arguments)
        }
    }

    private func run(
        context: ScriptContext,
        arguments: [String]
    ) throws -> Never {
        let script = context.script
        let cache = context.cache
        try cache.prepare()
        let toolchain = context.toolchain
        let compilerArguments = context.compilerArguments
        let key = context.key
        diagnostics.log("script: \(script.path)")
        diagnostics.log("compiler: \(toolchain.compilerPath)")
        diagnostics.log("support module: \(context.supportModule.directory.path)")
        diagnostics.log("cache key: \(key.rawValue)")

        if let executable = cache.cachedExecutable(for: key),
           cache.hasPathAssociation(for: script.path, key: key)
        {
            diagnostics.log(cache.cachedSupportModule(context.supportModule) == nil ? "support cache miss" : "support cache hit")
            diagnostics.log("cache hit")
            diagnostics.log("executable: \(executable.path)")
            diagnostics.log("exec")
            try Exec.replaceCurrentProcess(
                executable: executable,
                scriptPath: script.path,
                arguments: arguments
            )
        }

        let existingExecutable = cache.cachedExecutable(for: key) != nil
        diagnostics.log(existingExecutable ? "cache hit" : "cache miss")
        if !existingExecutable {
            try prepareSupportModule(context.supportModule, cache: cache, compiler: SwiftCompiler(toolchain: toolchain))
        }
        let executable: URL
        let lock = try CacheLock(
            url: cache.lockURL(for: key),
            onContention: { diagnostics.log("waiting for cache lock") }
        )
        executable = try lock.whileHeld {
            if let cached = cache.cachedExecutable(for: key) {
                if !cache.hasPathAssociation(for: script.path, key: key) {
                    try cache.addPathAssociation(for: script.path, key: key)
                    diagnostics.log("associated cached executable with script path")
                } else if !existingExecutable {
                    diagnostics.log("cache populated by another process")
                }
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
                supportFingerprint: context.supportModule.fingerprint,
                compilerConfiguration: context.compilerConfiguration
            ).write(to: stagingEntry.appendingPathComponent("metadata.json", isDirectory: false))
            try cache.writePathAssociation(for: script.path, in: stagingEntry)
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

    private func prepareSupportModule(
        _ module: SupportModule,
        cache: Cache,
        compiler: SwiftCompiler
    ) throws {
        if cache.cachedSupportModule(module) != nil {
            diagnostics.log("support cache hit")
            return
        }

        diagnostics.log("support cache miss")
        let lock = try CacheLock(
            url: cache.supportLockURL(for: module.fingerprint),
            onContention: { diagnostics.log("waiting for support cache lock") }
        )
        try lock.whileHeld {
            if cache.cachedSupportModule(module) != nil {
                diagnostics.log("support cache populated by another process")
                return
            }

            try cache.removeInvalidSupportModuleIfPresent(module)
            let stagingEntry = try cache.makeSupportStagingEntry(for: module.fingerprint)
            defer { cache.removeStagingEntryIfPresent(stagingEntry) }
            let stagedModule = module.inDirectory(stagingEntry)
            do {
                try Data(SupportModule.source.utf8).write(to: stagedModule.sourceURL, options: .atomic)
            } catch {
                throw WiftError("unable to stage support module source: \(error.localizedDescription)")
            }
            try compiler.compileSupportModule(stagedModule)
            do {
                try SupportModuleMetadata(module: stagedModule).write(to: stagedModule.metadataURL)
            } catch {
                throw WiftError("unable to write support module metadata: \(error.localizedDescription)")
            }
            try cache.installSupportModule(stagingEntry: stagingEntry, module: module)
        }
    }
}

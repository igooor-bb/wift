import Foundation

struct ScriptContext {
    let script: Script
    let cache: Cache
    let toolchain: Toolchain
    let moduleCacheContext: ModuleCacheContext
    let supportModule: SupportModule
    let compilerConfiguration: [String]
    let compilerArguments: [String]
    let key: CacheKey

    static func resolve(
        scriptPath: String,
        environment: [String: String],
        fileManager: FileManager
    ) throws -> ScriptContext {
        let script = try Script.resolve(scriptPath, fileManager: fileManager)
        let cache = try Cache(environment: environment, fileManager: fileManager)
        let toolchain = try Toolchain.resolve(environment: environment)
        let moduleCacheContext = toolchain.moduleCacheContext(moduleCachePath: cache.moduleCacheDirectory.path)
        let supportModule = SupportModule.resolve(
            toolchain: toolchain,
            moduleCacheContext: moduleCacheContext,
            cache: cache
        )
        let storageArguments = [
            "-I",
            supportModule.directory.path,
            supportModule.objectURL.path,
        ]
        let compilerConfiguration = [String]()
        let compilerArguments = moduleCacheContext.arguments + storageArguments
        let key = FingerprintInput(
            script: script,
            toolchain: toolchain,
            compilerConfiguration: compilerConfiguration,
            supportFingerprint: supportModule.fingerprint
        ).cacheKey()
        return ScriptContext(
            script: script,
            cache: cache,
            toolchain: toolchain,
            moduleCacheContext: moduleCacheContext,
            supportModule: supportModule,
            compilerConfiguration: compilerConfiguration,
            compilerArguments: compilerArguments,
            key: key
        )
    }
}

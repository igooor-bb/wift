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
        script: Script,
        cache: Cache,
        environment: [String: String]
    ) throws -> ScriptContext {
        let toolchain = try Toolchain.resolve(environment: environment, cache: cache)
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

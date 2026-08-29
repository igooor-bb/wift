import Foundation

struct ScriptContext {
    let script: Script
    let cache: Cache
    let toolchain: Toolchain
    let supportModule: SupportModule
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
        let supportModule = SupportModule.resolve(toolchain: toolchain, cache: cache)
        let compilerArguments = toolchain.compilerArguments(moduleCachePath: cache.moduleCacheDirectory.path) + [
            "-I",
            supportModule.directory.path,
            supportModule.objectURL.path,
        ]
        let key = FingerprintInput(
            script: script,
            toolchain: toolchain,
            compilerArguments: compilerArguments,
            supportFingerprint: supportModule.fingerprint
        ).cacheKey()
        return ScriptContext(
            script: script,
            cache: cache,
            toolchain: toolchain,
            supportModule: supportModule,
            compilerArguments: compilerArguments,
            key: key
        )
    }
}

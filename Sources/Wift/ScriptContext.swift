import Foundation

struct ScriptContext {
    let script: Script
    let cache: Cache
    let toolchain: Toolchain
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
        let compilerArguments = toolchain.compilerArguments(moduleCachePath: cache.moduleCacheDirectory.path)
        let key = FingerprintInput(
            script: script,
            toolchain: toolchain,
            compilerArguments: compilerArguments
        ).cacheKey()
        return ScriptContext(
            script: script,
            cache: cache,
            toolchain: toolchain,
            compilerArguments: compilerArguments,
            key: key
        )
    }
}

import Foundation

struct SupportModuleBuilder {
    let diagnostics: Diagnostics

    func prepare(
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

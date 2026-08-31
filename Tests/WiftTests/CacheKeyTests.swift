import Foundation
import Testing
@testable import Wift

struct CacheKeyTests {
    private let toolchain = Toolchain(
        compilerPath: "/toolchain/usr/bin/swiftc",
        compilerVersion: "Swift 6.2",
        target: "arm64-apple-macosx",
        sdkPath: "/SDKs/MacOSX.sdk"
    )

    @Test func fingerprintIsDeterministic() {
        let input = makeInput()

        #expect(input.cacheKey() == input.cacheKey())
    }

    @Test func sourceChangeInvalidatesFingerprint() {
        #expect(makeInput(source: "a").cacheKey() != makeInput(source: "b").cacheKey())
    }

    @Test func pathChangeDoesNotInvalidateFingerprint() {
        #expect(makeInput(path: "/a/script.swift").cacheKey() == makeInput(path: "/b/script.swift").cacheKey())
    }

    @Test func toolchainChangeInvalidatesFingerprint() {
        let other = Toolchain(
            compilerPath: toolchain.compilerPath,
            compilerVersion: "Swift 6.3",
            target: toolchain.target,
            sdkPath: toolchain.sdkPath
        )

        #expect(makeInput().cacheKey() != makeInput(toolchain: other).cacheKey())
    }

    @Test func compilerConfigurationChangeInvalidatesFingerprint() {
        #expect(
            makeInput(compilerConfiguration: ["-Onone"]).cacheKey()
                != makeInput(compilerConfiguration: ["-O"]).cacheKey()
        )
    }

    @Test func cacheRootDoesNotAffectScriptOrSupportFingerprints() throws {
        let firstCache = try Cache(root: URL(fileURLWithPath: "/cache/one"))
        let secondCache = try Cache(root: URL(fileURLWithPath: "/cache/two"))
        let firstContext = toolchain.moduleCacheContext(moduleCachePath: firstCache.moduleCacheDirectory.path)
        let secondContext = toolchain.moduleCacheContext(moduleCachePath: secondCache.moduleCacheDirectory.path)
        let firstSupport = SupportModule.resolve(toolchain: toolchain, moduleCacheContext: firstContext, cache: firstCache)
        let secondSupport = SupportModule.resolve(toolchain: toolchain, moduleCacheContext: secondContext, cache: secondCache)

        #expect(firstSupport.fingerprint == secondSupport.fingerprint)
        #expect(
            makeInput(supportFingerprint: firstSupport.fingerprint.rawValue).cacheKey()
                == makeInput(supportFingerprint: secondSupport.fingerprint.rawValue).cacheKey()
        )
    }

    @Test func supportAndScriptShareModuleCacheContext() throws {
        try withTemporaryDirectory { directory in
            let cache = try Cache(
                environment: ["WIFT_CACHE_DIR": directory.appendingPathComponent("cache").path],
                fileManager: .default
            )
            let context = toolchain.moduleCacheContext(moduleCachePath: cache.moduleCacheDirectory.path)
            let support = SupportModule.resolve(
                toolchain: toolchain,
                moduleCacheContext: context,
                cache: cache
            )

            #expect(support.moduleCacheContext == context)
            #expect(support.compilerArguments.starts(with: context.arguments))
        }
    }

    @Test func supportModuleChangeInvalidatesFingerprint() {
        #expect(
            makeInput(supportFingerprint: "support-a").cacheKey()
                != makeInput(supportFingerprint: "support-b").cacheKey()
        )
    }

    @Test func serializationIsUnambiguous() {
        let first = FingerprintSerializer.serialize([Data("ab".utf8), Data("c".utf8)])
        let second = FingerprintSerializer.serialize([Data("a".utf8), Data("bc".utf8)])

        #expect(first != second)
    }

    private func makeInput(
        source: String = "print(1)",
        path: String = "/scripts/example.swift",
        toolchain: Toolchain? = nil,
        compilerConfiguration: [String] = [],
        supportFingerprint: String = "support"
    ) -> FingerprintInput {
        FingerprintInput(
            script: Script(path: path, contents: Data(source.utf8)),
            toolchain: toolchain ?? self.toolchain,
            compilerConfiguration: compilerConfiguration,
            supportFingerprint: CacheKey(rawValue: supportFingerprint)
        )
    }
}

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

    @Test func pathChangeInvalidatesFingerprint() {
        #expect(makeInput(path: "/a/script.swift").cacheKey() != makeInput(path: "/b/script.swift").cacheKey())
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

    @Test func compilerArgumentsChangeInvalidatesFingerprint() {
        #expect(makeInput(arguments: ["-Onone"]).cacheKey() != makeInput(arguments: ["-O"]).cacheKey())
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
        arguments: [String] = ["-module-cache-path", "/cache/modules"]
    ) -> FingerprintInput {
        FingerprintInput(
            script: Script(path: path, contents: Data(source.utf8)),
            toolchain: toolchain ?? self.toolchain,
            compilerArguments: arguments
        )
    }
}

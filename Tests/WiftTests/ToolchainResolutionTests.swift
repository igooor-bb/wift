import Foundation
import Testing
@testable import Wift

struct ToolchainResolutionTests {
    @Test func reusesCachedVersionForSameInstallation() throws {
        try withTemporaryDirectory { directory in
            let cache = try preparedCache(in: directory)
            var versionCallCount = 0
            let dependencies = dependencies(identitySuffix: "one") {
                versionCallCount += 1
                return versionOutput("Swift version 6.2.4\nTarget: arm64-apple-macosx26.0")
            }
            let environment = ["SDKROOT": "/SDK"]

            let first = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies
            )
            let second = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies
            )

            #expect(first == second)
            #expect(versionCallCount == 1)
        }
    }

    @Test func invalidatesCachedVersionWhenInstallationIdentityChanges() throws {
        try withTemporaryDirectory { directory in
            let cache = try preparedCache(in: directory)
            var versionCallCount = 0
            let capture: () -> ProcessOutput = {
                versionCallCount += 1
                return versionOutput("Swift version 6.2.4\nTarget: arm64-apple-macosx26.0")
            }
            let environment = ["SDKROOT": "/SDK"]

            _ = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies(identitySuffix: "one", captureVersion: capture)
            )
            _ = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies(identitySuffix: "two", captureVersion: capture)
            )

            #expect(versionCallCount == 2)
        }
    }

    @Test func invalidatesCachedVersionWhenSDKChanges() throws {
        try withTemporaryDirectory { directory in
            let cache = try preparedCache(in: directory)
            var versionCallCount = 0
            let dependencies = dependencies(identitySuffix: "one") {
                versionCallCount += 1
                return versionOutput("Swift version 6.2.4\nTarget: arm64-apple-macosx26.0")
            }

            _ = try Toolchain.resolve(
                environment: ["SDKROOT": "/SDK-one"],
                cache: cache,
                dependencies: dependencies
            )
            _ = try Toolchain.resolve(
                environment: ["SDKROOT": "/SDK-two"],
                cache: cache,
                dependencies: dependencies
            )

            #expect(versionCallCount == 2)
        }
    }

    @Test func doesNotCacheUnknownToolchainLayout() throws {
        try withTemporaryDirectory { directory in
            let cache = try preparedCache(in: directory)
            var versionCallCount = 0
            var dependencies = dependencies(identitySuffix: "one") {
                versionCallCount += 1
                return versionOutput("Swift version 6.2.4\nTarget: arm64-apple-macosx26.0")
            }
            dependencies = ToolchainResolutionDependencies(
                findExecutable: dependencies.findExecutable,
                capture: dependencies.capture,
                machOIdentity: { _ in nil },
                hostIdentity: dependencies.hostIdentity
            )
            let environment = ["SDKROOT": "/SDK"]

            _ = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies
            )
            _ = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies
            )

            #expect(versionCallCount == 2)
        }
    }

    @Test func replacesCorruptResolutionRecord() throws {
        try withTemporaryDirectory { directory in
            let cache = try preparedCache(in: directory)
            var versionCallCount = 0
            let dependencies = dependencies(identitySuffix: "one") {
                versionCallCount += 1
                return versionOutput("Swift version 6.2.4\nTarget: arm64-apple-macosx26.0")
            }
            let environment = ["SDKROOT": "/SDK"]

            _ = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies
            )
            let record = try #require(
                FileManager.default.contentsOfDirectory(
                    at: cache.toolchainsDirectory,
                    includingPropertiesForKeys: nil
                )
                .first { $0.pathExtension == "json" }
            )
            try Data("not json".utf8).write(to: record, options: .atomic)

            _ = try Toolchain.resolve(
                environment: environment,
                cache: cache,
                dependencies: dependencies
            )

            #expect(versionCallCount == 2)
            #expect(cache.trustedData(at: record).flatMap { try? JSONSerialization.jsonObject(with: $0) } != nil)
        }
    }

    @Test func readsMachOUUIDAndSourceVersion() throws {
        try withTemporaryDirectory { directory in
            let binary = directory.appendingPathComponent("swift-frontend")
            var commands = Data()
            append(UInt32(0x1B), to: &commands)
            append(UInt32(24), to: &commands)
            commands.append(contentsOf: 0 ..< 16)
            append(UInt32(0x2A), to: &commands)
            append(UInt32(16), to: &commands)
            append(UInt64(0x0102_0304_0506_0708), to: &commands)

            var binaryData = Data()
            append(UInt32(0xFEED_FACF), to: &binaryData)
            append(UInt32(0), to: &binaryData)
            append(UInt32(0), to: &binaryData)
            append(UInt32(0), to: &binaryData)
            append(UInt32(2), to: &binaryData)
            append(UInt32(commands.count), to: &binaryData)
            append(UInt32(0), to: &binaryData)
            append(UInt32(0), to: &binaryData)
            binaryData.append(commands)
            try binaryData.write(to: binary)

            let identity = try #require(MachOIdentity.read(from: binary))

            #expect(identity.uuid == "000102030405060708090a0b0c0d0e0f")
            #expect(identity.sourceVersion == 0x0102_0304_0506_0708)
        }
    }

    private func preparedCache(in directory: URL) throws -> Cache {
        let cache = try Cache(root: directory.appendingPathComponent("cache"))
        try cache.prepare()
        return cache
    }

    private func dependencies(
        identitySuffix: String,
        captureVersion: @escaping () -> ProcessOutput
    ) -> ToolchainResolutionDependencies {
        ToolchainResolutionDependencies(
            findExecutable: { _, _ in "/toolchain/swift-frontend" },
            capture: { _, arguments in
                #expect(arguments == ["--version"])
                return captureVersion()
            },
            machOIdentity: { url in
                MachOIdentity(
                    uuid: "\(url.lastPathComponent)-\(identitySuffix)",
                    sourceVersion: 1
                )
            },
            hostIdentity: { "macOS|arm64" }
        )
    }

    private func versionOutput(_ version: String) -> ProcessOutput {
        ProcessOutput(
            standardOutput: Data(version.utf8),
            standardError: Data(),
            exitCode: 0
        )
    }

    private func append(_ value: some FixedWidthInteger, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

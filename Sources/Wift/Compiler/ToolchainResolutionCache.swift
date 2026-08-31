import CryptoKit
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct ToolchainResolutionDependencies {
    let findExecutable: (String, [String: String]) -> String?
    let capture: (String, [String]) throws -> ProcessOutput
    let machOIdentity: (URL) -> MachOIdentity?
    let hostIdentity: () -> String

    static var live: ToolchainResolutionDependencies {
        ToolchainResolutionDependencies(
            findExecutable: { name, environment in
                ExecutableLookup.find(name, environment: environment)
            },
            capture: { executable, arguments in
                try ProcessExecution.capture(executable: executable, arguments: arguments)
            },
            machOIdentity: MachOIdentity.read,
            hostIdentity: {
                let version = ProcessInfo.processInfo.operatingSystemVersion
                var system = utsname()
                uname(&system)
                let machineCapacity = MemoryLayout.size(ofValue: system.machine)
                let machine = withUnsafePointer(to: &system.machine) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: machineCapacity) {
                        String(cString: $0)
                    }
                }
                return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)|\(machine)"
            }
        )
    }
}

enum ToolchainInstallationSignature {
    private static let schemaVersion = "1"
    private static let selectorEnvironmentKeys = [
        "DEVELOPER_DIR",
        "MACOSX_DEPLOYMENT_TARGET",
        "SWIFT_EXEC",
        "TOOLCHAINS",
    ]

    static func resolve(
        compilerPath: String,
        sdkPath: String?,
        environment: [String: String],
        dependencies: ToolchainResolutionDependencies
    ) -> CacheKey? {
        let selectedCompilerPath: String
        #if os(macOS)
            if URL(fileURLWithPath: compilerPath).standardizedFileURL.path == "/usr/bin/swiftc" {
                guard let output = try? dependencies.capture("/usr/bin/xcrun", ["--find", "swiftc"]),
                      output.exitCode == 0,
                      let path = String(data: output.standardOutput, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                      !path.isEmpty
                else {
                    return nil
                }
                selectedCompilerPath = path
            } else {
                selectedCompilerPath = compilerPath
            }
        #else
            selectedCompilerPath = compilerPath
        #endif

        let frontend = URL(fileURLWithPath: selectedCompilerPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let driver = frontend.deletingLastPathComponent().appendingPathComponent("swift-driver")
        guard let frontendIdentity = dependencies.machOIdentity(frontend),
              let driverIdentity = dependencies.machOIdentity(driver)
        else {
            return nil
        }

        var fields = [
            Self.schemaVersion,
            compilerPath,
            frontend.path,
            frontendIdentity.uuid,
            frontendIdentity.sourceVersion.map(String.init) ?? "",
            driver.path,
            driverIdentity.uuid,
            driverIdentity.sourceVersion.map(String.init) ?? "",
            sdkPath ?? "",
            dependencies.hostIdentity(),
        ]
        fields += selectorEnvironmentKeys.map { key in
            "\(key)=\(environment[key] ?? "")"
        }
        let data = FingerprintSerializer.serialize(fields.map { Data($0.utf8) })
        return CacheKey(rawValue: SHA256.hexDigest(of: data))
    }
}

private struct ToolchainResolutionRecord: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let signature: String
    let compilerPath: String
    let compilerVersion: String
    let target: String
    let sdkPath: String?

    init(signature: CacheKey, toolchain: Toolchain) {
        schemaVersion = Self.currentSchemaVersion
        self.signature = signature.rawValue
        compilerPath = toolchain.compilerPath
        compilerVersion = toolchain.compilerVersion
        target = toolchain.target
        sdkPath = toolchain.sdkPath
    }

    func toolchain(
        matching signature: CacheKey,
        compilerPath expectedCompilerPath: String,
        sdkPath expectedSDKPath: String?
    ) -> Toolchain? {
        guard schemaVersion == Self.currentSchemaVersion,
              self.signature == signature.rawValue,
              compilerPath == expectedCompilerPath,
              sdkPath == expectedSDKPath,
              !compilerVersion.isEmpty,
              !target.isEmpty
        else {
            return nil
        }
        return Toolchain(
            compilerPath: compilerPath,
            compilerVersion: compilerVersion,
            target: target,
            sdkPath: sdkPath
        )
    }
}

struct ToolchainResolutionCache {
    let cache: Cache

    func resolve(
        signature: CacheKey,
        compilerPath: String,
        sdkPath: String?,
        onMiss: () throws -> Toolchain
    ) throws -> Toolchain {
        let lock = try CacheLock(url: cache.toolchainLockURL(for: signature))
        return try lock.whileHeld {
            if let toolchain = load(
                signature: signature,
                compilerPath: compilerPath,
                sdkPath: sdkPath
            ) {
                return toolchain
            }
            let toolchain = try onMiss()
            try? store(toolchain, signature: signature)
            return toolchain
        }
    }

    private func load(
        signature: CacheKey,
        compilerPath: String,
        sdkPath: String?
    ) -> Toolchain? {
        let url = cache.toolchainResolutionURL(for: signature)
        guard let data = cache.trustedData(at: url),
              let record = try? JSONDecoder().decode(ToolchainResolutionRecord.self, from: data)
        else {
            return nil
        }
        return record.toolchain(
            matching: signature,
            compilerPath: compilerPath,
            sdkPath: sdkPath
        )
    }

    private func store(_ toolchain: Toolchain, signature: CacheKey) throws {
        let destination = cache.toolchainResolutionURL(for: signature)
        let temporary = cache.toolchainsDirectory.appendingPathComponent(
            ".\(signature.rawValue)-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? cache.fileManager.removeItem(at: temporary) }
        let data = try JSONEncoder().encode(ToolchainResolutionRecord(signature: signature, toolchain: toolchain))
        try data.write(to: temporary, options: .withoutOverwriting)
        try cache.fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard temporary.path.withCString({ source in
            destination.path.withCString { target in
                rename(source, target)
            }
        }) == 0 else {
            throw WiftError("unable to cache toolchain resolution: \(String(cString: strerror(errno)))")
        }
    }
}

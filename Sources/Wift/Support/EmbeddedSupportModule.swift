import CryptoKit
import Foundation

struct SupportModule: Equatable {
    static let schemaVersion = "1"
    static let moduleName = "Wift"
    static let source: String = {
        guard let source = String(bytes: PackageResources.Wift_swift, encoding: .utf8) else {
            preconditionFailure("embedded Wift library source is not UTF-8")
        }
        return source
    }()

    let fingerprint: CacheKey
    let compilerArguments: [String]
    let directory: URL

    var sourceURL: URL {
        directory.appendingPathComponent("Wift.swift", isDirectory: false)
    }

    var moduleURL: URL {
        directory.appendingPathComponent("Wift.swiftmodule", isDirectory: false)
    }

    var objectURL: URL {
        directory.appendingPathComponent("Wift.o", isDirectory: false)
    }

    var metadataURL: URL {
        directory.appendingPathComponent("metadata.json", isDirectory: false)
    }

    static func resolve(toolchain: Toolchain, cache: Cache) -> SupportModule {
        let compilerArguments = toolchain.compilerArguments(moduleCachePath: cache.moduleCacheDirectory.path) + [
            "-parse-as-library",
            "-O",
            "-module-name",
            moduleName,
            "-emit-module",
            "-emit-object",
        ]
        let fields = [
            Data(schemaVersion.utf8),
            Data(source.utf8),
            Data(toolchain.compilerPath.utf8),
            Data(toolchain.compilerVersion.utf8),
            Data(toolchain.target.utf8),
            Data((toolchain.sdkPath ?? "").utf8),
            Data(String(compilerArguments.count).utf8),
        ] + compilerArguments.map { Data($0.utf8) }
        let fingerprint = CacheKey(
            rawValue: SHA256.hexDigest(of: FingerprintSerializer.serialize(fields))
        )
        return SupportModule(
            fingerprint: fingerprint,
            compilerArguments: compilerArguments,
            directory: cache.supportDirectory.appendingPathComponent(fingerprint.rawValue, isDirectory: true)
        )
    }

    func inDirectory(_ directory: URL) -> SupportModule {
        SupportModule(
            fingerprint: fingerprint,
            compilerArguments: compilerArguments,
            directory: directory
        )
    }
}

struct SupportModuleMetadata: Codable, Equatable {
    let schemaVersion: String
    let fingerprint: String
    let compilerArguments: [String]

    init(module: SupportModule) {
        schemaVersion = SupportModule.schemaVersion
        fingerprint = module.fingerprint.rawValue
        compilerArguments = module.compilerArguments
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> SupportModuleMetadata? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SupportModuleMetadata.self, from: data)
    }
}

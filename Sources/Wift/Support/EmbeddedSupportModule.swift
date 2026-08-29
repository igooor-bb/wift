import CryptoKit
import Foundation

struct SupportModule: Equatable {
    static let schemaVersion = "1"
    static let moduleName = "Wift"
    static let source: String = {
        guard let source = String(bytes: EmbeddedWiftLibrarySource.bytes, encoding: .utf8) else {
            preconditionFailure("embedded Wift library source is not UTF-8")
        }
        return source
    }()

    let fingerprint: CacheKey
    let moduleCacheContext: ModuleCacheContext
    let actionArguments: [String]
    let directory: URL

    var compilerArguments: [String] {
        moduleCacheContext.arguments + actionArguments
    }

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

    static func resolve(
        toolchain: Toolchain,
        moduleCacheContext: ModuleCacheContext,
        cache: Cache
    ) -> SupportModule {
        let actionArguments = [
            "-parse-as-library",
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
            Data(String(moduleCacheContext.arguments.count).utf8),
        ] + moduleCacheContext.arguments.map { Data($0.utf8) } + [
            Data(String(actionArguments.count).utf8),
        ] + actionArguments.map { Data($0.utf8) }
        let fingerprint = CacheKey(
            rawValue: SHA256.hexDigest(of: FingerprintSerializer.serialize(fields))
        )
        return SupportModule(
            fingerprint: fingerprint,
            moduleCacheContext: moduleCacheContext,
            actionArguments: actionArguments,
            directory: cache.supportDirectory.appendingPathComponent(fingerprint.rawValue, isDirectory: true)
        )
    }

    func inDirectory(_ directory: URL) -> SupportModule {
        SupportModule(
            fingerprint: fingerprint,
            moduleCacheContext: moduleCacheContext,
            actionArguments: actionArguments,
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

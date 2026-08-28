import CryptoKit
import Foundation

struct CacheMetadata: Codable, Equatable {
    let schemaVersion: Int
    let sourcePath: String
    let sourceHash: String
    let cacheKey: String
    let compilerPath: String
    let compilerVersion: String
    let target: String
    let sdk: String?
    let compilerArguments: [String]
    let createdAt: Date

    init(
        script: Script,
        key: CacheKey,
        toolchain: Toolchain,
        compilerArguments: [String],
        createdAt: Date = Date()
    ) {
        schemaVersion = 1
        sourcePath = script.path
        sourceHash = SHA256.hexDigest(of: script.contents)
        cacheKey = key.rawValue
        compilerPath = toolchain.compilerPath
        compilerVersion = toolchain.compilerVersion
        target = toolchain.target
        sdk = toolchain.sdkPath
        self.compilerArguments = compilerArguments
        self.createdAt = createdAt
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(self).write(to: url, options: .atomic)
        } catch {
            throw WiftError("unable to write cache metadata: \(error.localizedDescription)")
        }
    }
}

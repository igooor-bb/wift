import CryptoKit
import Foundation

struct CacheMetadata: Codable, Equatable {
    let schemaVersion: Int
    let sourceHash: String
    let cacheKey: String
    let compilerPath: String
    let compilerVersion: String
    let target: String
    let sdk: String?
    let supportFingerprint: String
    let compilerConfiguration: [String]
    let createdAt: Date

    init(
        script: Script,
        key: CacheKey,
        toolchain: Toolchain,
        supportFingerprint: CacheKey,
        compilerConfiguration: [String],
        createdAt: Date = Date()
    ) {
        schemaVersion = 1
        sourceHash = SHA256.hexDigest(of: script.contents)
        cacheKey = key.rawValue
        compilerPath = toolchain.compilerPath
        compilerVersion = toolchain.compilerVersion
        target = toolchain.target
        sdk = toolchain.sdkPath
        self.supportFingerprint = supportFingerprint.rawValue
        self.compilerConfiguration = compilerConfiguration
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

    static func read(from url: URL) -> CacheMetadata? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CacheMetadata.self, from: data)
    }
}

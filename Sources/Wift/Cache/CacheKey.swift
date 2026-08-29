import CryptoKit
import Foundation

struct CacheKey: Equatable, Hashable, CustomStringConvertible {
    let rawValue: String

    var description: String {
        rawValue
    }

    var shard: String {
        String(rawValue.prefix(2))
    }
}

struct FingerprintInput {
    static let schemaVersion = "1"

    let script: Script
    let toolchain: Toolchain
    let moduleCacheContext: ModuleCacheContext
    let actionArguments: [String]
    let supportFingerprint: CacheKey

    func cacheKey() -> CacheKey {
        var fields = [
            Data(Self.schemaVersion.utf8),
            Data(script.path.utf8),
            script.contents,
            Data(toolchain.compilerPath.utf8),
            Data(toolchain.compilerVersion.utf8),
            Data(supportFingerprint.rawValue.utf8),
            Data(String(moduleCacheContext.arguments.count).utf8),
        ]
        fields.append(contentsOf: moduleCacheContext.arguments.map { Data($0.utf8) })
        fields.append(Data(String(actionArguments.count).utf8))
        fields.append(contentsOf: actionArguments.map { Data($0.utf8) })

        return CacheKey(rawValue: SHA256.hexDigest(of: FingerprintSerializer.serialize(fields)))
    }
}

enum FingerprintSerializer {
    static func serialize(_ fields: [Data]) -> Data {
        var result = Data()
        for field in fields {
            var length = UInt64(field.count).bigEndian
            Swift.withUnsafeBytes(of: &length) { bytes in
                result.append(contentsOf: bytes)
            }
            result.append(field)
        }
        return result
    }
}

extension SHA256 {
    static func hexDigest(of data: Data) -> String {
        hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit
import Foundation

struct PathAssociation: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let canonicalPath: String

    init(canonicalPath: String) {
        schemaVersion = Self.schemaVersion
        self.canonicalPath = canonicalPath
    }

    var identifier: String {
        Self.identifier(for: canonicalPath)
    }

    var fileName: String {
        "\(identifier).json"
    }

    static func identifier(for canonicalPath: String) -> String {
        SHA256.hexDigest(of: Data(canonicalPath.utf8))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(self).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw WiftError("unable to write path association: \(error.localizedDescription)")
        }
    }

    static func read(from url: URL, expectedCanonicalPath: String? = nil) -> PathAssociation? {
        guard let data = try? Data(contentsOf: url),
              let association = try? JSONDecoder().decode(PathAssociation.self, from: data),
              association.schemaVersion == schemaVersion,
              url.lastPathComponent == association.fileName,
              expectedCanonicalPath == nil || association.canonicalPath == expectedCanonicalPath
        else {
            return nil
        }
        return association
    }
}

import Foundation

struct Script: Equatable {
    let path: String
    let contents: Data

    static func resolve(
        _ inputPath: String,
        fileManager: FileManager = .default
    ) throws -> Script {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inputPath, isDirectory: &isDirectory) else {
            throw WiftError("script not found: \(inputPath)")
        }
        guard !isDirectory.boolValue else {
            throw WiftError("not a file: \(inputPath)")
        }

        let canonicalURL = URL(fileURLWithPath: inputPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: canonicalURL.path)
        } catch {
            throw WiftError("unable to inspect script: \(inputPath): \(error.localizedDescription)")
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw WiftError("not a file: \(inputPath)")
        }

        do {
            return try Script(path: canonicalURL.path, contents: Data(contentsOf: canonicalURL))
        } catch {
            throw WiftError("unable to read script: \(inputPath): \(error.localizedDescription)")
        }
    }
}

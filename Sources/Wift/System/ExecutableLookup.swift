import Foundation

enum ExecutableLookup {
    static func find(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if name.contains("/") {
            return executablePath(at: name, fileManager: fileManager)
        }

        for directory in environment["PATH", default: ""].split(separator: ":", omittingEmptySubsequences: false) {
            let base = directory.isEmpty ? fileManager.currentDirectoryPath : String(directory)
            let candidate = URL(fileURLWithPath: base).appendingPathComponent(name).path
            if let path = executablePath(at: candidate, fileManager: fileManager) {
                return path
            }
        }

        return nil
    }

    private static func executablePath(
        at path: String,
        fileManager: FileManager
    ) -> String? {
        guard fileManager.isExecutableFile(atPath: path) else {
            return nil
        }

        return URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}

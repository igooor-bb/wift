import CryptoKit
import Darwin
import Foundation

struct EditorWorkspace {
    let root: URL
    let fileManager: FileManager

    init(environment: [String: String], fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let override = environment["WIFT_EDITOR_DIR"], !override.isEmpty {
            root = URL(fileURLWithPath: override).standardizedFileURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
            )
            root = applicationSupport.appendingPathComponent("wift-editor", isDirectory: true)
        }
    }

    func prepare() throws -> Cache {
        try fileManager.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.createPrivateDirectory(root)
        let cache = try Cache(root: root.appendingPathComponent("support-cache"), fileManager: fileManager)
        try cache.prepare()
        try Self.createPrivateDirectory(root.appendingPathComponent("environments"))
        return cache
    }

    /// The outer identity survives source edits. Immutable revisions let already-open IDEs
    /// keep using their configuration when another invocation selects a different toolchain.
    func publish(scriptPath: String, editor: String, files: [String: Data], cache: Cache) throws -> URL {
        let identity = Self.digest([Data("1".utf8), Data(scriptPath.utf8), Data(editor.utf8)])
        let revision = Self.digest(files.keys.sorted().flatMap { [Data($0.utf8), files[$0]!] })
        let parent = root.appendingPathComponent("environments", isDirectory: true).appendingPathComponent(identity, isDirectory: true)
        let destination = parent.appendingPathComponent(revision, isDirectory: true)
        let lock = try CacheLock(url: cache.locksDirectory.appendingPathComponent("editor-\(identity).lock"))
        return try lock.whileHeld {
            try Self.createPrivateDirectory(parent)
            if Self.status(destination) != nil {
                try Self.validatePrivateDirectory(destination)
                for (path, expected) in files {
                    let file = destination.appendingPathComponent(path)
                    if path.contains("/") {
                        try Self.validatePrivateDirectory(file.deletingLastPathComponent())
                    }
                    guard try Self.readPrivateFile(file, expectedSize: expected.count) == expected else {
                        throw WiftError("editor configuration was modified: \(file.path); move this environment aside and retry")
                    }
                }
                return destination
            }
            let staging = try cache.makeStagingEntry(for: CacheKey(rawValue: revision))
            defer { cache.removeStagingEntryIfPresent(staging) }
            for (path, data) in files {
                let file = staging.appendingPathComponent(path)
                if path.contains("/") {
                    try Self.createPrivateDirectory(file.deletingLastPathComponent())
                }
                try data.write(to: file, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            try fileManager.moveItem(at: staging, to: destination)
            return destination
        }
    }

    private static func digest(_ fields: [Data]) -> String {
        SHA256.hexDigest(of: FingerprintSerializer.serialize(fields))
    }

    private static func status(_ url: URL) -> stat? {
        var value = stat()
        return lstat(url.path, &value) == 0 ? value : nil
    }

    private static func validatePrivateDirectory(_ url: URL) throws {
        guard let value = status(url), value.st_uid == geteuid(),
              value.st_mode & S_IFMT == S_IFDIR, value.st_mode & (S_IRWXG | S_IRWXO) == 0
        else {
            throw WiftError("editor directory is not private and owner-controlled: \(url.path)")
        }
    }

    private static func createPrivateDirectory(_ url: URL) throws {
        guard mkdir(url.path, S_IRWXU) == 0 || errno == EEXIST else {
            throw WiftError("unable to create editor directory: \(url.path): \(String(cString: strerror(errno)))")
        }
        try validatePrivateDirectory(url)
    }

    private static func readPrivateFile(_ url: URL, expectedSize: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw WiftError("unable to read editor configuration: \(url.path)")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_uid == geteuid(),
              value.st_mode & S_IFMT == S_IFREG, value.st_mode & (S_IRWXG | S_IRWXO) == 0, value.st_size == expectedSize
        else {
            throw WiftError("editor configuration is not a private regular file: \(url.path)")
        }
        return try handle.readToEnd() ?? Data()
    }
}

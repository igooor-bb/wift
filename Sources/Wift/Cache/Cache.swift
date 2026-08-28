import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct Cache {
    let root: URL
    let fileManager: FileManager

    var executablesDirectory: URL {
        root.appendingPathComponent("executables", isDirectory: true)
    }

    var moduleCacheDirectory: URL {
        root.appendingPathComponent("module-cache", isDirectory: true)
    }

    var locksDirectory: URL {
        root.appendingPathComponent("locks", isDirectory: true)
    }

    private var stagingDirectory: URL {
        root.appendingPathComponent("staging", isDirectory: true)
    }

    init(
        root: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        if let root {
            self.root = root.standardizedFileURL
        } else if let override = environment["WIFT_CACHE_DIR"], !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        } else {
            do {
                self.root = try fileManager
                    .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                    .appendingPathComponent("wift", isDirectory: true)
            } catch {
                throw WiftError("unable to locate cache directory: \(error.localizedDescription)")
            }
        }
    }

    func prepare() throws {
        do {
            try fileManager.createDirectory(
                at: root.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            for directory in [root, executablesDirectory, moduleCacheDirectory, locksDirectory, stagingDirectory] {
                try createPrivateDirectory(directory)
            }
        } catch {
            if let error = error as? WiftError {
                throw error
            }
            throw WiftError("unable to create cache directory: \(error.localizedDescription)")
        }
    }

    func entryDirectory(for key: CacheKey) -> URL {
        executablesDirectory
            .appendingPathComponent(key.shard, isDirectory: true)
            .appendingPathComponent(key.rawValue, isDirectory: true)
    }

    func executableURL(for key: CacheKey) -> URL {
        entryDirectory(for: key).appendingPathComponent("executable", isDirectory: false)
    }

    func metadataURL(for key: CacheKey) -> URL {
        entryDirectory(for: key).appendingPathComponent("metadata.json", isDirectory: false)
    }

    func cachedExecutable(for key: CacheKey) -> URL? {
        let executable = executableURL(for: key)
        guard let status = fileStatus(at: executable),
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & S_IXUSR != 0,
              status.st_mode & (S_IWGRP | S_IWOTH) == 0
        else {
            return nil
        }
        return executable
    }

    func lockURL(for key: CacheKey) -> URL {
        locksDirectory.appendingPathComponent("\(key.rawValue).lock", isDirectory: false)
    }

    func makeStagingEntry(for key: CacheKey) throws -> URL {
        let directory = stagingDirectory.appendingPathComponent(
            "\(key.rawValue)-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            return directory
        } catch {
            throw WiftError("unable to create cache staging directory: \(error.localizedDescription)")
        }
    }

    func install(stagingEntry: URL, for key: CacheKey) throws {
        let destination = entryDirectory(for: key)
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: stagingEntry.appendingPathComponent("executable").path
            )
            try fileManager.moveItem(at: stagingEntry, to: destination)
        } catch {
            throw WiftError("unable to install cache entry: \(error.localizedDescription)")
        }
    }

    func removeInvalidEntryIfPresent(for key: CacheKey) throws {
        let entry = entryDirectory(for: key)
        guard fileManager.fileExists(atPath: entry.path), cachedExecutable(for: key) == nil else {
            return
        }
        do {
            try fileManager.removeItem(at: entry)
        } catch {
            throw WiftError("unable to replace invalid cache entry: \(error.localizedDescription)")
        }
    }

    func removeStagingEntryIfPresent(_ entry: URL) {
        try? fileManager.removeItem(at: entry)
    }

    private func validatePrivateDirectory(_ directory: URL) throws {
        guard let status = fileStatus(at: directory),
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_mode & (S_IRWXG | S_IRWXO) == 0
        else {
            throw WiftError("cache directory is not private and owner-controlled: \(directory.path)")
        }
    }

    private func createPrivateDirectory(_ directory: URL) throws {
        let result = directory.path.withCString { path in
            mkdir(path, S_IRWXU)
        }
        guard result == 0 || errno == EEXIST else {
            throw WiftError(
                "unable to create cache directory: \(directory.path): \(String(cString: strerror(errno)))"
            )
        }
        try validatePrivateDirectory(directory)
    }

    private func fileStatus(at url: URL) -> stat? {
        var status = stat()
        let result = url.path.withCString { path in
            lstat(path, &status)
        }
        return result == 0 ? status : nil
    }
}

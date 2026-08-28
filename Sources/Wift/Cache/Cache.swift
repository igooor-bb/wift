import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct Cache {
    private static let markerContents = Data("wift-cache-v1\n".utf8)

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

    var accessLockURL: URL {
        root.deletingLastPathComponent().appendingPathComponent(
            ".wift-\(root.lastPathComponent).lock",
            isDirectory: false
        )
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
            try ensureManagedMarker()
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
        guard isTrustedExecutable(executable) else {
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

    func withAccessLock<T>(
        mode: CacheLock.Mode,
        _ body: () throws -> T
    ) throws -> T {
        do {
            try fileManager.createDirectory(
                at: accessLockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw WiftError("unable to create cache lock directory: \(error.localizedDescription)")
        }
        let lock = try CacheLock(url: accessLockURL, mode: mode)
        return try lock.whileHeld(body)
    }

    func removeEntry(for key: CacheKey) throws -> Bool {
        let entry = entryDirectory(for: key)
        guard fileManager.fileExists(atPath: entry.path) else {
            return false
        }
        do {
            try fileManager.removeItem(at: entry)
            return true
        } catch {
            throw WiftError("unable to remove cache entry: \(error.localizedDescription)")
        }
    }

    func removeAll() throws {
        let sharedCacheDirectory: URL
        do {
            sharedCacheDirectory = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        } catch {
            throw WiftError("unable to locate cache directory: \(error.localizedDescription)")
        }
        try CacheCleanupSafety.validate(
            root: root,
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            sharedCacheDirectory: sharedCacheDirectory
        )
        guard fileManager.fileExists(atPath: root.path) else {
            return
        }
        try validatePrivateDirectory(root)

        let defaultRoot = sharedCacheDirectory.appendingPathComponent("wift", isDirectory: true)
        guard rootsResolveToSamePath(root, defaultRoot) || hasValidManagedMarker() else {
            throw WiftError("refusing to clean unmanaged cache path: \(root.path)")
        }
        do {
            try fileManager.removeItem(at: root)
        } catch {
            throw WiftError("unable to clean cache: \(error.localizedDescription)")
        }
    }

    func statistics() throws -> CacheStatistics {
        try CacheStatistics(
            executableCount: validExecutableCount(),
            executableBytes: logicalSize(of: executablesDirectory),
            moduleCacheBytes: logicalSize(of: moduleCacheDirectory),
            totalBytes: logicalSize(of: root)
        )
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

    private func ensureManagedMarker() throws {
        let marker = root.appendingPathComponent(".wift-cache", isDirectory: false)
        if fileManager.fileExists(atPath: marker.path) {
            guard hasValidManagedMarker() else {
                throw WiftError("invalid cache ownership marker: \(marker.path)")
            }
            return
        }
        do {
            try Self.markerContents.write(to: marker, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        } catch {
            throw WiftError("unable to create cache ownership marker: \(error.localizedDescription)")
        }
    }

    private func hasValidManagedMarker() -> Bool {
        let marker = root.appendingPathComponent(".wift-cache", isDirectory: false)
        guard let status = fileStatus(at: marker),
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & (S_IWGRP | S_IWOTH) == 0,
              let contents = try? Data(contentsOf: marker)
        else {
            return false
        }
        return contents == Self.markerContents
    }

    private func rootsResolveToSamePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func fileStatus(at url: URL) -> stat? {
        var status = stat()
        let result = url.path.withCString { path in
            lstat(path, &status)
        }
        return result == 0 ? status : nil
    }

    private func validExecutableCount() throws -> Int {
        try files(in: executablesDirectory).reduce(into: 0) { count, file in
            if file.lastPathComponent == "executable", isTrustedExecutable(file) {
                count += 1
            }
        }
    }

    private func logicalSize(of directory: URL) throws -> UInt64 {
        try files(in: directory).reduce(into: 0) { size, file in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return
            }
            size += UInt64(values.fileSize ?? 0)
        }
    }

    private func files(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw WiftError("unable to read cache directory: \(directory.path)")
        }

        var files = [URL]()
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            files.append(file)
        }
        return files
    }

    private func isTrustedExecutable(_ executable: URL) -> Bool {
        guard let status = fileStatus(at: executable),
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & S_IXUSR != 0,
              status.st_mode & (S_IWGRP | S_IWOTH) == 0
        else {
            return false
        }
        return true
    }
}

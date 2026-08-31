import Darwin
import Foundation

struct CacheFootprint {
    struct Size: Equatable {
        var logical: Int = 0
        var allocated: Int = 0

        static func - (lhs: Size, rhs: Size) -> Size {
            Size(
                logical: lhs.logical - rhs.logical,
                allocated: lhs.allocated - rhs.allocated
            )
        }
    }

    var executable = Size()
    var support = Size()
    var module = Size()
    var metadata = Size()
    var executableCount = 0
    var supportContextCount = 0
    var moduleContextCount = 0
    var pathAssociationCount = 0

    var total: Size {
        Size(
            logical: executable.logical + support.logical + module.logical + metadata.logical,
            allocated: executable.allocated + support.allocated + module.allocated + metadata.allocated
        )
    }

    func subtracting(_ other: CacheFootprint) -> CacheFootprint {
        CacheFootprint(
            executable: executable - other.executable,
            support: support - other.support,
            module: module - other.module,
            metadata: metadata - other.metadata,
            executableCount: executableCount - other.executableCount,
            supportContextCount: supportContextCount - other.supportContextCount,
            moduleContextCount: moduleContextCount - other.moduleContextCount,
            pathAssociationCount: pathAssociationCount - other.pathAssociationCount
        )
    }

    static func capture(cache: URL, fileManager: FileManager = .default) throws -> CacheFootprint {
        guard fileManager.fileExists(atPath: cache.path) else {
            return CacheFootprint()
        }
        guard let enumerator = fileManager.enumerator(
            at: cache,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            throw FixtureError("unable to enumerate cache at \(cache.path)")
        }

        var footprint = CacheFootprint()
        let canonicalCachePath = cache.standardizedFileURL.resolvingSymlinksInPath().path
        while let item = enumerator.nextObject() as? URL {
            var status = stat()
            guard lstat(item.path, &status) == 0 else {
                throw FixtureError("unable to inspect cache item at \(item.path)")
            }
            let fileType = status.st_mode & S_IFMT
            if fileType == S_IFLNK {
                enumerator.skipDescendants()
                continue
            }
            guard fileType == S_IFREG else {
                continue
            }

            let size = Size(
                logical: Int(status.st_size),
                allocated: Int(status.st_blocks) * 512
            )
            let canonicalItemPath = item.standardizedFileURL.resolvingSymlinksInPath().path
            guard canonicalItemPath.hasPrefix(canonicalCachePath + "/") else {
                throw FixtureError("cache item escaped cache root: \(item.path)")
            }
            let relativePath = String(canonicalItemPath.dropFirst(canonicalCachePath.count))
            if relativePath.hasPrefix("/executables/") {
                if item.lastPathComponent == "executable" {
                    footprint.executable.logical += size.logical
                    footprint.executable.allocated += size.allocated
                    footprint.executableCount += 1
                } else {
                    footprint.metadata.logical += size.logical
                    footprint.metadata.allocated += size.allocated
                }
                if relativePath.contains("/paths/"), item.pathExtension == "json" {
                    footprint.pathAssociationCount += 1
                }
            } else if relativePath.hasPrefix("/support/") {
                footprint.support.logical += size.logical
                footprint.support.allocated += size.allocated
                if item.lastPathComponent == "Wift.o" {
                    footprint.supportContextCount += 1
                }
            } else if relativePath.hasPrefix("/module-cache/") {
                footprint.module.logical += size.logical
                footprint.module.allocated += size.allocated
            } else {
                footprint.metadata.logical += size.logical
                footprint.metadata.allocated += size.allocated
            }
        }
        let moduleRoot = cache.appendingPathComponent("module-cache", isDirectory: true)
        footprint.moduleContextCount = try immediateDirectoryCount(at: moduleRoot, fileManager: fileManager)
        return footprint
    }

    private static func immediateDirectoryCount(at root: URL, fileManager: FileManager) throws -> Int {
        guard fileManager.fileExists(atPath: root.path) else {
            return 0
        }
        return try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).count { url in
            try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
    }
}

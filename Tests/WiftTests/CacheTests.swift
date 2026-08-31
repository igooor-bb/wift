import Foundation
import Testing
@testable import Wift

struct CacheTests {
    @Test func cacheLayoutUsesHashShard() throws {
        try withTemporaryDirectory { directory in
            let cache = try Cache(root: directory)
            let key = CacheKey(rawValue: "abcdef0123456789")

            #expect(
                cache.executableURL(for: key).path == directory
                    .appendingPathComponent("executables/ab/abcdef0123456789/executable")
                    .path
            )
        }
    }

    @Test func preparesPrivateCacheDirectories() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("cache", isDirectory: true)
            let cache = try Cache(root: root)

            try cache.prepare()

            for path in [
                cache.root,
                cache.executablesDirectory,
                cache.moduleCacheDirectory,
                cache.supportDirectory,
                cache.toolchainsDirectory,
                cache.locksDirectory,
            ] {
                let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
                #expect(permissions.intValue & 0o077 == 0)
            }
        }
    }

    @Test func rejectsSymlinkAsCachedExecutable() throws {
        try withTemporaryDirectory { directory in
            let cache = try Cache(root: directory.appendingPathComponent("cache"))
            try cache.prepare()
            let key = CacheKey(rawValue: "abcdef0123456789")
            let entry = cache.entryDirectory(for: key)
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("target")
            try Data().write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
            try FileManager.default.createSymbolicLink(
                at: cache.executableURL(for: key),
                withDestinationURL: target
            )

            #expect(cache.cachedExecutable(for: key) == nil)
        }
    }
}

import Foundation
import Testing
@testable import Wift

struct CacheCleanupSafetyTests {
    @Test func rejectsCriticalPaths() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let sharedCache = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let unsafeRoots = [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/tmp", isDirectory: true),
            home,
            sharedCache,
        ]

        for root in unsafeRoots {
            #expect(throws: WiftError.self) {
                try CacheCleanupSafety.validate(
                    root: root,
                    homeDirectory: home,
                    sharedCacheDirectory: sharedCache
                )
            }
        }
    }

    @Test func refusesToRemoveUnmanagedDirectory() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("unmanaged", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let importantFile = root.appendingPathComponent("important")
            try Data("keep".utf8).write(to: importantFile)
            let cache = try Cache(root: root)

            #expect(throws: WiftError.self) {
                try cache.removeAll()
            }
            #expect(FileManager.default.fileExists(atPath: importantFile.path))
        }
    }
}

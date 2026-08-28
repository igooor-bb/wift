import Foundation
import Testing
@testable import Wift

struct CacheStatisticsTests {
    @Test(
        arguments: [
            (UInt64(0), "0 B"),
            (850, "850 B"),
            (1024, "1.0 KiB"),
            (12697, "12.4 KiB"),
            (9_122_611, "8.7 MiB"),
            (1_288_490_189, "1.2 GiB"),
        ]
    )
    func formatsByteCounts(byteCount: UInt64, expected: String) {
        #expect(ByteSizeFormatter.string(fromByteCount: byteCount) == expected)
    }

    @Test func countsOnlyValidExecutablesAndDoesNotFollowSymlinks() throws {
        try withTemporaryDirectory { directory in
            let cache = try Cache(root: directory.appendingPathComponent("cache"))
            try cache.prepare()

            let validKey = CacheKey(rawValue: "abcdef0123456789")
            let validEntry = cache.entryDirectory(for: validKey)
            try FileManager.default.createDirectory(at: validEntry, withIntermediateDirectories: true)
            let executable = cache.executableURL(for: validKey)
            try Data(repeating: 1, count: 10).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

            let invalidKey = CacheKey(rawValue: "fedcba9876543210")
            try FileManager.default.createDirectory(
                at: cache.entryDirectory(for: invalidKey),
                withIntermediateDirectories: true
            )
            try Data(repeating: 2, count: 20).write(
                to: cache.moduleCacheDirectory.appendingPathComponent("module")
            )

            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data(repeating: 3, count: 10000).write(to: outside.appendingPathComponent("large"))
            try FileManager.default.createSymbolicLink(
                at: cache.moduleCacheDirectory.appendingPathComponent("outside"),
                withDestinationURL: outside
            )

            let statistics = try cache.statistics()
            #expect(statistics.executableCount == 1)
            #expect(statistics.executableBytes == 10)
            #expect(statistics.moduleCacheBytes == 20)
            #expect(statistics.totalBytes >= 30)
            #expect(statistics.totalBytes < 10000)
        }
    }
}

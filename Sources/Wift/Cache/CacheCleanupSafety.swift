import Foundation

enum CacheCleanupSafety {
    static func validate(
        root: URL,
        homeDirectory: URL,
        sharedCacheDirectory: URL
    ) throws {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let path = resolvedRoot.path
        let unsafePaths = [
            "/",
            "/tmp",
            "/private/tmp",
            "/var",
            "/private/var",
            "/Library/Caches",
            "/System/Library/Caches",
            homeDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
            sharedCacheDirectory.standardizedFileURL.resolvingSymlinksInPath().path,
        ]
        guard root.isFileURL,
              path.hasPrefix("/"),
              resolvedRoot.pathComponents.count > 2,
              !unsafePaths.contains(path)
        else {
            throw WiftError("refusing to clean unsafe cache path: \(root.path)")
        }
    }
}

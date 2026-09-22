import Foundation
import os

/// Security-scoped bookmarks let an app keep read access to folders the user picked across
/// launches without copying anything into its sandbox.
public enum BookmarkStore {
    public struct Resolved: Sendable {
        public var url: URL
        public var isStale: Bool
        public var didStartAccess: Bool
    }

    public static func makeBookmark(for url: URL) throws -> Data {
        let sw = Stopwatch()
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        Logger.bookmarks.info("[bookmark] created for \(url.lastPathComponent, privacy: .public) bytes=\(data.count) in \(sw.ms, format: .fixed(precision: 1))ms")
        return data
    }

    /// Resolves the bookmark and starts security-scoped access. The caller owns the scope and
    /// must call `stopAccessingSecurityScopedResource()` when done with it.
    public static func resolveAndStartAccess(_ data: Data) throws -> Resolved {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        let started = url.startAccessingSecurityScopedResource()
        Logger.bookmarks.info("[bookmark] resolved \(url.lastPathComponent, privacy: .public) stale=\(isStale) accessStarted=\(started)")
        return Resolved(url: url, isStale: isStale, didStartAccess: started)
    }
}

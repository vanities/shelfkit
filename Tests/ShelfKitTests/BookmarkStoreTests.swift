import XCTest
@testable import ShelfKit

final class BookmarkStoreTests: XCTestCase {
    func testABookmarkResolvesBackToItsFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShelfKit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try BookmarkStore.makeBookmark(for: folder)
        let resolved = try BookmarkStore.resolveAndStartAccess(data)
        defer { if resolved.didStartAccess { resolved.url.stopAccessingSecurityScopedResource() } }
        XCTAssertEqual(resolved.url.standardizedFileURL.resolvingSymlinksInPath().path,
                       folder.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertFalse(resolved.isStale)
    }
}

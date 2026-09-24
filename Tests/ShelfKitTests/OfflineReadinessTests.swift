import XCTest
@testable import ShelfKit

final class OfflineReadinessTests: XCTestCase {
    func testRequiresEveryFileAndRejectsIncompleteCopies() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("first.mp3")
        let second = dir.appendingPathComponent("second.mp3")
        try Data([1, 2, 3]).write(to: first)
        XCTAssertEqual(OfflineReadiness.check(files: [.init(url: first, expectedBytes: 3)], managedCopy: true), .ready)
        XCTAssertEqual(OfflineReadiness.check(files: [.init(url: first, expectedBytes: 4)], managedCopy: true), .unavailable)
        XCTAssertEqual(OfflineReadiness.check(files: [.init(url: first), .init(url: second)], managedCopy: true), .unavailable)
        XCTAssertEqual(OfflineReadiness.check(files: [], managedCopy: true), .unavailable)
    }

    func testImageFolderIncludesNestedPagesAndRejectsEmptyPage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = dir.appendingPathComponent("chapter")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(OfflineReadiness.checkImageFolder(dir, managedCopy: true), .unavailable)
        try Data([1]).write(to: nested.appendingPathComponent("01.jpg"))
        XCTAssertEqual(OfflineReadiness.checkImageFolder(dir, managedCopy: true), .ready)
        XCTAssertEqual(OfflineReadiness.checkImageFolder(dir, managedCopy: true, expectedBytes: 2), .unavailable)
        try Data().write(to: nested.appendingPathComponent("02.jpg"))
        XCTAssertEqual(OfflineReadiness.checkImageFolder(dir, managedCopy: true), .unavailable)
    }
}

import XCTest
@testable import ShelfKit

final class LibraryToolsTests: XCTestCase {
    func testArrivalsBaselineAndCopiesAreNotNewArrivals() {
        var state = LibraryToolsState()
        let source = UUID()
        state.recordScan(source: source, keys: ["one"], previousKeys: [], hadPreviousScan: false)
        XCTAssertTrue(state.arrivals.isEmpty)
        state.recordScan(source: source, keys: ["one", "two"], previousKeys: ["one"], hadPreviousScan: true)
        XCTAssertEqual(Set(state.arrivals.keys), ["two"])
        state.recordScan(source: UUID(), keys: ["two"], previousKeys: ["one", "two"], hadPreviousScan: true)
        XCTAssertEqual(state.arrivals.count, 1)
        state.dismissArrivals()
        state.recordScan(source: source, keys: ["one", "two"], previousKeys: ["one", "two"], hadPreviousScan: true)
        XCTAssertTrue(state.arrivals.isEmpty)
    }

    func testSmartRulesExcludeFinishedAndUnknownEstimates() {
        let now = Date()
        let old = now.addingTimeInterval(-40 * 86400)
        let item = LibraryToolItem(id: "a", title: "A", bytes: 20, isLocal: true, started: true,
                             finished: false, lastOpened: old, remainingSeconds: nil)
        XCTAssertTrue(SmartShelfRule.downloadedUnfinished.matches(item, now: now))
        XCTAssertTrue(SmartShelfRule.abandoned.matches(item, now: now))
        XCTAssertFalse(SmartShelfRule.shortRemaining.matches(item, now: now))
    }

    func testReconnectRejectsTraversalAndDifferentSizes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appending(path: "book.mp3"))
        XCTAssertTrue(RelinkFile(path: "book.mp3", bytes: 3).matches(root: root))
        XCTAssertFalse(RelinkFile(path: "book.mp3", bytes: 4).matches(root: root))
        XCTAssertFalse(RelinkFile(path: "../book.mp3", bytes: 3).matches(root: root))
    }
}

extension LibraryToolsTests {
    func testBackupRejectsWrongAppAndCoverPathTraversal() throws {
        let wrong = LibraryBackupDocument(app: "Mango", state: Data(), covers: [:])
        XCTAssertThrowsError(try wrong.validate(app: "Earmark"))
        let unsafe = LibraryBackupDocument(app: "Mango", state: Data(), covers: ["../../outside": Data()])
        XCTAssertThrowsError(try unsafe.validate(app: "Mango"))
        let safe = LibraryBackupDocument(app: "Mango", state: Data(), covers: ["custom-1234": Data()])
        XCTAssertNoThrow(try safe.validate(app: "Mango"))
    }
    func testReconnectImageFolderAndSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let folder = root.appending(path: "volume")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: folder.appending(path: "1.jpg"))
        XCTAssertTrue(RelinkFile(path: "volume", bytes: 3, imageFolder: true).matches(root: root))
        XCTAssertFalse(RelinkFile(path: "volume", bytes: 4, imageFolder: true).matches(root: root))
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: "escape").path, withDestinationPath: "/tmp")
        XCTAssertFalse(RelinkFile(path: "escape", bytes: 3, imageFolder: true).matches(root: root))
    }
}

extension LibraryToolsTests {
    func testNASRelocationUsesListingsAndRejectsChangedFiles() async throws {
        let files = [RelinkFile(path: "Book/1.mp3", bytes: 100), RelinkFile(path: "Book/2.mp3", bytes: 200)]
        let recorder = ListingRecorder()
        let missing = try await NASRelocation.missing(files: files) { path in
            await recorder.record(path)
            return [NASEntry(name: "1.mp3", relativePath: "Book/1.mp3", isDirectory: false, size: 100, modifiedAt: nil),
                    NASEntry(name: "2.mp3", relativePath: "Book/2.mp3", isDirectory: false, size: 201, modifiedAt: nil)]
        }
        XCTAssertEqual(missing, ["Book/2.mp3"])
        let calls = await recorder.calls
        XCTAssertEqual(calls, ["Book"])
    }
}

private actor ListingRecorder {
    var calls: [String] = []
    func record(_ path: String) { calls.append(path) }
}

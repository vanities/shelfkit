import XCTest
@testable import ShelfKit

/// What the Files app drops into an app's folder while it's open reaches the shelf: the folder
/// watcher reports it, once per burst.
@MainActor
final class FolderWatcherTests: XCTestCase {
    private var folder: URL!

    /// Counts reports; a class so the watcher's main-actor closure can change it.
    private final class Tally { var count = 0 }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testAFileDroppedInIsReported() async throws {
        let reported = expectation(description: "reported")
        let watcher = try XCTUnwrap(FolderWatcher(url: folder, settle: .milliseconds(100)) { reported.fulfill() })
        try Data("audio".utf8).write(to: folder.appending(path: "Emma.m4b"))
        await fulfillment(of: [reported], timeout: 5)
        watcher.stop()
    }

    /// Copying a whole book in is many changes; the shelf should look once, when it's done.
    func testABurstIsReportedOnce() async throws {
        let tally = Tally()
        let settled = expectation(description: "settled")
        let watcher = try XCTUnwrap(FolderWatcher(url: folder, settle: .milliseconds(300)) {
            tally.count += 1
            if tally.count == 1 { settled.fulfill() }
        })
        for track in 1...5 {
            try Data("audio".utf8).write(to: folder.appending(path: "0\(track).mp3"))
        }
        await fulfillment(of: [settled], timeout: 5)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(tally.count, 1)
        watcher.stop()
    }

    func testAFolderThatIsntThereIsNotWatched() {
        XCTAssertNil(FolderWatcher(url: folder.appending(path: "missing")) {})
    }
}

/// A file shared from another app lands in the app's Inbox; it moves up into the app's folder
/// without ever replacing a file already there.
final class OpenedFilesTests: XCTestCase {
    private var documents: URL!

    override func setUpWithError() throws {
        documents = FileManager.default.temporaryDirectory.appending(path: "docs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: documents.appending(path: "Inbox"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: documents)
    }

    func testASharedFileMovesUpOutOfTheInbox() throws {
        let shared = documents.appending(path: "Inbox/Emma.m4b")
        try Data("emma".utf8).write(to: shared)
        XCTAssertTrue(OpenedFiles.isInInbox(shared, documents: documents))

        let kept = OpenedFiles.moveOutOfInbox(shared, into: documents)
        XCTAssertEqual(kept.lastPathComponent, "Emma.m4b")
        XCTAssertFalse(OpenedFiles.isInInbox(kept, documents: documents))
        XCTAssertEqual(try Data(contentsOf: kept), Data("emma".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path(percentEncoded: false)))
    }

    func testANameAlreadyTakenIsNumberedNotReplaced() throws {
        try Data("mine".utf8).write(to: documents.appending(path: "Emma.m4b"))
        let shared = documents.appending(path: "Inbox/Emma.m4b")
        try Data("shared".utf8).write(to: shared)

        let kept = OpenedFiles.moveOutOfInbox(shared, into: documents)
        XCTAssertEqual(kept.lastPathComponent, "Emma 2.m4b")
        XCTAssertEqual(try Data(contentsOf: documents.appending(path: "Emma.m4b")), Data("mine".utf8))
        XCTAssertEqual(try Data(contentsOf: kept), Data("shared".utf8))
    }

    /// An opened file's URL and the app's folder often spell the device's root differently.
    func testPathsMatchWhicheverWayTheRootIsSpelled() throws {
        let file = documents.appending(path: "Jane Austen/Emma.m4b")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("emma".utf8).write(to: file)
        let path = file.path(percentEncoded: false)
        let otherSpelling = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : "/private" + path
        let respelled = URL(filePath: otherSpelling)

        XCTAssertEqual(respelled.relativePath(inside: documents), "Jane Austen/Emma.m4b")
        XCTAssertTrue(respelled.isSameFile(as: file))
        XCTAssertNil(documents.appending(path: "Elsewhere.m4b").relativePath(inside: documents.appending(path: "Jane Austen")))
    }
}

import XCTest
@testable import ShelfKit

/// A move deletes the original, so every way it can go wrong must leave the original where it
/// was — and never replace what's already in the app's folder.
final class LocalMoveTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "LocalMoveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func write(_ bytes: Int, _ seed: UInt8, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &+ Int(seed)) }).write(to: url)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    private func run(_ files: [LocalMove.File], root: URL? = nil, cancel: Bool = false) throws {
        try LocalMove.run(files, into: "Earmark", pruningUpTo: root, progress: { _ in }, isCancelled: { cancel })
    }

    func testAMoveCopiesChecksAndThenRemovesTheOriginal() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/Dune/Dune.m4b"), to = dir.appending(path: "App/Dune/Dune.m4b")
        try write(9_000_000, 3, from)   // more than two chunks
        let original = try Data(contentsOf: from)
        try run([.init(source: from, destination: to, size: 9_000_000)])
        XCTAssertFalse(exists(from))
        XCTAssertEqual(try Data(contentsOf: to), original, "every byte")
        XCTAssertFalse(exists(to.appendingPathExtension("part")))
    }

    func testProgressCountsEveryByte() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/a.mp3"), to = dir.appending(path: "App/a.mp3")
        try write(9_000_000, 1, from)
        let seen = LockedArray()
        try LocalMove.run([.init(source: from, destination: to, size: 9_000_000)], into: "Earmark",
                          progress: { seen.append($0) }, isCancelled: { false })
        XCTAssertEqual(seen.values.last, 9_000_000)
        XCTAssertEqual(seen.values, seen.values.sorted(), "never goes backwards")
    }

    func testTheSameFileAlreadyThereIsNotCopiedAgain() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/a.mp3"), to = dir.appending(path: "App/a.mp3")
        try write(1_000, 1, from)
        try write(1_000, 1, to)
        try run([.init(source: from, destination: to, size: 1_000)])
        XCTAssertFalse(exists(from), "the duplicate collapses into the one already there")
        XCTAssertTrue(exists(to))
    }

    func testADifferentFileThereIsNeverOverwritten() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/a.mp3"), to = dir.appending(path: "App/a.mp3")
        try write(1_000, 1, from)
        try write(500, 9, to)
        XCTAssertThrowsError(try run([.init(source: from, destination: to, size: 1_000)])) { error in
            XCTAssertEqual(error as? LocalMove.Failure, .differentFileThere("a.mp3", app: "Earmark"))
        }
        XCTAssertTrue(exists(from), "the original stays")
        XCTAssertEqual(try Data(contentsOf: to).count, 500, "and so does what was there")
    }

    /// The same size isn't the same file: treating it as one would delete a unique original.
    func testASameSizedDifferentFileIsNeverTakenForTheSame() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/Chapter 01.mp3"), to = dir.appending(path: "App/Chapter 01.mp3")
        try write(5_000_000, 1, from)
        try write(5_000_000, 2, to)
        let there = try Data(contentsOf: to)
        XCTAssertThrowsError(try run([.init(source: from, destination: to, size: 5_000_000)]))
        XCTAssertTrue(exists(from), "the original stays")
        XCTAssertEqual(try Data(contentsOf: to), there, "and what was there is untouched")
    }

    /// One conflict anywhere in a book stops the whole move before a single file is copied.
    func testNothingMovesWhenAnyFileConflicts() throws {
        let dir = try tempDir()
        let first = dir.appending(path: "Picked/Book/01.mp3"), second = dir.appending(path: "Picked/Book/02.mp3")
        try write(1_000, 1, first)
        try write(1_000, 2, second)
        try write(1_000, 7, dir.appending(path: "App/Book/02.mp3"))
        XCTAssertThrowsError(try run([
            .init(source: first, destination: dir.appending(path: "App/Book/01.mp3"), size: 1_000),
            .init(source: second, destination: dir.appending(path: "App/Book/02.mp3"), size: 1_000),
        ]))
        XCTAssertTrue(exists(first) && exists(second))
        XCTAssertFalse(exists(dir.appending(path: "App/Book/01.mp3")), "not even the file that could have gone")
    }

    func testCancellingKeepsTheOriginal() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/a.mp3"), to = dir.appending(path: "App/a.mp3")
        try write(1_000, 1, from)
        XCTAssertThrowsError(try run([.init(source: from, destination: to, size: 1_000)], cancel: true)) { error in
            XCTAssertEqual(error as? LocalMove.Failure, .cancelled)
        }
        XCTAssertTrue(exists(from))
        XCTAssertFalse(exists(to))
    }

    /// If the size is wrong the original must not be touched (a one-byte short file here).
    func testAShortCopyKeepsTheOriginal() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/a.mp3"), to = dir.appending(path: "App/a.mp3")
        try write(1_000, 1, from)
        XCTAssertThrowsError(try run([.init(source: from, destination: to, size: 1_001)]))
        XCTAssertTrue(exists(from))
        XCTAssertFalse(exists(to))
        XCTAssertFalse(exists(to.appendingPathExtension("part")))
    }

    /// A book in discs moves whole; the folders it leaves empty go, up to the folder the user
    /// picked, which stays — as does a folder something else still lives in.
    func testEmptiedFoldersGoButThePickedFolderStays() throws {
        let dir = try tempDir()
        let picked = dir.appending(path: "Picked")
        var files: [LocalMove.File] = []
        for path in ["Author/Book/Disc 1/01.mp3", "Author/Book/Disc 2/01.mp3", "Author/Book/cover.jpg"] {
            try write(2_000, 4, picked.appending(path: path))
            files.append(.init(source: picked.appending(path: path), destination: dir.appending(path: "App/\(path)"), size: 2_000))
        }
        try Data().write(to: picked.appending(path: "Author/Book/.DS_Store"))
        try write(10, 1, picked.appending(path: "Other Author/Other.mp3"))
        try run(files, root: picked)
        XCTAssertFalse(exists(picked.appending(path: "Author")), "emptied all the way up")
        XCTAssertTrue(exists(picked), "the picked folder itself stays")
        XCTAssertTrue(exists(picked.appending(path: "Other Author/Other.mp3")))
        XCTAssertTrue(exists(dir.appending(path: "App/Author/Book/Disc 2/01.mp3")))
    }

    func testWithoutARootNoFolderIsRemoved() throws {
        let dir = try tempDir()
        let from = dir.appending(path: "Picked/Book/a.mp3")
        try write(10, 1, from)
        try run([.init(source: from, destination: dir.appending(path: "App/Book/a.mp3"), size: 10)])
        XCTAssertTrue(exists(dir.appending(path: "Picked/Book")))
    }

    func testMessagesNameTheApp() {
        XCTAssertEqual(LocalMove.Failure.differentFileThere("a.mp3", app: "Earmark").errorDescription,
                       "A different a.mp3 is already in Earmark's folder, so nothing was moved.")
        XCTAssertEqual(LocalMove.Failure.originalsLeft(2, app: "Mango").errorDescription,
                       "Moved into Mango, but 2 original files couldn't be removed from the folder.")
    }

    func testIsInside() {
        let books = URL(filePath: "/x/Books", directoryHint: .isDirectory)
        XCTAssertTrue(URL(filePath: "/x/Books/a.mp3").isInside(books))
        XCTAssertTrue(URL(filePath: "/x/Books/a.mp3").isInside(URL(filePath: "/x/Books/")))
        XCTAssertFalse(URL(filePath: "/x/Books 2/a.mp3").isInside(books), "a sibling sharing the name")
        XCTAssertFalse(books.isInside(books), "not the folder itself")
        XCTAssertFalse(URL(filePath: "/x/Books/../Other/a.mp3").isInside(books))
    }
}

/// Progress arrives on whatever thread copies; collected under a lock.
private final class LockedArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int64] = []
    func append(_ value: Int64) { lock.withLock { storage.append(value) } }
    var values: [Int64] { lock.withLock { storage } }
}

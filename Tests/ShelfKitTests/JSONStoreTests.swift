import XCTest
@testable import ShelfKit

/// The store holds the user's whole library: it must never lose a file it can't read, and must
/// put a moved-aside library back when it can.
final class JSONStoreTests: XCTestCase {
    private struct Library: SalvageableLibrary, Equatable {
        var sources: [String] = []
        var places: [String: Int] = [:]

        init() {}
        init(sources: [String], places: [String: Int]) {
            self.sources = sources
            self.places = places
        }

        var hasUserData: Bool { !sources.isEmpty || !places.isEmpty }
        mutating func merge(restoring old: Library) {
            for source in old.sources where !sources.contains(source) { sources.append(source) }
            for (key, value) in old.places where places[key] == nil { places[key] = value }
        }
        var salvageCounts: [String: Int] { ["sources": sources.count, "places": places.count] }
    }

    private func store() throws -> JSONStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: "JSONStoreTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return JSONStore(appFolder: "unused", directory: dir)
    }

    private func files(_ store: JSONStore) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path(percentEncoded: false))) ?? []).sorted()
    }

    func testTheAppsFolderIsWhereTheLibraryLives() {
        let folder = "ShelfKitTests-\(UUID().uuidString)"
        let store = JSONStore(appFolder: folder)
        addTeardownBlock { try? FileManager.default.removeItem(at: store.directory) }
        XCTAssertEqual(store.directory.lastPathComponent, folder)
        XCTAssertEqual(store.directory.deletingLastPathComponent().lastPathComponent, "Application Support")
    }

    func testALibraryRoundTrips() throws {
        let store = try store()
        let library = Library(sources: ["NAS"], places: ["dune": 42])
        try store.saveJSON(library, named: "library.json")
        XCTAssertEqual(store.loadLibrary(Library.self, named: "library.json"), library)
    }

    func testNoFileIsAnEmptyLibrary() throws {
        XCTAssertEqual(try store().loadLibrary(Library.self, named: "library.json"), Library())
    }

    /// A file this build can't read is moved aside, never left to be overwritten by the next save.
    func testAnUnreadableFileIsMovedAsideNotLost() throws {
        let store = try store()
        try Data("{ not json".utf8).write(to: store.directory.appending(path: "library.json"))
        XCTAssertNil(store.loadJSON(Library.self, named: "library.json"))
        let moved = files(store)
        XCTAssertEqual(moved.count, 1)
        XCTAssertTrue(moved[0].hasPrefix("library.json.corrupt-"))
    }

    /// An older build moved the library aside; this one can read it, so its user state comes
    /// back underneath what's current, and the file is renamed so it's only ever used once.
    func testAMovedAsideLibraryIsRestoredUnderneathTheCurrentOne() throws {
        let store = try store()
        try store.saveJSON(Library(sources: ["On My iPhone"], places: ["dune": 100]), named: "library.json")
        try store.saveJSON(Library(sources: ["NAS"], places: ["dune": 5, "emma": 7]), named: "library.json.corrupt-1000")
        let loaded = store.loadLibrary(Library.self, named: "library.json")
        XCTAssertEqual(loaded.sources, ["On My iPhone", "NAS"])
        XCTAssertEqual(loaded.places, ["dune": 100, "emma": 7], "the current place wins")
        XCTAssertEqual(files(store), ["library.json", "library.json.recovered-1000"])
        XCTAssertEqual(store.loadLibrary(Library.self, named: "library.json"), loaded, "and it's saved")
    }

    func testAMovedAsideFileStillUnreadableIsSetAsideForGood() throws {
        let store = try store()
        try Data("{ still not json".utf8).write(to: store.directory.appending(path: "library.json.corrupt-2000"))
        XCTAssertEqual(store.loadLibrary(Library.self, named: "library.json"), Library())
        XCTAssertEqual(files(store), ["library.json.unreadable-2000"])
    }
}

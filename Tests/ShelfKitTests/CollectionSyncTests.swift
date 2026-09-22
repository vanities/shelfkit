import XCTest
@testable import ShelfKit

/// The rule these guard: something deleted or cleared on one device stays gone on all of them.
final class CollectionSyncTests: XCTestCase {
    private struct Mark: Identifiable, Hashable {
        let id: String
        var note = ""
    }

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testAUnionKeepsBothSidesOnce() {
        let merged = UnionSync.merge([Mark(id: "a", note: "mine")], [Mark(id: "a", note: "theirs"), Mark(id: "b")], without: Tombstones())
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
        XCTAssertEqual(merged.first?.note, "mine", "this device wins a clash")
    }

    /// The bug a plain union had: delete here, and the other side's copy came straight back.
    func testSomethingDeletedDoesNotComeBack() {
        var buried = Tombstones()
        buried.bury("a", at: t0)
        XCTAssertEqual(UnionSync.merge([], [Mark(id: "a"), Mark(id: "b")], without: buried).map(\.id), ["b"])
        XCTAssertEqual(UnionSync.merge([Mark(id: "a")], [], without: buried).map(\.id), [], "deleted elsewhere: goes here too")
    }

    func testTombstonesMergeKeepingTheLaterDeletion() {
        var mine = Tombstones(), theirs = Tombstones()
        mine.bury("a", at: t0)
        theirs.bury("a", at: t0.addingTimeInterval(60))
        theirs.bury("b", at: t0)
        let merged = mine.merging(theirs)
        XCTAssertEqual(merged.dates["a"], t0.addingTimeInterval(60))
        XCTAssertTrue(merged.contains("b"))
    }

    func testOldTombstonesArePruned() {
        let set = Tombstones(["old": t0, "new": t0.addingTimeInterval(86_400 * 200)])
        XCTAssertEqual(Set(set.pruned(before: t0.addingTimeInterval(86_400 * 100)).dates.keys), ["new"])
    }

    func testTombstonesEncodeAsAFlatObject() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(Tombstones(["a": t0])), as: UTF8.self)
        XCTAssertTrue(json.hasPrefix("{\"a\":"), json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(Tombstones.self, from: Data(json.utf8)), Tombstones(["a": t0]))
    }

    /// A cleared rating is a value too: the later of set and clear wins, wherever it happened.
    func testTheLatestSetOrClearWins() {
        let local: [String: Stamped<Int>] = ["dune": Stamped(4, at: t0), "emma": Stamped(nil, at: t0.addingTimeInterval(10))]
        let remote: [String: Stamped<Int>] = ["dune": Stamped(nil, at: t0.addingTimeInterval(5)), "emma": Stamped(3, at: t0),
                                              "ubik": Stamped(5, at: t0)]
        let merged = LatestWins.merge(local, remote)
        XCTAssertNil(merged["dune"]?.value, "cleared after it was rated")
        XCTAssertNil(merged["emma"]?.value, "cleared here after it was rated there")
        XCTAssertEqual(merged["ubik"]?.value, 5)
    }
}

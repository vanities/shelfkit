import XCTest
@testable import ShelfKit

/// iCloud's key-value store, stood in for by a dictionary that counts writes.
private final class MemoryBacking: KeyValueBacking {
    var values: [String: Data] = [:]
    var writes = 0
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        writes += 1
        values[key] = value as? Data
    }
    func synchronize() -> Bool { true }
}

@MainActor
final class CloudKeyValueStoreTests: XCTestCase {
    private struct Place: Codable, Equatable {
        var time: Double
        var at: Date
    }

    func testAValueRoundTripsWithItsDates() {
        let backing = MemoryBacking()
        let store = CloudKeyValueStore(backing: backing)
        let places = ["dune": Place(time: 42, at: Date(timeIntervalSince1970: 1_000_000))]
        XCTAssertTrue(store.save(places, key: "progress.v1"))
        XCTAssertEqual(store.load([String: Place].self, key: "progress.v1"), places)
    }

    /// A book saves its place every few seconds; iCloud throttles an app that writes that often.
    func testWritingTheSameValueAgainWritesNothing() {
        let backing = MemoryBacking()
        let store = CloudKeyValueStore(backing: backing)
        let places = ["b": Place(time: 1, at: .distantPast), "a": Place(time: 2, at: .distantPast)]
        store.save(places, key: "progress.v1")
        store.save(places, key: "progress.v1")
        XCTAssertEqual(backing.writes, 1, "same value, same bytes (keys sorted), no second write")
        store.save(["a": Place(time: 3, at: .distantPast)], key: "progress.v1")
        XCTAssertEqual(backing.writes, 2)
    }

    func testAValueTooBigForICloudIsNotWritten() {
        let backing = MemoryBacking()
        let store = CloudKeyValueStore(backing: backing, maxBytes: 100)
        XCTAssertFalse(store.save(String(repeating: "x", count: 200), key: "big"))
        XCTAssertNil(backing.values["big"])
    }

    func testSomethingUnreadableIsNilNotACrash() {
        let backing = MemoryBacking()
        backing.values["progress.v1"] = Data("not json".utf8)
        XCTAssertNil(CloudKeyValueStore(backing: backing).load([String: Place].self, key: "progress.v1"))
        XCTAssertNil(CloudKeyValueStore(backing: backing).load([String: Place].self, key: "missing"))
    }
}

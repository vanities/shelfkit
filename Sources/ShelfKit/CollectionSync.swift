import Foundation

// Merging what two devices each have, through the user's own iCloud.
//
// A plain union (add whatever the other side has) is right for things that only ever get added,
// and wrong the moment something can be deleted or cleared: the other side still has it, so the
// next merge brings it back. Deletions are remembered as tombstones and synced too; values that
// can change or be cleared (a rating) travel with the time they were set.

/// Deletions remembered long enough to reach every device: id → when it was deleted.
public struct Tombstones: Codable, Hashable, Sendable {
    public private(set) var dates: [String: Date]

    public init(_ dates: [String: Date] = [:]) {
        self.dates = dates
    }

    public var isEmpty: Bool { dates.isEmpty }

    public func contains(_ id: String) -> Bool { dates[id] != nil }

    public mutating func bury(_ id: String, at date: Date = .now) {
        dates[id] = max(date, dates[id] ?? .distantPast)
    }

    /// For ids that can come back (a key rated again), not ones that are unique (a bookmark).
    public mutating func unbury(_ id: String) {
        dates[id] = nil
    }

    /// Both sets' deletions, the later date where they overlap.
    public func merging(_ other: Tombstones) -> Tombstones {
        Tombstones(dates.merging(other.dates) { max($0, $1) })
    }

    /// Without deletions older than `cutoff`: by then every device has seen them, and the set
    /// must not grow forever in a store capped near 1 MB.
    public func pruned(before cutoff: Date) -> Tombstones {
        Tombstones(dates.filter { $0.value >= cutoff })
    }

    // A flat `{id: date}` object in the JSON, rather than `{"dates": {…}}`.
    public init(from decoder: Decoder) throws {
        dates = try decoder.singleValueContainer().decode([String: Date].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dates)
    }
}

public enum UnionSync {
    /// Both lists' items, each once — `local`'s copy wins a clash — and nothing buried.
    public static func merge<Item: Identifiable>(_ local: [Item], _ remote: [Item], without buried: Tombstones) -> [Item]
    where Item.ID == String {
        let known = Set(local.map(\.id))
        return (local + remote.filter { !known.contains($0.id) }).filter { !buried.contains($0.id) }
    }
}

/// A value and when it was set; `nil` records that it was cleared, so the clear syncs as well.
public struct Stamped<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value?
    public var at: Date

    public init(_ value: Value?, at: Date) {
        self.value = value
        self.at = at
    }
}

public enum LatestWins {
    /// Per key, whichever side set it last. A key only one side has is kept as it is.
    public static func merge<Key: Hashable, Value>(_ local: [Key: Stamped<Value>], _ remote: [Key: Stamped<Value>]) -> [Key: Stamped<Value>] {
        local.merging(remote) { mine, theirs in theirs.at > mine.at ? theirs : mine }
    }
}

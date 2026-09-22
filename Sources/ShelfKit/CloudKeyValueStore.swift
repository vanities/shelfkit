import Foundation
import os

/// What `CloudKeyValueStore` writes to: iCloud's key-value store in the apps, a dictionary in tests.
public protocol KeyValueBacking: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueBacking {}

/// The user's own iCloud key-value storage, for the few small things both apps sync between a
/// person's devices — one JSON value per key. Mango's rules, shared so Earmark keeps them too:
/// a value over `maxBytes` isn't written (iCloud caps one near 1 MB), and a write that changes
/// nothing is skipped (iCloud throttles an app that writes too often — and a book saves its
/// place every few seconds). Keys are sorted when encoding, so the same value is the same bytes.
/// Without the iCloud entitlement every call quietly does nothing.
@MainActor
public final class CloudKeyValueStore {
    private let backing: KeyValueBacking
    private let maxBytes: Int
    private var observer: (any NSObjectProtocol)?

    /// Another device changed something.
    public var onExternalChange: (() -> Void)?

    public init(backing: KeyValueBacking = NSUbiquitousKeyValueStore.default, maxBytes: Int = 900_000) {
        self.backing = backing
        self.maxBytes = maxBytes
    }

    /// Starts listening for other devices' changes and pulls what's new.
    public func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: backing as? NSUbiquitousKeyValueStore, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) ?? -1
            Logger.cloud.info("[cloud] external change (reason \(reason))")
            MainActor.assumeIsolated { self?.onExternalChange?() }
        }
        let ok = backing.synchronize()
        Logger.cloud.info("[cloud] started, synchronize=\(ok)")
    }

    /// The value under `key`, or nil when there's none or it can't be read (logged).
    public func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = backing.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Logger.cloud.error("[cloud] \(key, privacy: .public) undecodable (\(data.count)B): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Writes `value` under `key` unless it's too big or already there. Returns whether the
    /// value is now in the store (true for an unchanged value, false when it was too big).
    @discardableResult
    public func save<T: Encodable>(_ value: T, key: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            Logger.cloud.error("[cloud] \(key, privacy: .public) unencodable: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard data.count <= maxBytes else {
            Logger.cloud.error("[cloud] \(key, privacy: .public) is \(data.count)B, over the \(self.maxBytes)B limit — not syncing")
            return false
        }
        if backing.data(forKey: key) == data { return true }
        backing.set(data, forKey: key)
        backing.synchronize()
        Logger.cloud.debug("[cloud] wrote \(key, privacy: .public) \(data.count)B")
        return true
    }
}

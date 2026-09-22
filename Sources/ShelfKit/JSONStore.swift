import Foundation
import os

/// A library file that can be put back together from a copy moved aside by an older build.
public protocol SalvageableLibrary: Codable {
    init()
    /// Anything the user did that's worth restoring (a moved-aside empty library isn't).
    var hasUserData: Bool { get }
    /// Folds an older copy's user state in underneath this one's — this one always wins.
    mutating func merge(restoring old: Self)
    /// What the log reports before and after a salvage: `["sources": 3, "nas": 1, …]`.
    var salvageCounts: [String: Int] { get }
}

/// JSON on disk in Application Support/<appFolder>. Small, inspectable, and it never throws the
/// user's data away: a file it can't read is moved aside (`name.corrupt-<time>`) rather than
/// crashing or being overwritten, and a library an older build moved aside is merged back once
/// a build can read it (`loadLibrary`). Both apps' library files go through it.
public struct JSONStore: Sendable {
    public let directory: URL

    /// `appFolder` names the folder in Application Support ("Mango", "Earmark"). Changing it
    /// would start every user on an empty library, so it's the app's to pin.
    public init(appFolder: String, directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appending(path: appFolder, directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    // MARK: Library

    /// The library file, with any readable copy an older build moved aside merged back in.
    public func loadLibrary<Library: SalvageableLibrary>(_ type: Library.Type, named name: String) -> Library {
        var current = loadJSON(Library.self, named: name) ?? Library()
        // An older build may have moved the library aside as ".corrupt-*" because it couldn't decode
        // a newer field (that is what cost a test library its NAS server). Merge any such file's user
        // state back in — current always wins — and rename it so it is only ever considered once.
        let salvaged = salvageMovedAside(Library.self, named: name)
        guard !salvaged.isEmpty else { return current }
        let before = current.salvageCounts
        for old in salvaged { current.merge(restoring: old) }
        let after = current.salvageCounts
        if before != after {
            let change = after.keys.sorted().map { "\($0) \(before[$0] ?? 0)→\(after[$0] ?? 0)" }.joined(separator: ", ")
            Logger.store.warning("[store] restored moved-aside data: \(change, privacy: .public)")
            try? saveJSON(current, named: name)
        }
        return current
    }

    /// Decodes every `<name>.corrupt-*` this build can read (newest first) and renames each one
    /// away from the `.corrupt-` prefix so a later launch never reconsiders it: `.recovered-` when it
    /// decoded, `.unreadable-` when it did not.
    private func salvageMovedAside<Library: SalvageableLibrary>(_ type: Library.Type, named name: String) -> [Library] {
        let prefix = "\(name).corrupt-"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .sorted(by: >)
        guard !names.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var salvaged: [Library] = []
        for moved in names {
            let url = directory.appending(path: moved)
            do {
                let library = try decoder.decode(Library.self, from: Data(contentsOf: url))
                let counts = library.salvageCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                Logger.store.warning("[store] salvaged \(moved, privacy: .public): \(counts, privacy: .public)")
                if library.hasUserData { salvaged.append(library) }
                rename(url, name: moved, replacing: ".corrupt-", with: ".recovered-")
            } catch {
                Logger.store.error("[store] \(moved, privacy: .public) still unreadable: \(error.localizedDescription, privacy: .public)")
                rename(url, name: moved, replacing: ".corrupt-", with: ".unreadable-")
            }
        }
        return salvaged
    }

    private func rename(_ url: URL, name: String, replacing old: String, with new: String) {
        let destination = directory.appending(path: name.replacingOccurrences(of: old, with: new))
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    // MARK: Any JSON

    /// A JSON file in the folder, or nil when there's none. One that can't be read is moved aside
    /// (`name.corrupt-<time>`) and nil returned, so the next save can't overwrite it.
    public func loadJSON<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        let url = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            Logger.store.info("[store] no \(name, privacy: .public) yet")
            return nil
        }
        let sw = Stopwatch()
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(T.self, from: data)
            Logger.store.info("[store] loaded \(name, privacy: .public) bytes=\(data.count) in \(sw.ms, format: .fixed(precision: 1))ms")
            return value
        } catch {
            Logger.store.error("[store] failed to load \(name, privacy: .public): \(error.localizedDescription, privacy: .public) — moving aside")
            let backup = directory.appending(path: "\(name).corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    /// Writes atomically, with sorted keys and ISO dates, so a diff of two saves is readable.
    public func saveJSON<T: Encodable>(_ value: T, named name: String) throws {
        let sw = Stopwatch()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: directory.appending(path: name), options: .atomic)
        Logger.store.debug("[store] saved \(name, privacy: .public) bytes=\(data.count) in \(sw.ms, format: .fixed(precision: 1))ms")
    }
}

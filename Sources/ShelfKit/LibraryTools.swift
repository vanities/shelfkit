import Foundation

public struct LibraryToolItem: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var bytes: Int64
    public var isLocal: Bool
    public var started: Bool
    public var finished: Bool
    public var lastOpened: Date?
    public var remainingSeconds: Double?
    public init(id: String, title: String, detail: String = "", bytes: Int64, isLocal: Bool,
                started: Bool = false, finished: Bool = false, lastOpened: Date? = nil, remainingSeconds: Double? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.bytes = bytes
        self.isLocal = isLocal; self.started = started; self.finished = finished
        self.lastOpened = lastOpened; self.remainingSeconds = remainingSeconds
    }
}

public enum SmartShelfRule: String, Codable, CaseIterable, Sendable {
    case downloadedUnfinished, abandoned, shortRemaining
    public var title: String {
        switch self {
        case .downloadedUnfinished: "Downloaded and unfinished"
        case .abandoned: "Not opened in 30 days"
        case .shortRemaining: "Under two hours remaining"
        }
    }
    public func matches(_ item: LibraryToolItem, now: Date = .now) -> Bool {
        guard !item.finished else { return false }
        switch self {
        case .downloadedUnfinished: return item.isLocal
        case .abandoned: return item.started && item.lastOpened.map { now.timeIntervalSince($0) >= 30 * 86400 } == true
        case .shortRemaining: return item.remainingSeconds.map { $0 > 0 && $0 <= 7200 } == true
        }
    }
}

public struct SmartShelf: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rule: SmartShelfRule
    public init(name: String, rule: SmartShelfRule) { id = UUID(); self.name = name; self.rule = rule }
}

/// Device-local discovery and preferences; no deletable collection is unioned through iCloud.
public struct LibraryToolsState: Codable, Sendable {
    public var smartShelves: [SmartShelf] = []
    public var arrivals: [String: Date] = [:]
    public var baselinedSources: Set<UUID> = []
    public var dismissedGaps: Set<String> = []
    public init() {}
    public mutating func recordScan(source: UUID, keys: Set<String>, previousKeys: Set<String>, hadPreviousScan: Bool, now: Date = .now) {
        if hadPreviousScan || baselinedSources.contains(source) {
            for key in keys.subtracting(previousKeys) where arrivals[key] == nil { arrivals[key] = now }
        }
        baselinedSources.insert(source)
    }
    public mutating func dismissArrivals() { arrivals.removeAll() }
    private enum CodingKeys: String, CodingKey { case smartShelves, arrivals, baselinedSources, dismissedGaps }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        smartShelves = try c.decodeIfPresent([SmartShelf].self, forKey: .smartShelves) ?? []
        arrivals = try c.decodeIfPresent([String: Date].self, forKey: .arrivals) ?? [:]
        baselinedSources = try c.decodeIfPresent(Set<UUID>.self, forKey: .baselinedSources) ?? []
        dismissedGaps = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedGaps) ?? []
    }
}

public struct RelinkFile: Sendable {
    public let path: String
    public let bytes: Int64
    public let imageFolder: Bool
    public init(path: String, bytes: Int64, imageFolder: Bool = false) { self.path = path; self.bytes = bytes; self.imageFolder = imageFolder }
    public func matches(root: URL) -> Bool {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), bytes > 0 else { return false }
        let target = root.appending(path: path).resolvingSymlinksInPath()
        let base = root.resolvingSymlinksInPath().path + "/"
        if imageFolder {
            guard target.path.hasPrefix(base),
                  let entries = try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return false }
            var allBytes: Int64 = 0, imageBytes: Int64 = 0, imageCount = 0
            let extensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff"]
            for entry in entries {
                guard entry.resolvingSymlinksInPath().path.hasPrefix(base),
                      let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), let size = values.fileSize else { return false }
                allBytes += Int64(size)
                if values.isRegularFile == true, extensions.contains(entry.pathExtension.lowercased()) { imageBytes += Int64(size); imageCount += 1 }
            }
            return imageCount > 0 && (allBytes == bytes || imageBytes == bytes)
        }
        guard target.path.hasPrefix(base),
              let values = try? target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize else { return false }
        return Int64(size) == bytes
    }
}

public struct LibraryBackupDocument: Codable, Sendable {
    public var version: Int = 1
    public let app: String
    public let date: Date
    public let state: Data
    public let covers: [String: Data]
    public init(app: String, state: Data, covers: [String: Data]) {
        self.app = app; self.date = .now; self.state = state; self.covers = covers
    }
    public static func safeCoverID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count < 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
    public func validate(app expected: String) throws {
        guard version == 1, app == expected, covers.count <= 10000,
              covers.keys.allSatisfy(Self.safeCoverID) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

import Foundation
import os

/// Moves a book's files from a folder the user picked into the app's own folder: copy, check
/// each one arrived whole, and only then remove the originals. Nothing already in the app's
/// folder is ever overwritten — the same file there (byte for byte) counts as moved; a
/// different one stops the move before any file is copied or removed.
///
/// Always a real copy, read and written in chunks: never a clone or a rename, which for a file
/// iCloud hasn't downloaded yet could leave a placeholder where the book should be — and then
/// delete the only real copy.
public enum LocalMove {
    public struct File: Sendable, Equatable {
        public let source: URL
        public let destination: URL
        /// The size the library last saw; a copy that comes out different keeps the original.
        public let size: Int64

        public init(source: URL, destination: URL, size: Int64) {
            self.source = source
            self.destination = destination
            self.size = size
        }
    }

    public enum Failure: LocalizedError, Equatable {
        /// A different file of the same name is already in the app's folder.
        case differentFileThere(String, app: String)
        /// A copy came out the wrong size; the original was kept.
        case incomplete(String)
        case cancelled
        /// Copied and checked, but the folder wouldn't let go of these originals.
        case originalsLeft(Int, app: String)

        public var errorDescription: String? {
            switch self {
            case .differentFileThere(let name, let app): "A different \(name) is already in \(app)'s folder, so nothing was moved."
            case .incomplete(let name): "\(name) didn't copy completely. The original is untouched."
            case .cancelled: "Cancelled. The original is untouched."
            case .originalsLeft(let count, let app): "Moved into \(app), but \(count) original file\(count == 1 ? "" : "s") couldn't be removed from the folder."
            }
        }
    }

    static let chunkBytes = 4 * 1024 * 1024

    /// Moves `files` into `app`'s folder (their destinations), then removes every folder the
    /// originals leave holding nothing but dotfiles, walking up to — never removing, never
    /// leaving — `root`, the folder the user picked. Throws before touching an original if
    /// anything is off; `progress` gets bytes done so far.
    public static func run(_ files: [File], into app: String, pruningUpTo root: URL? = nil,
                           progress: @Sendable (Int64) -> Void, isCancelled: @Sendable () -> Bool) throws {
        let sw = Stopwatch()
        let total = files.reduce(0) { $0 + $1.size }
        Logger.move.info("[move] start files=\(files.count) bytes=\(total) into \(app, privacy: .public)")
        // Nothing is copied until every file is either missing from the app's folder or already
        // there byte for byte. Same size isn't proof: removing the original would lose it.
        var alreadyThere = Set<URL>()
        for file in files where exists(file.destination) {
            guard try sameContents(file.source, file.destination, isCancelled: isCancelled) else {
                Logger.move.error("[move] refused: a different \(file.destination.lastPathComponent, privacy: .public) is already in \(app, privacy: .public)'s folder")
                throw Failure.differentFileThere(file.destination.lastPathComponent, app: app)
            }
            alreadyThere.insert(file.destination)
        }
        if !alreadyThere.isEmpty {
            Logger.move.info("[move] \(alreadyThere.count) file(s) already there byte for byte — not copied again")
        }

        let fileManager = FileManager.default
        var done: Int64 = 0
        for file in files {
            if isCancelled() { throw Failure.cancelled }
            if alreadyThere.contains(file.destination) {
                done += file.size
                progress(done)
                continue
            }
            // One that arrived after the check above answers to the same rule.
            if exists(file.destination) {
                guard try sameContents(file.source, file.destination, isCancelled: isCancelled) else {
                    Logger.move.error("[move] refused: a different \(file.destination.lastPathComponent, privacy: .public) appeared in \(app, privacy: .public)'s folder")
                    throw Failure.differentFileThere(file.destination.lastPathComponent, app: app)
                }
                alreadyThere.insert(file.destination)
                done += file.size
                progress(done)
                continue
            }
            try fileManager.createDirectory(at: file.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = file.destination.appendingPathExtension("part")
            try? fileManager.removeItem(at: partial)
            let base = done
            do {
                try copy(from: file.source, to: partial, progress: { progress(base + $0) }, isCancelled: isCancelled)
            } catch {
                try? fileManager.removeItem(at: partial)
                Logger.move.error("[move] copy of \(file.source.lastPathComponent, privacy: .public) stopped: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            let copied = size(of: partial)
            guard copied == file.size else {
                try? fileManager.removeItem(at: partial)
                Logger.move.error("[move] \(file.source.lastPathComponent, privacy: .public) copied \(copied) of \(file.size) bytes — original kept")
                throw Failure.incomplete(file.source.lastPathComponent)
            }
            try fileManager.moveItem(at: partial, to: file.destination)
            done += file.size
            progress(done)
        }

        // Every file is in the app's folder, whole: only now do the originals go.
        var left = 0
        for file in files {
            do {
                try fileManager.removeItem(at: file.source)
            } catch {
                left += 1
                Logger.move.error("[move] couldn't remove original \(file.source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if let root {
            removeEmptyFolders(Set(files.map { $0.source.deletingLastPathComponent() }), upTo: root)
        }
        Logger.move.info("[move] done files=\(files.count) copied=\(files.count - alreadyThere.count) originalsLeft=\(left) in \(sw.ms, format: .fixed(precision: 0))ms")
        if left > 0 { throw Failure.originalsLeft(left, app: app) }
    }

    /// Each folder that holds nothing but dotfiles goes, then its parent, and so on up to `root`,
    /// which always stays — as does anything that isn't inside it.
    static func removeEmptyFolders(_ folders: Set<URL>, upTo root: URL) {
        let fileManager = FileManager.default
        for start in folders.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            var folder = start.standardizedFileURL
            while folder.isInside(root),
                  let names = try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)),
                  names.allSatisfy({ $0.hasPrefix(".") }) {
                do {
                    try fileManager.removeItem(at: folder)
                    Logger.move.debug("[move] removed emptied folder \(folder.lastPathComponent, privacy: .public)")
                } catch {
                    Logger.move.error("[move] couldn't remove emptied folder \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    break
                }
                folder = folder.deletingLastPathComponent()
            }
        }
    }

    /// Byte for byte, a chunk at a time — sizes first, so a different file usually costs one look.
    static func sameContents(_ a: URL, _ b: URL, isCancelled: () -> Bool) throws -> Bool {
        let sizeA = size(of: a)
        guard sizeA >= 0 else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: a]) }
        guard sizeA == size(of: b) else { return false }
        let left = try FileHandle(forReadingFrom: a)
        defer { try? left.close() }
        let right = try FileHandle(forReadingFrom: b)
        defer { try? right.close() }
        while true {
            if isCancelled() { throw Failure.cancelled }
            let chunkA = try left.read(upToCount: chunkBytes) ?? Data()
            let chunkB = try right.read(upToCount: chunkBytes) ?? Data()
            guard chunkA == chunkB else { return false }
            if chunkA.isEmpty { return true }
        }
    }

    private static func copy(from source: URL, to destination: URL, progress: (Int64) -> Void, isCancelled: () -> Bool) throws {
        guard FileManager.default.createFile(atPath: destination.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        var copied: Int64 = 0
        while let chunk = try reader.read(upToCount: chunkBytes), !chunk.isEmpty {
            if isCancelled() { throw Failure.cancelled }
            try writer.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            progress(copied)
        }
        try writer.synchronize()
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1)
    }
}

public extension URL {
    /// Whether this file is somewhere inside `folder` (not the folder itself, nor a sibling
    /// that merely starts with its name: "Books 2" isn't inside "Books"). A directory URL's
    /// path may or may not end in "/"; both work.
    func isInside(_ folder: URL) -> Bool {
        var base = folder.standardizedFileURL.path(percentEncoded: false)
        if !base.hasSuffix("/") { base += "/" }
        let path = standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix(base) && path.count > base.count
    }
}

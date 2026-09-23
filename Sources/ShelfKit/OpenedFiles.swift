import Foundation
import os

/// A file handed to the app with "Open With" or a share sheet. From another app it arrives as
/// the app's own copy in Documents/Inbox, iOS's folder and no place to keep it; from Files it's
/// opened where it is.
public enum OpenedFiles {
    /// Moves a file iOS copied into Documents/Inbox up into Documents itself, where it's an
    /// ordinary file of the app's own. A name already taken gets a number ("Emma 2.m4b"); nothing
    /// is replaced. Returns where the file is now: the original URL if it couldn't move.
    public static func moveOutOfInbox(_ url: URL, into documents: URL) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var destination = documents.appending(path: url.lastPathComponent)
        var copy = 2
        while FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            destination = documents.appending(path: ext.isEmpty ? "\(stem) \(copy)" : "\(stem) \(copy).\(ext)")
            copy += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            Logger.files.info("[open] moved \(url.lastPathComponent, privacy: .public) out of Inbox as \(destination.lastPathComponent, privacy: .public)")
            return destination
        } catch {
            Logger.files.error("[open] couldn't move \(url.lastPathComponent, privacy: .public) out of Inbox: \(error.localizedDescription, privacy: .public)")
            return url
        }
    }

    /// Whether a file sits in the app's Inbox (Documents/Inbox).
    public static func isInInbox(_ url: URL, documents: URL) -> Bool {
        url.relativePath(inside: documents.appending(path: "Inbox")) != nil
    }
}

public extension URL {
    /// This file's path under `folder` ("Author/Book/01.mp3"), or nil when it isn't inside it.
    /// Unlike `isInside`, it resolves symlinks first, so the device's root can be spelled either
    /// way (/var or /private/var): an opened file's URL and the app's own folder often differ there.
    func relativePath(inside folder: URL) -> String? {
        var base = folder.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        if !base.hasSuffix("/") { base += "/" }
        let path = resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        guard path.hasPrefix(base), path.count > base.count else { return nil }
        return String(path.dropFirst(base.count))
    }

    /// Whether two URLs name the same file, whichever way each spells its path.
    func isSameFile(as other: URL) -> Bool {
        resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            == other.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
    }
}

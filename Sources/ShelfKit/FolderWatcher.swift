import Foundation
import os

/// Tells when a folder's own entries change (a file or folder added, removed or renamed at its
/// top level) for as long as it's kept. A change made while the app is suspended is reported when
/// it resumes, and a burst of them (a copy of many files) is reported once, a moment after the last.
///
/// Both apps watch their own folder with it, so what the Files app drops in (beside the app on an
/// iPad, or while it waits in the background) reaches the shelf without a relaunch.
@MainActor
public final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject
    private var settling: Task<Void, Never>?

    public init?(url: URL, settle: Duration = .seconds(1), onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            Logger.files.error("[watch] can't watch \(url.lastPathComponent, privacy: .public) errno=\(errno)")
            return nil
        }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                           eventMask: [.write, .rename, .delete, .link],
                                                           queue: .main)
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed(settle: settle, onChange: onChange) }
        }
        source.resume()
        Logger.files.info("[watch] watching \(url.lastPathComponent, privacy: .public)")
    }

    /// Stops watching; nothing more is reported.
    public func stop() {
        settling?.cancel()
        source.cancel()
    }

    private func changed(settle: Duration, onChange: @escaping @MainActor () -> Void) {
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
            Logger.files.debug("[watch] changed")
            onChange()
        }
    }
}

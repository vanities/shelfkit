import Foundation

/// A point-in-time check, never a download or a network read.
public enum OfflineReadiness: String, Sendable {
    case ready, needsDownload, unavailable, providerManaged

    public var label: String {
        switch self {
        case .ready: "Ready for offline"
        case .needsDownload: "Download needed"
        case .unavailable: "Files missing or incomplete"
        case .providerManaged: "Check availability in Files"
        }
    }
    public var symbol: String {
        switch self {
        case .ready: "checkmark.circle"
        case .needsDownload: "arrow.down.circle"
        case .unavailable: "exclamationmark.circle"
        case .providerManaged: "folder.badge.questionmark"
        }
    }

    public struct File: Sendable {
        public let url: URL
        public let expectedBytes: Int64
        public init(url: URL, expectedBytes: Int64 = 0) {
            self.url = url
            self.expectedBytes = expectedBytes
        }
    }

    /// Security-scoped roots must already be accessible. Call off the main actor for large books.
    public static func check(files: [File], managedCopy: Bool) -> Self {
        guard !files.isEmpty else { return .unavailable }
        var needsDownload = false
        var providerManaged = false
        for file in files {
            do {
                let values = try file.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey,
                    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .volumeIsLocalKey])
                if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current {
                    needsDownload = true
                    continue
                }
                guard values.isRegularFile == true, let size = values.fileSize, size > 0,
                      file.expectedBytes <= 0 || Int64(size) == file.expectedBytes,
                      FileManager.default.isReadableFile(atPath: file.url.path) else { return .unavailable }
                // Third-party providers can expose placeholders with ordinary file metadata.
                // Do not claim that their remote storage is a durable offline copy.
                if !managedCopy, values.isUbiquitousItem != true,
                   values.volumeIsLocal != true || file.url.path.contains("File Provider Storage")
                    || file.url.path.contains("FileProviderStorage") {
                    providerManaged = true
                }
            } catch { return .unavailable }
        }
        if needsDownload { return .needsDownload }
        return providerManaged ? .providerManaged : .ready
    }

    public static func checkImageFolder(_ url: URL, managedCopy: Bool, expectedBytes: Int64 = 0) -> Self {
        let fm = FileManager.default
        var failed = false
        guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                          options: [.skipsHiddenFiles], errorHandler: { _, _ in
            failed = true
            return false
        }) else { return .unavailable }
        let extensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff"]
        var files: [File] = []
        for case let file as URL in entries where extensions.contains(file.pathExtension.lowercased()) {
            files.append(File(url: file))
        }
        guard !failed else { return .unavailable }
        let result = check(files: files, managedCopy: managedCopy)
        guard result == .ready, expectedBytes > 0 else { return result }
        let bytes = files.reduce(Int64(0)) { total, file in
            total + Int64((try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return bytes >= expectedBytes ? .ready : .unavailable
    }
}

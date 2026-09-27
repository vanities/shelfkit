import Foundation

public enum NASRelocation {
    /// Directory listings only: never opens or downloads media during a relocation preview.
    public static func missing(files: [RelinkFile], list: @Sendable (String) async throws -> [NASEntry]) async throws -> [String] {
        var cache: [String: [NASEntry]] = [:], missing: [String] = []
        let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "bmp", "tif", "tiff"]
        for file in files {
            guard file.bytes > 0, !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else { missing.append(file.path); continue }
            let parent = file.imageFolder ? file.path : (file.path as NSString).deletingLastPathComponent
            if cache[parent] == nil { cache[parent] = try await list(parent) }
            let entries = cache[parent] ?? []
            if file.imageFolder {
                let pages = entries.filter { !$0.isDirectory && images.contains(($0.name as NSString).pathExtension.lowercased()) }
                if pages.isEmpty || pages.reduce(Int64(0), { $0 + $1.size }) != file.bytes { missing.append(file.path) }
            } else if !entries.contains(where: { !$0.isDirectory && $0.relativePath == file.path && $0.size == file.bytes }) {
                missing.append(file.path)
            }
        }
        return missing
    }
}

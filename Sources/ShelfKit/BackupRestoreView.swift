#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import os

public struct BackupRestoreView: View {
    let app: String
    let export: () async throws -> LibraryBackupDocument
    let preview: (LibraryBackupDocument) throws -> String
    let restore: (LibraryBackupDocument) async throws -> Void
    @State private var document: BackupFile?
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: LibraryBackupDocument?
    @State private var summary = ""
    @State private var busy = false
    @State private var message: String?
    public init(app: String, export: @escaping () async throws -> LibraryBackupDocument,
                preview: @escaping (LibraryBackupDocument) throws -> String,
                restore: @escaping (LibraryBackupDocument) async throws -> Void) {
        self.app = app; self.export = export; self.preview = preview; self.restore = restore
    }
    public var body: some View {
        Form {
            Section {
                Text("Save progress, notes, lists, corrections and chosen covers. Add your media sources before restoring on a new device. Audio, comics and NAS passwords are not included.")
                Button("Export backup…") {
                    Task { await perform {
                        let backup = try await export()
                        let data = try await Task.detached(priority: .utility) { try JSONEncoder().encode(backup) }.value
                        guard data.count <= 200_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        document = BackupFile(data: data); exporting = true
                    } }
                }
                Button("Choose backup to restore…") { importing = true }
            }.disabled(busy)
            if let pending {
                Section("Restore preview") {
                    Text(pending.date, style: .date)
                    Text(summary)
                    Text("Current values win on conflicts. Unmatched books are skipped. Media sources and passwords stay as configured.").font(.footnote)
                    Button("Restore missing state") {
                        Task { await perform { try await restore(pending); self.pending = nil; message = "Restore complete." } }
                    }.disabled(busy)
                    Button("Cancel") { self.pending = nil }.disabled(busy)
                }
            }
            if busy { ProgressView() }
            if let message { Text(message) }
        }
        .navigationTitle("Backup and restore")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "\(app)-backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task { await perform {
                    let backup = try await Task.detached(priority: .utility) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size > 0, size <= 200_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        return try JSONDecoder().decode(LibraryBackupDocument.self, from: Data(contentsOf: url))
                    }.value
                    try backup.validate(app: app)
                    summary = try preview(backup); pending = backup
                } }
            case .failure(let error): message = error.localizedDescription
            }
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        busy = true; message = nil
        defer { busy = false }
        do { try await action() } catch {
            Logger.store.error("[backup] \(app, privacy: .public): \(error.localizedDescription, privacy: .public)")
            message = error.localizedDescription
        }
    }
}
#endif

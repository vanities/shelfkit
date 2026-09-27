#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import os

public struct ReconnectSource: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let files: [RelinkFile]
    public init(id: UUID, name: String, files: [RelinkFile]) { self.id = id; self.name = name; self.files = files }
}

public struct ReconnectFolderView: View {
    let sources: [ReconnectSource]
    let busy: Bool
    let apply: (UUID, URL) throws -> Void
    public init(sources: [ReconnectSource], busy: Bool, apply: @escaping (UUID, URL) throws -> Void) {
        self.sources = sources; self.busy = busy; self.apply = apply
    }
    @State private var sourceID: UUID?
    @State private var picking = false
    @State private var checking = false
    @State private var candidate: URL?
    @State private var matches = 0
    @State private var expected = 0
    @State private var missing: [String] = []
    @State private var error: String?
    @State private var message: String?
    private var source: ReconnectSource? { sources.first { $0.id == sourceID } }
    public var body: some View {
        Form {
            Section {
                Text("Choose the source, then its new folder. The preview checks existing relative filenames and sizes. Matching preserves your place, notes and corrections. It does not compare file contents.")
                Picker("Source", selection: $sourceID) {
                    Text("Choose a source").tag(Optional<UUID>.none)
                    ForEach(sources) { Text($0.name).tag(Optional($0.id)) }
                }.onChange(of: sourceID) { candidate = nil; matches = 0 }
                Button("Choose new folder…") { picking = true }.disabled(source == nil || checking)
            }
            if checking { ProgressView("Checking files…") }
            if let candidate {
                Section("Preview") {
                    Text(candidate.lastPathComponent)
                    Text("\(matches) of \(expected) known files match")
                    ForEach(missing.prefix(40), id: \.self) { Text("Missing or different: " + $0).font(.caption).foregroundStyle(.secondary) }
                    Text("The source keeps its identity. Unmatched files must be resolved before reconnecting.").font(.footnote)
                    Button("Reconnect") { Task { await reconnect(candidate) } }
                        .disabled(matches != expected || expected == 0 || checking || busy)
                }
            }
            if let message { Text(message) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Reconnect a folder")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await preview(url) }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
    private func preview(_ url: URL) async {
        guard let source else { return }
        checking = true; error = nil; message = nil; candidate = nil
        let files = source.files
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() }; checking = false }
        let unmatched = await Task.detached(priority: .utility) { files.filter { !$0.matches(root: url) }.map(\.path) }.value
        guard sourceID == source.id else { return }
        expected = files.count; matches = files.count - unmatched.count; missing = unmatched; candidate = url
    }
    private func reconnect(_ url: URL) async {
        guard let source else { return }
        await preview(url)
        guard matches == expected, expected > 0, sourceID == source.id, !busy else { return }
        do { try apply(source.id, url); candidate = nil; error = nil; message = "Folder reconnected." } catch {
            Logger.files.error("[reconnect] \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
    }
}
#endif

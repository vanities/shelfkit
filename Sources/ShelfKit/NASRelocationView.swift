#if os(iOS)
import SwiftUI
import os

public struct NASRelocationView: View {
    let files: [RelinkFile]
    let busy: Bool
    let makeClient: (NASServer) throws -> NASClient
    let apply: (NASServer) throws -> Void
    @State private var candidate: NASServer
    @State private var checked: NASServer?
    @State private var checking = false
    @State private var missing: [String] = []
    @State private var message: String?
    public init(server: NASServer, files: [RelinkFile], busy: Bool,
                makeClient: @escaping (NASServer) throws -> NASClient, apply: @escaping (NASServer) throws -> Void) {
        _candidate = State(initialValue: server)
        self.files = files; self.busy = busy; self.makeClient = makeClient; self.apply = apply
    }
    public var body: some View {
        Form {
            Section("New NAS location") {
                TextField("Host", text: $candidate.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Share", text: $candidate.share).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Folder inside share", text: $candidate.path).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Uses this NAS's saved login and port. Checks names and sizes without opening your media.").font(.footnote).foregroundStyle(.secondary)
                Button(checking ? "Checking…" : "Preview matches") { Task { await preview() } }
                    .disabled(checking || busy || files.isEmpty || candidate.host.isEmpty || candidate.share.isEmpty)
            }
            if checked == candidate {
                Section("Preview") {
                    Text("\(files.count - missing.count) of \(files.count) known files match")
                    ForEach(missing.prefix(40), id: \.self) { Text("Missing or different: " + $0).font(.caption) }
                    Button("Reconnect NAS") {
                        Task {
                            await preview()
                            guard checked == candidate, missing.isEmpty, !files.isEmpty, !busy else { return }
                            do { try apply(candidate); checked = nil; message = "NAS reconnected." } catch { report(error) }
                        }
                    }.disabled(checking || busy || !missing.isEmpty || files.isEmpty)
                }
            }
            if let message { Text(message) }
        }
        .navigationTitle("Reconnect NAS")
        .onChange(of: candidate) { checked = nil; message = nil }
    }
    private func preview() async {
        checking = true; message = nil; checked = nil
        defer { checking = false }
        let snapshot = candidate
        do {
            let client = try makeClient(snapshot)
            do {
                let result = try await NASRelocation.missing(files: files) { try await client.list($0) }
                await client.disconnect()
                guard candidate == snapshot else { return }
                missing = result; checked = snapshot
            } catch { await client.disconnect(); throw error }
        } catch { report(error) }
    }
    private func report(_ error: any Error) {
        Logger.nas.error("[reconnect] preview/apply failed: \(error.localizedDescription, privacy: .public)")
        message = error.localizedDescription
    }
}
#endif

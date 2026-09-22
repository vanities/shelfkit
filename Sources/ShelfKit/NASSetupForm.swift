#if os(iOS)
import SwiftUI
import os

/// Adding an SMB share, the same form in both apps. The share is only added once it answers —
/// connected, and its folder listed — so a typo never becomes a source that can't scan. The
/// password goes to the app (and from there the Keychain), never into a library file.
public struct NASSetupForm: View {
    /// What the app calls a likely folder ("comics", "audiobooks").
    let folderPlaceholder: String
    let footer: String
    /// Saves the server and its password, and makes it a source. Throwing keeps the form open
    /// with the error shown.
    let add: @MainActor (NASServer, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    /// Empty means SMB's standard 445; a NAS behind a port forward or a Docker share differs.
    @State private var port = ""
    @State private var share = ""
    @State private var path = ""
    @State private var username = ""
    @State private var password = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var adding = false
    @State private var addError: String?

    public init(folderPlaceholder: String, footer: String, add: @escaping @MainActor (NASServer, String) async throws -> Void) {
        self.folderPlaceholder = folderPlaceholder
        self.footer = footer
        self.add = add
    }

    private var portNumber: Int? { NASServer.port(from: port) }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !share.trimmingCharacters(in: .whitespaces).isEmpty
            && portNumber != nil
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") { TextField("My NAS", text: $name).multilineTextAlignment(.trailing) }
                    LabeledContent("Host") {
                        TextField("nas.local", text: $host)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Port") {
                        TextField("445", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Server")
                } footer: {
                    if portNumber == nil {
                        Text("A port is a number from 1 to 65535 — leave it empty for SMB's usual 445.")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    LabeledContent("Share") {
                        TextField("media", text: $share)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Folder") {
                        TextField(folderPlaceholder, text: $path)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text(footer)
                }
                Section("Login") {
                    LabeledContent("Username") {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Password") {
                        SecureField("", text: $password).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if testing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(!canSave || testing || adding)
                    if let testResult {
                        Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(testOK ? .green : .red)
                    }
                }
                if let addError {
                    Section {
                        Label(addError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            // A result is about what was tested; once any field changes it no longer says anything.
            .onChange(of: [host, port, share, path, username, password]) { testResult = nil }
            .navigationTitle("Add NAS Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(adding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if adding {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(adding)
    }

    private func makeServer() -> NASServer {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        return NASServer(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? trimmedHost,
            host: trimmedHost,
            port: portNumber ?? 445,
            share: share.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
            path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).replacingOccurrences(of: "\\", with: "/"),
            username: username.trimmingCharacters(in: .whitespaces),
            addedAt: .now
        )
    }

    /// Connects and lists the folder: how many items it holds, or what went wrong.
    private static func check(_ server: NASServer, password: String) async throws -> Int {
        let client = try NASClient(server: server, password: password)
        defer { Task { await client.disconnect() } }
        return try await client.list("").count
    }

    private func test() async {
        testing = true
        testResult = nil
        defer { testing = false }
        let server = makeServer()
        do {
            let count = try await Self.check(server, password: password)
            testOK = true
            testResult = "Connected — \(count) items in \(server.path.isEmpty ? server.share : server.path)."
        } catch {
            testOK = false
            testResult = error.localizedDescription
        }
    }

    private func save() async {
        adding = true
        addError = nil
        defer { adding = false }
        let server = makeServer()
        Logger.nas.info("[nas] adding \(server.displayLocation, privacy: .public)")
        do {
            _ = try await Self.check(server, password: password)
            try await add(server, password)
            dismiss()
        } catch {
            Logger.nas.error("[nas] add failed for \(server.displayLocation, privacy: .public): \(error.localizedDescription, privacy: .public)")
            addError = error.localizedDescription
        }
    }
}
#endif

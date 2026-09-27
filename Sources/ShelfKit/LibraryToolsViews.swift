#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

public struct TripPreparationView: View {
    let items: [LibraryToolItem]
    let groups: [String: Set<String>]
    let check: (String) async -> OfflineReadiness
    let download: (Set<String>) async -> String
    @State private var selected: Set<String>
    @State private var statuses: [String: OfflineReadiness] = [:]
    @State private var checking = false
    @State private var query = ""
    @State private var message: String?
    public init(items: [LibraryToolItem], groups: [String: Set<String>], initial: Set<String> = [],
                check: @escaping (String) async -> OfflineReadiness, download: @escaping (Set<String>) async -> String) {
        self.items = items; self.groups = groups; self.check = check; self.download = download
        _selected = State(initialValue: initial)
    }
    private var picked: [LibraryToolItem] { items.filter { selected.contains($0.id) } }
    public var body: some View {
        List {
            Section {
                Menu("Add from…", systemImage: "text.badge.plus") {
                    ForEach(groups.keys.sorted(), id: \.self) { name in
                        Button(name) { selected.formUnion(groups[name] ?? []) }
                    }
                }
                Text("\(picked.count) \(picked.count == 1 ? "book" : "books") · \(ByteCountFormatter.string(fromByteCount: picked.reduce(0) { $0 + $1.bytes }, countStyle: .file)) total")
                Button("Download selected", systemImage: "arrow.down.circle") {
                    Task { checking = true; message = await download(selected); statuses = [:]; checking = false }
                }.disabled(picked.isEmpty || checking)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Button(checking ? "Checking…" : "Verify selected files", systemImage: "checkmark.icloud") {
                    Task {
                        checking = true
                        for item in picked { statuses[item.id] = await check(item.id) }
                        checking = false
                    }
                }.disabled(checking || picked.isEmpty)
                Text("Verify after transfers finish. Provider-managed files may still need Keep Downloaded in Files.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Books") {
                ForEach(items.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { item in
                    Button {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(item.title).foregroundStyle(.primary)
                                Text(statuses[item.id]?.label ?? item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(minHeight: 44)
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Prepare for a trip")
    }
}

public struct SmartShelvesView: View {
    let items: [LibraryToolItem]
    @Binding var state: LibraryToolsState
    let open: (String) -> Void
    @State private var name = ""
    @State private var rule = SmartShelfRule.downloadedUnfinished
    public init(items: [LibraryToolItem], state: Binding<LibraryToolsState>, open: @escaping (String) -> Void) {
        self.items = items; _state = state; self.open = open
    }
    public var body: some View {
        List {
            Section("Create a smart list") {
                TextField("Name", text: $name)
                Picker("Include", selection: $rule) {
                    ForEach(SmartShelfRule.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button("Save smart list") {
                    state.smartShelves.append(SmartShelf(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rule.title : name, rule: rule))
                    name = ""
                }
            }
            Section("Smart lists") {
                ForEach(state.smartShelves) { shelf in
                    NavigationLink {
                        List(items.filter { shelf.rule.matches($0) }) { item in
                            Button(item.title) { open(item.id) }.frame(minHeight: 44)
                        }.navigationTitle(shelf.name)
                    } label: { LabeledContent(shelf.name, value: "\(items.filter { shelf.rule.matches($0) }.count)") }
                }.onDelete { state.smartShelves.remove(atOffsets: $0) }
            }
        }.navigationTitle("Smart lists")
    }
}

public struct NewArrivalsView: View {
    let items: [LibraryToolItem]
    @Binding var state: LibraryToolsState
    let download: (Set<String>) async -> String
    let open: (String) -> Void
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var downloading = false
    public init(items: [LibraryToolItem], state: Binding<LibraryToolsState>, download: @escaping (Set<String>) async -> String, open: @escaping (String) -> Void) {
        self.items = items; _state = state; self.download = download; self.open = open
    }
    private var arrivals: [LibraryToolItem] { items.filter { state.arrivals[$0.id] != nil }.sorted { state.arrivals[$0.id]! > state.arrivals[$1.id]! } }
    public var body: some View {
        List {
            Section {
                Text("New books found after a source's first scan. Downloading an existing book doesn't count as an arrival.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Download selected (\(selected.count))") {
                    Task { downloading = true; message = await download(selected); downloading = false }
                }.disabled(selected.isEmpty || downloading)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Button("Mark all seen") { state.dismissArrivals(); selected = [] }.disabled(arrivals.isEmpty)
            }
            ForEach(arrivals) { item in
                HStack {
                    Button {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    } label: { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless)
                    Button { open(item.id) } label: {
                        VStack(alignment: .leading) { Text(item.title); Text(item.detail).font(.caption).foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.borderless)
                }
            }
        }.navigationTitle("New arrivals")
    }
}

public struct BackupFile: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data
    public init(data: Data) { self.data = data }
    public init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif

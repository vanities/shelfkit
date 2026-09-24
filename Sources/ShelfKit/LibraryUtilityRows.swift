#if canImport(SwiftUI)
import SwiftUI

public struct OfflineReadinessRow: View {
    let title: String
    let status: OfflineReadiness?
    public init(title: String, status: OfflineReadiness?) {
        self.title = title
        self.status = status
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.body)
            if let status {
                Label(status.label, systemImage: status.symbol)
                    .font(.caption).foregroundStyle(status == .ready ? .green : .secondary)
            } else {
                HStack { ProgressView().controlSize(.mini); Text("Checking local files…").font(.caption) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

public struct BookmarkSearchRow: View {
    let title: String
    let note: String
    let location: String
    public init(title: String, note: String, location: String) {
        self.title = title
        self.note = note
        self.location = location
    }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.isEmpty ? location : note).lineLimit(2)
                Text("\(title) · \(location)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}
#endif

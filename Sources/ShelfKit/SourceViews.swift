import SwiftUI

// The rows of a Sources screen, drawn the same in both apps: a source, a transfer, a tip.
// Each app works out the words; these only lay them out.

/// A folder or NAS share in the Sources list: where it is, and how its last scan went.
public struct SourceRowView: View {
    let systemImage: String
    let name: String
    /// A NAS share's address; nil for a folder on this device.
    let location: String?
    /// "11 books · 24 files · scanned 1 minute ago", "Reading tags 3 of 12", or what went wrong.
    let status: String
    let isError: Bool
    /// Something worth knowing that isn't an error ("2 .cbr files can't be opened").
    let warning: String?
    let isScanning: Bool

    public init(systemImage: String, name: String, location: String? = nil, status: String, isError: Bool = false,
                warning: String? = nil, isScanning: Bool = false) {
        self.systemImage = systemImage
        self.name = name
        self.location = location
        self.status = status
        self.isError = isError
        self.warning = warning
        self.isScanning = isScanning
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let location {
                    Text(location)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isError ? Color.red : Color.secondary)
                    .lineLimit(2)
                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if isScanning {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "11 books · 24 files · scanned 1 minute ago": what a finished scan found, and when.
    public static func scanSummary(items: Int, noun: String, files: Int, at date: Date?) -> String {
        guard let date else { return "Not scanned yet" }
        let when = date.formatted(.relative(presentation: .named))
        if files == 0 { return "Empty · checked \(when)" }
        return "\(items) \(noun)\(items == 1 ? "" : "s") · \(files) file\(files == 1 ? "" : "s") · scanned \(when)"
    }
}

/// One download, upload or move in the Transfers list. Cancel it with its button or a swipe;
/// swipe to retry one that failed.
public struct TransferRowView: View {
    public enum Kind: Sendable { case download, upload, move }
    public enum Phase: Sendable { case queued, running, done, failed, cancelled }

    let kind: Kind
    let title: String
    let phase: Phase
    let fraction: Double
    let doneBytes: Int64
    let totalBytes: Int64
    let error: String?
    let cancel: () -> Void
    let retry: () -> Void

    public init(kind: Kind, title: String, phase: Phase, fraction: Double, doneBytes: Int64, totalBytes: Int64,
                error: String?, cancel: @escaping () -> Void, retry: @escaping () -> Void) {
        self.kind = kind
        self.title = title
        self.phase = phase
        self.fraction = fraction
        self.doneBytes = doneBytes
        self.totalBytes = totalBytes
        self.error = error
        self.cancel = cancel
        self.retry = retry
    }

    private var isActive: Bool { phase == .queued || phase == .running }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: kind == .download ? "arrow.down.circle" : kind == .upload ? "arrow.up.circle" : "arrow.right.circle")
                    .foregroundStyle(phase == .failed ? Color.red : Color.accentColor)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                switch phase {
                case .queued: Text("Waiting").font(.caption).foregroundStyle(.secondary)
                case .running: Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                case .cancelled: Text("Cancelled").font(.caption).foregroundStyle(.secondary)
                }
                if isActive {
                    Button("Cancel", systemImage: "xmark.circle.fill", action: cancel)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            if isActive {
                ProgressView(value: fraction)
                Text("\(doneBytes.formatted(.byteCount(style: .file))) of \(totalBytes.formatted(.byteCount(style: .file)))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            if isActive {
                Button("Cancel", role: .destructive, action: cancel)
            } else if phase == .failed {
                Button("Retry", action: retry).tint(.blue)
            }
        }
    }
}

/// A line of help at the foot of the Sources list.
public struct TipRowView: View {
    let systemImage: String
    let title: String
    let detail: String

    public init(systemImage: String, title: String, detail: String) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

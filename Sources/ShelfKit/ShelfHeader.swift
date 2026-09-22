import SwiftUI

/// The top of a shelf's page (a series in Mango; an author, a series or a folder in Earmark):
/// its cover, its name, what's in it, and one button for the obvious next thing, continue or
/// start. Drawn the same in both apps; each app supplies the cover and the words.
public struct ShelfHeader<Cover: View>: View {
    /// The one button: "Continue Vol. 3", "Resume Heaven's River".
    public struct Primary {
        let title: String
        let systemImage: String
        let action: @MainActor () -> Void

        public init(_ title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.action = action
        }
    }

    /// Wide enough to read the cover, narrow enough to leave the words a column.
    public static var coverWidth: CGFloat { 110 }

    let title: String
    let subtitle: String
    let detail: String?
    let primary: Primary?
    let cover: Cover

    public init(title: String, subtitle: String, detail: String? = nil, primary: Primary? = nil,
                @ViewBuilder cover: () -> Cover) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.primary = primary
        self.cover = cover()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            cover
                .frame(width: Self.coverWidth)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if let primary {
                    Button(action: primary.action) {
                        // Title and icon wherever it sits: a List row (Mango) would otherwise drop the icon
                        // that a ScrollView (Earmark) shows.
                        Label(primary.title, systemImage: primary.systemImage)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

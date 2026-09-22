import SwiftUI

// What a book or comic's copies look like on a source's page, drawn the same in both apps:
// where it is (`CopyPlace`), a swatch or tile for it, a bar for a whole source, and a ring for
// a group with the menu of what can move.

/// Where one book or comic stands between this device and a NAS.
public enum CopyPlace: Equatable, Sendable {
    /// Only on the NAS.
    case remote
    /// Coming down or going up, this far along (0…1).
    case transferring(Double)
    /// On this device and on the NAS.
    case both
    /// Only on this device.
    case deviceOnly
}

/// A place's look: filled when it's in both places, outlined when it's only on the NAS, grey
/// when it's only on this device, filling up while it moves. Tiles and legends both use it.
public struct PlaceBackground: View {
    public static let radius: CGFloat = 7
    let place: CopyPlace

    public init(_ place: CopyPlace) {
        self.place = place
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        switch place {
        case .remote:
            shape.strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
        case .both:
            shape.fill(Color.accentColor.opacity(0.2))
        case .deviceOnly:
            shape.fill(Color.secondary.opacity(0.15))
        case .transferring(let fraction):
            shape.strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                .background(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.2))
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .clipShape(shape)
        }
    }
}

/// A legend entry: a small swatch of a place and what it means.
public struct PlaceLegend: View {
    let place: CopyPlace
    let text: String

    public init(_ place: CopyPlace, _ text: String) {
        self.place = place
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 5) {
            PlaceBackground(place).frame(width: 14, height: 10)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// How much of a source is in both places, as a thin bar.
public struct StorageBar: View {
    let fraction: Double

    public init(fraction: Double) {
        self.fraction = fraction
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(fraction > 0 ? 6 : 0, proxy.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent")
    }
}

/// A group's share of both places, App Store style: an arrow while there's more to move, a stop
/// square while it's moving, a check once it's all in both places.
public struct TransferRing: View {
    let fraction: Double
    /// Up for this device's copies going to the NAS, down for the NAS's coming here.
    let upward: Bool
    let isMoving: Bool
    let isComplete: Bool

    public init(fraction: Double, upward: Bool, isMoving: Bool, isComplete: Bool) {
        self.fraction = fraction
        self.upward = upward
        self.isMoving = isMoving
        self.isComplete = isComplete
    }

    public var body: some View {
        Group {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: isMoving ? "stop.fill" : upward ? "arrow.up" : "arrow.down")
                        .font(.system(size: isMoving ? 8 : 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 22, height: 22)
            }
        }
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}

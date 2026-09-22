import SwiftUI

// The pieces of a Stats screen, drawn the same in both apps: a titled card, a headline tile,
// and the yearly goal as a ring.

/// A titled card on the Stats screen.
public struct StatCard<Content: View>: View {
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
    }
}

/// One headline number at the top of Stats: an icon, the value, what it counts.
public struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    public init(_ value: String, _ label: String, systemImage: String, tint: Color) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// The yearly goal as a ring: finished this year against what you're aiming for.
public struct GoalRing: View {
    let done: Int
    let goal: Int
    /// What's counted, for VoiceOver: "volumes", "books".
    let noun: String

    public init(done: Int, goal: Int, noun: String) {
        self.done = done
        self.goal = goal
        self.noun = noun
    }

    private var fraction: Double { goal > 0 ? min(1, Double(done) / Double(goal)) : 0 }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.orange.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.orange.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(done)").font(.title2.weight(.bold)).monospacedDigit()
                Text("of \(goal)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .animation(.easeOut(duration: 0.6), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(goal) \(noun) this year")
    }

    /// "3 ahead of pace.", from the share of the year gone.
    public static func pace(done: Int, goal: Int, on date: Date = .now, calendar: Calendar = .current) -> String {
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let days = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
        let delta = Double(done) - Double(goal) * day / days
        if abs(delta) < 1 { return "Right on pace." }
        return delta > 0 ? "\(Int(delta.rounded())) ahead of pace." : "\(Int((-delta).rounded())) behind pace."
    }
}

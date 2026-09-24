#if canImport(SwiftUI)
import SwiftUI

/// Kept compact on Stats; records are disclosed only when requested.
public struct ActivityInsightsView: View {
    private let insights: ActivityInsights
    private let noun: String
    @State private var records = false

    public init(insights: ActivityInsights, noun: String) {
        self.insights = insights
        self.noun = noun
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.headline)
            HStack {
                Label(Durations.short(insights.weekSeconds), systemImage: "clock")
                Spacer()
                Text("\(insights.weekFinished) \(noun) finished")
            }
            .font(.subheadline)
            if let favorite = insights.weekFavorite {
                Text("Most time with: \(favorite)").font(.subheadline).foregroundStyle(.secondary)
            }
            DisclosureGroup("Personal records", isExpanded: $records) {
                VStack(spacing: 10) {
                    LabeledContent("Longest session", value: Durations.short(insights.longestSession))
                    if let month = insights.busiestMonth {
                        LabeledContent("Busiest month · \(month)", value: Durations.short(insights.busiestMonthSeconds))
                    }
                    if let day = insights.favoriteWeekday { LabeledContent("Favorite day", value: day) }
                    Text("Based on retained activity. Session and book details are from this device; day totals include iCloud.")
                        .font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline).padding(.top, 8)
            }
        }
    }
}

public struct ActivitySessionRow: View {
    private let title: String
    private let date: Date
    private let seconds: Double
    private let detail: String?

    public init(title: String, date: Date, seconds: Double, detail: String? = nil) {
        self.title = title; self.date = date; self.seconds = seconds; self.detail = detail
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary).lineLimit(2)
                Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(Durations.short(seconds)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }
}
#endif

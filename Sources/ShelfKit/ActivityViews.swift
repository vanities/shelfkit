import Charts
import SwiftUI

// How Stats draws time spent with books, the same in both apps: the time card's numbers, a
// calendar of the last few months, when in the day, and which books took the most time.

/// The time card: this week, this month and all time; the longest streak, an average session,
/// and pages a minute where there are pages.
public struct ActivityTimeView: View {
    let stats: ActivityStats
    /// "Average sitting" for a reader, "Average session" for a listener.
    let sessionLabel: String

    public init(stats: ActivityStats, sessionLabel: String) {
        self.stats = stats
        self.sessionLabel = sessionLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                stat(Durations.short(stats.thisWeekSeconds), "This week")
                stat(Durations.short(stats.thisMonthSeconds), "This month")
                stat(Durations.short(stats.totalSeconds), "All time")
            }
            HStack(spacing: 12) {
                stat("\(stats.longestStreak)d", "Longest streak")
                if let average = stats.averageSessionMinutes {
                    stat("\(Int(average.rounded()))m", sessionLabel)
                }
                if let pace = stats.pagesPerMinute {
                    stat(pace.formatted(.number.precision(.fractionLength(1))), "Pages / minute")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A GitHub-style calendar of the last few months: one square per day, darker for more time.
public struct ActivityHeatmap: View {
    let days: [ActivityStats.Day]

    public init(days: [ActivityStats.Day]) {
        self.days = days
    }

    private var weeks: [[ActivityStats.Day]] {
        stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private var busiest: Double { max(1, days.map(\.seconds).max() ?? 1) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(color(for: day))
                                .aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(Durations.short(day.seconds))")
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(shade(level)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func color(for day: ActivityStats.Day) -> Color {
        day.seconds <= 0 ? Color.secondary.opacity(0.12) : shade(min(1, day.seconds / busiest))
    }

    private func shade(_ level: Double) -> Color {
        level <= 0 ? Color.secondary.opacity(0.12) : Color.orange.opacity(0.25 + 0.75 * level)
    }
}

/// When in the day the time goes: morning, afternoon, evening, night.
public struct TimeOfDayChart: View {
    let buckets: [ActivityStats.Bucket]

    public init(buckets: [ActivityStats.Bucket]) {
        self.buckets = buckets
    }

    public var body: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("When", bucket.name), y: .value("Minutes", bucket.seconds / 60))
                .foregroundStyle(Color.orange.gradient)
                .cornerRadius(4)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 140)
    }
}

/// The habits card: when in the day, and the books (or series) that took the most time.
public struct ActivityHabitsView: View {
    let stats: ActivityStats

    public init(stats: ActivityStats) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimeOfDayChart(buckets: stats.timeOfDay)
            if !stats.topByTime.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Most time spent in").font(.caption).foregroundStyle(.secondary)
                ForEach(stats.topByTime) { bucket in
                    HStack {
                        Text(bucket.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(Durations.short(bucket.seconds))
                            .font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

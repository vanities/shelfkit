import Foundation

// Time spent with a book — reading a comic, listening to an audiobook — as both apps count it.
// Each app records its own sessions; what they add up to, and how devices share it, lives here.

/// A stretch of time with one book, as an app recorded it.
public protocol ActivitySession {
    var startedAt: Date { get }
    /// Time that counted: pages turning, audio playing — not a book left open.
    var activeSeconds: Double { get }
    /// What "most time spent in" groups by (a series, a book), and its name.
    var activityGroupKey: String { get }
    var activityGroupName: String { get }
    /// Pages moved forward; 0 where there are no pages (a novel, an audiobook).
    var activityPages: Int { get }
}

/// One day's activity, rolled up — what syncs between devices, rather than every session.
/// Its keys are Mango's since before it was shared; they must not change.
public struct DayActivity: Codable, Hashable, Sendable {
    public var seconds: Double
    public var pages: Int
    public var sessions: Int

    public init(seconds: Double = 0, pages: Int = 0, sessions: Int = 0) {
        self.seconds = seconds
        self.pages = pages
        self.sessions = sessions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        pages = try c.decodeIfPresent(Int.self, forKey: .pages) ?? 0
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
    }
}

public enum DayKey {
    /// "2026-09-21" in the reader's own calendar — the key days are grouped and synced by.
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Per-day totals from a list of sessions.
    public static func rollUp<Session: ActivitySession>(_ sessions: [Session], calendar: Calendar = .current) -> [String: DayActivity] {
        var days: [String: DayActivity] = [:]
        for session in sessions {
            let key = string(for: session.startedAt, calendar: calendar)
            var day = days[key] ?? DayActivity()
            day.seconds += session.activeSeconds
            day.pages += session.activityPages
            day.sessions += 1
            days[key] = day
        }
        return days
    }
}

/// Day totals shared between a person's devices through their own iCloud: one slot per device,
/// each written only by that device, so adding them up never counts a day twice.
public enum DeviceActivity {
    /// This device's days plus every other device's slot — never this device's old slot, which
    /// `own` replaces.
    public static func combined(own: [String: DayActivity], cloud: [String: [String: DayActivity]],
                                deviceID: String) -> [String: DayActivity] {
        var days = own
        for (device, deviceDays) in cloud where device != deviceID {
            for (key, value) in deviceDays {
                var day = days[key] ?? DayActivity()
                day.seconds += value.seconds
                day.pages += value.pages
                day.sessions += value.sessions
                days[key] = day
            }
        }
        return days
    }

    /// The cloud value with this device's slot replaced by `own`, keeping only days since `since`.
    public static func updated(cloud: [String: [String: DayActivity]], own: [String: DayActivity], deviceID: String,
                               since: Date, calendar: Calendar = .current) -> [String: [String: DayActivity]] {
        var all = cloud
        let cutoff = DayKey.string(for: since, calendar: calendar)
        all[deviceID] = own.filter { $0.key >= cutoff }
        return all
    }
}

/// Time, streaks, pace and habits — what Stats can say about *how* you read or listen rather
/// than what you finished. Built from day totals (which include your other devices) and this
/// device's own sessions (for the per-book and time-of-day detail).
public struct ActivityStats: Equatable, Sendable {
    public struct Day: Equatable, Identifiable, Sendable {
        public var id: Date { date }
        public var date: Date
        public var seconds: Double
        public var pages: Int
    }

    public struct Bucket: Equatable, Identifiable, Sendable {
        public var id: String { name }
        public var name: String
        public var seconds: Double
    }

    public var totalSeconds: Double = 0
    public var thisWeekSeconds: Double = 0
    public var thisMonthSeconds: Double = 0
    public var currentStreak = 0
    public var longestStreak = 0
    public var daysActive = 0
    /// Every day of the last `heatmapWeeks` weeks, oldest first, week-aligned, zero-filled.
    public var heatmap: [Day] = []
    /// Pages a minute, from sessions that turned pages (comics); nil where none did.
    public var pagesPerMinute: Double?
    public var averageSessionMinutes: Double?
    public var timeOfDay: [Bucket] = []
    public var topByTime: [Bucket] = []

    public init() {}

    public var hasActivity: Bool { totalSeconds > 0 }

    public static let heatmapWeeks = 17

    public static func build<Session: ActivitySession>(days: [String: DayActivity], sessions: [Session], now: Date = .now,
                                                       calendar: Calendar = .current) -> ActivityStats {
        var stats = ActivityStats()
        let dated: [(Date, DayActivity)] = days.compactMap { key, value in
            DayKey.date(from: key, calendar: calendar).map { ($0, value) }
        }
        let today = calendar.startOfDay(for: now)

        stats.totalSeconds = dated.reduce(0) { $0 + $1.1.seconds }
        stats.daysActive = dated.count { $0.1.seconds > 0 }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            stats.thisWeekSeconds = dated.filter { week.contains($0.0) }.reduce(0) { $0 + $1.1.seconds }
        }
        if let month = calendar.dateInterval(of: .month, for: now) {
            stats.thisMonthSeconds = dated.filter { month.contains($0.0) }.reduce(0) { $0 + $1.1.seconds }
        }

        (stats.currentStreak, stats.longestStreak) = streaks(
            Set(dated.filter { $0.1.seconds > 0 }.map { calendar.startOfDay(for: $0.0) }),
            today: today, calendar: calendar)

        stats.heatmap = heatmap(dated, today: today, calendar: calendar)

        // Pace only from sessions that genuinely turned pages; a novel or an audiobook has none.
        let paced = sessions.filter { $0.activityPages > 0 && $0.activeSeconds > 0 }
        let pacedMinutes = paced.reduce(0) { $0 + $1.activeSeconds } / 60
        if pacedMinutes > 0 {
            stats.pagesPerMinute = Double(paced.reduce(0) { $0 + $1.activityPages }) / pacedMinutes
        }
        if !sessions.isEmpty {
            stats.averageSessionMinutes = sessions.reduce(0) { $0 + $1.activeSeconds } / Double(sessions.count) / 60
        }

        stats.timeOfDay = timeOfDay(sessions, calendar: calendar)

        var byGroup: [String: (name: String, seconds: Double)] = [:]
        for session in sessions {
            var entry = byGroup[session.activityGroupKey] ?? (session.activityGroupName, 0)
            entry.seconds += session.activeSeconds
            byGroup[session.activityGroupKey] = entry
        }
        stats.topByTime = byGroup.values
            .map { Bucket(name: $0.name, seconds: $0.seconds) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(5)
            .map { $0 }
        return stats
    }

    /// The current streak counts today *or* yesterday as its end, so it doesn't read as broken
    /// first thing in the morning before you've picked a book up.
    public static func streaks(_ activeDays: Set<Date>, today: Date, calendar: Calendar) -> (current: Int, longest: Int) {
        guard !activeDays.isEmpty else { return (0, 0) }
        var longest = 0
        var run = 0
        var previous: Date?
        for day in activeDays.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        var current = 0
        var cursor = activeDays.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)
        while let day = cursor, activeDays.contains(day) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        return (current, longest)
    }

    private static func heatmap(_ dated: [(Date, DayActivity)], today: Date, calendar: Calendar) -> [Day] {
        var byDay: [Date: DayActivity] = [:]
        for (date, value) in dated { byDay[calendar.startOfDay(for: date)] = value }
        // Start on the first day of the week, heatmapWeeks back, so columns line up as weeks.
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -(heatmapWeeks - 1), to: thisWeekStart)
        else { return [] }
        var days: [Day] = []
        var cursor = start
        while cursor <= today {
            let value = byDay[cursor]
            days.append(Day(date: cursor, seconds: value?.seconds ?? 0, pages: value?.pages ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private static func timeOfDay<Session: ActivitySession>(_ sessions: [Session], calendar: Calendar) -> [Bucket] {
        var totals: [String: Double] = ["Morning": 0, "Afternoon": 0, "Evening": 0, "Night": 0]
        for session in sessions {
            let hour = calendar.component(.hour, from: session.startedAt)
            let name = switch hour {
            case 5..<12: "Morning"
            case 12..<17: "Afternoon"
            case 17..<22: "Evening"
            default: "Night"
            }
            totals[name, default: 0] += session.activeSeconds
        }
        return ["Morning", "Afternoon", "Evening", "Night"].map { Bucket(name: $0, seconds: totals[$0] ?? 0) }
    }
}

public enum Durations {
    /// "3h 20m", "45m", "<1m".
    public static func short(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return seconds > 0 ? "<1m" : "0m" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}

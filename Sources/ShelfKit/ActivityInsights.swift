import Foundation

/// A recap uses synced day totals for time, and device-local sessions for book detail.
public struct ActivityInsights: Sendable {
    public var weekSeconds: Double
    public var weekFinished: Int
    public var weekFavorite: String?
    public var longestSession: Double
    public var busiestMonth: String?
    public var busiestMonthSeconds: Double
    public var favoriteWeekday: String?
    public var dailyAverage: Double

    public init<S: ActivitySession>(days: [String: DayActivity], sessions: [S], finishes: [Date],
                                    now: Date = .now, calendar: Calendar = .current) {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let recent = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: now))!
        var months: [String: Double] = [:]
        var weekdays: [Int: Double] = [:]
        var recentSeconds = 0.0
        weekSeconds = 0
        for (key, value) in days {
            guard let date = DayKey.date(from: key, calendar: calendar), date <= now,
                  value.seconds.isFinite, value.seconds > 0 else { continue }
            if date >= week.start { weekSeconds += value.seconds }
            if date >= recent { recentSeconds += value.seconds }
            months[String(key.prefix(7)), default: 0] += value.seconds
            weekdays[calendar.component(.weekday, from: date), default: 0] += value.seconds
        }
        weekFinished = finishes.filter { $0 >= week.start && $0 <= now }.count
        let valid = sessions.filter { $0.startedAt <= now && $0.activeSeconds.isFinite && $0.activeSeconds > 0 }
        longestSession = valid.map(\.activeSeconds).max() ?? 0
        var favorites: [String: (String, Double)] = [:]
        for session in valid where session.startedAt >= week.start {
            let previous = favorites[session.activityGroupKey]?.1 ?? 0
            favorites[session.activityGroupKey] = (session.activityGroupName, previous + session.activeSeconds)
        }
        weekFavorite = favorites.sorted { $0.value.1 == $1.value.1 ? $0.key < $1.key : $0.value.1 > $1.value.1 }.first?.value.0
        let month = months.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first
        busiestMonth = month?.key
        busiestMonthSeconds = month?.value ?? 0
        if let weekday = weekdays.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).first?.key {
            favoriteWeekday = calendar.weekdaySymbols[weekday - 1]
        } else { favoriteWeekday = nil }
        // Calendar days, including days off: this is a forecast of pace, not an active-day target.
        dailyAverage = recentSeconds / 28
    }

    public func daysToFinish(remainingSeconds: Double) -> Int? {
        guard remainingSeconds.isFinite, remainingSeconds > 0, dailyAverage >= 60 else { return nil }
        return Int(min(3650, ceil(remainingSeconds / dailyAverage)))
    }
}

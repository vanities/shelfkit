import XCTest
@testable import ShelfKit

/// A session as either app might record one.
private struct Session: ActivitySession {
    var startedAt: Date
    var activeSeconds: Double
    var activityGroupKey = "k"
    var activityGroupName = "Book"
    var activityPages = 0
}

final class ActivityTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func key(_ y: Int, _ m: Int, _ d: Int) -> String { DayKey.string(for: day(y, m, d), calendar: calendar) }

    func testDayKeysRoundTrip() {
        let date = day(2026, 9, 21)
        XCTAssertEqual(DayKey.string(for: date, calendar: calendar), "2026-09-21")
        XCTAssertEqual(DayKey.date(from: "2026-09-21", calendar: calendar), date)
        XCTAssertNil(DayKey.date(from: "yesterday", calendar: calendar))
    }

    /// What Mango has synced since before this was shared still reads the same.
    func testADayMangoSyncedStillDecodes() throws {
        let data = Data(#"{"pages":30,"seconds":600,"sessions":1}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(DayActivity.self, from: data), DayActivity(seconds: 600, pages: 30, sessions: 1))
        XCTAssertEqual(try JSONDecoder().decode(DayActivity.self, from: Data(#"{"seconds":60}"#.utf8)).sessions, 0)
    }

    func testStreakCountsBackFromToday() {
        let active: Set<Date> = [day(2026, 9, 19), day(2026, 9, 20), day(2026, 9, 21)]
        let streak = ActivityStats.streaks(active, today: day(2026, 9, 21), calendar: calendar)
        XCTAssertEqual(streak.current, 3)
        XCTAssertEqual(streak.longest, 3)
    }

    /// Before anything today, yesterday's streak is still alive.
    func testStreakSurvivesUntilTodayIsOver() {
        let active: Set<Date> = [day(2026, 9, 19), day(2026, 9, 20)]
        XCTAssertEqual(ActivityStats.streaks(active, today: day(2026, 9, 21), calendar: calendar).current, 2)
    }

    func testMissingADayBreaksIt() {
        let active: Set<Date> = [day(2026, 9, 17), day(2026, 9, 18), day(2026, 9, 20), day(2026, 9, 21)]
        let streak = ActivityStats.streaks(active, today: day(2026, 9, 21), calendar: calendar)
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.longest, 2)
    }

    func testLongestCanBeInThePast() {
        let active: Set<Date> = [day(2026, 1, 1), day(2026, 1, 2), day(2026, 1, 3), day(2026, 1, 4), day(2026, 9, 21)]
        let streak = ActivityStats.streaks(active, today: day(2026, 9, 21), calendar: calendar)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.longest, 4)
    }

    func testNothingNoStreak() {
        XCTAssertEqual(ActivityStats.streaks([], today: day(2026, 9, 21), calendar: calendar).current, 0)
    }

    func testTotalsAndPeriods() {
        let days: [String: DayActivity] = [
            key(2026, 9, 21): DayActivity(seconds: 600, pages: 30, sessions: 1),
            key(2026, 9, 2): DayActivity(seconds: 1200, pages: 40, sessions: 2),
            key(2026, 5, 1): DayActivity(seconds: 3000, pages: 90, sessions: 3),
        ]
        let stats = ActivityStats.build(days: days, sessions: [Session](), now: day(2026, 9, 21), calendar: calendar)
        XCTAssertEqual(stats.totalSeconds, 4800, accuracy: 0.1)
        XCTAssertEqual(stats.thisMonthSeconds, 1800, accuracy: 0.1)
        XCTAssertEqual(stats.daysActive, 3)
        XCTAssertTrue(stats.hasActivity)
    }

    /// Whole weeks, zero-filled, ending today — gaps would read as missing data.
    func testHeatmapIsWholeWeeksEndingToday() throws {
        let stats = ActivityStats.build(days: [key(2026, 9, 21): DayActivity(seconds: 60)], sessions: [Session](),
                                        now: day(2026, 9, 21), calendar: calendar)
        let last = try XCTUnwrap(stats.heatmap.last)
        XCTAssertEqual(last.date, day(2026, 9, 21))
        XCTAssertEqual(last.seconds, 60)
        XCTAssertGreaterThanOrEqual(stats.heatmap.count, (ActivityStats.heatmapWeeks - 1) * 7)
        XCTAssertEqual(calendar.component(.weekday, from: stats.heatmap[0].date), calendar.firstWeekday)
    }

    /// Pace comes only from sessions that turned pages: none for a novel or an audiobook.
    func testPaceOnlyFromSessionsWithPages() throws {
        let sessions = [Session(startedAt: day(2026, 9, 21), activeSeconds: 600, activityPages: 60),
                        Session(startedAt: day(2026, 9, 21), activeSeconds: 600)]
        let stats = ActivityStats.build(days: [:], sessions: sessions, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(stats.pagesPerMinute), 6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.averageSessionMinutes), 10, accuracy: 0.001)
        let listening = ActivityStats.build(days: [:], sessions: [Session(startedAt: .now, activeSeconds: 900)], calendar: calendar)
        XCTAssertNil(listening.pagesPerMinute)
    }

    func testTimeOfDayAndMostTimeSpentIn() {
        let sessions = [
            Session(startedAt: day(2026, 9, 21, hour: 8), activeSeconds: 600, activityGroupKey: "a", activityGroupName: "Dune"),
            Session(startedAt: day(2026, 9, 21, hour: 23), activeSeconds: 1200, activityGroupKey: "b", activityGroupName: "Emma"),
            Session(startedAt: day(2026, 9, 22, hour: 9), activeSeconds: 300, activityGroupKey: "a", activityGroupName: "Dune"),
        ]
        let stats = ActivityStats.build(days: [:], sessions: sessions, calendar: calendar)
        XCTAssertEqual(stats.timeOfDay.map(\.name), ["Morning", "Afternoon", "Evening", "Night"])
        XCTAssertEqual(stats.timeOfDay[0].seconds, 900)
        XCTAssertEqual(stats.timeOfDay[3].seconds, 1200)
        XCTAssertEqual(stats.topByTime.map(\.name), ["Emma", "Dune"])
    }

    func testRollUpGroupsSessionsByDay() {
        let sessions = [Session(startedAt: day(2026, 9, 21), activeSeconds: 100, activityPages: 10),
                        Session(startedAt: day(2026, 9, 21, hour: 5), activeSeconds: 50)]
        let days = DayKey.rollUp(sessions, calendar: calendar)
        XCTAssertEqual(days["2026-09-21"], DayActivity(seconds: 150, pages: 10, sessions: 2))
    }

    // MARK: Between devices

    /// This device's own slot in the cloud is stale — its live sessions stand in for it.
    func testCombinedAddsOtherDevicesButNotThisOnesOldSlot() {
        let own = ["2026-09-21": DayActivity(seconds: 100, sessions: 1)]
        let cloud = ["phone": ["2026-09-21": DayActivity(seconds: 999, sessions: 9)],
                     "ipad": ["2026-09-21": DayActivity(seconds: 50, sessions: 1), "2026-09-20": DayActivity(seconds: 30, sessions: 1)]]
        let all = DeviceActivity.combined(own: own, cloud: cloud, deviceID: "phone")
        XCTAssertEqual(all["2026-09-21"], DayActivity(seconds: 150, sessions: 2))
        XCTAssertEqual(all["2026-09-20"]?.seconds, 30)
    }

    func testUpdatedReplacesThisDevicesSlotAndDropsOldDays() {
        let cloud = ["phone": ["2024-01-01": DayActivity(seconds: 1)], "ipad": ["2026-09-20": DayActivity(seconds: 30)]]
        let own = ["2026-09-21": DayActivity(seconds: 100), "2020-01-01": DayActivity(seconds: 5)]
        let updated = DeviceActivity.updated(cloud: cloud, own: own, deviceID: "phone", since: day(2025, 1, 1), calendar: calendar)
        XCTAssertEqual(updated["phone"], ["2026-09-21": DayActivity(seconds: 100)])
        XCTAssertEqual(updated["ipad"], cloud["ipad"], "other devices' slots are theirs")
    }

    func testDurations() {
        XCTAssertEqual(Durations.short(0), "0m")
        XCTAssertEqual(Durations.short(20), "<1m")
        XCTAssertEqual(Durations.short(45 * 60), "45m")
        XCTAssertEqual(Durations.short(200 * 60), "3h 20m")
    }
}

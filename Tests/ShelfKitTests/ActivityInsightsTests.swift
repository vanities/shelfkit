import XCTest
@testable import ShelfKit

final class ActivityInsightsTests: XCTestCase {
    private struct Session: ActivitySession {
        var startedAt: Date
        var activeSeconds: Double
        var activityGroupKey: String
        var activityGroupName: String
        var activityPages: Int { 0 }
    }
    func testRecapSeparatesSyncedTimeFromLocalFavoritesAndRejectsFutureData() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!
        let yesterday = now.addingTimeInterval(-86_400)
        let future = now.addingTimeInterval(86_400)
        let insights = ActivityInsights(days: ["2026-09-23": .init(seconds: 3600), "2026-09-24": .init(seconds: 1800),
                                               "2026-09-25": .init(seconds: 99999), "2026-08-01": .init(seconds: 7200)],
                                        sessions: [Session(startedAt: yesterday, activeSeconds: 600, activityGroupKey: "a", activityGroupName: "A"),
                                                   Session(startedAt: now, activeSeconds: 900, activityGroupKey: "b", activityGroupName: "B"),
                                                   Session(startedAt: future, activeSeconds: 9999, activityGroupKey: "c", activityGroupName: "Future")],
                                        finishes: [yesterday, future], now: now, calendar: calendar)
        XCTAssertEqual(insights.weekSeconds, 5400)
        XCTAssertEqual(insights.weekFinished, 1)
        XCTAssertEqual(insights.weekFavorite, "B")
        XCTAssertEqual(insights.longestSession, 900)
        XCTAssertEqual(insights.busiestMonth, "2026-08")
        XCTAssertEqual(insights.dailyAverage, 5400 / 28.0, accuracy: 0.01)
        XCTAssertEqual(insights.daysToFinish(remainingSeconds: 5400), 28)
        XCTAssertNil(insights.daysToFinish(remainingSeconds: .infinity))
    }
    func testNoHistoryDoesNotInventAPaceOrFavorite() {
        let insights = ActivityInsights(days: [:], sessions: [Session](), finishes: [])
        XCTAssertNil(insights.weekFavorite)
        XCTAssertNil(insights.favoriteWeekday)
        XCTAssertNil(insights.daysToFinish(remainingSeconds: 3600))
    }
}

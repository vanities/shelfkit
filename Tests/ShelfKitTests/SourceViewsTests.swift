import XCTest
@testable import ShelfKit

/// The Sources list's words are the one bit of logic in its rows.
final class SourceViewsTests: XCTestCase {
    func testAScanSummarySaysWhatItFoundAndWhen() {
        let now = Date()
        XCTAssertTrue(SourceRowView.scanSummary(items: 11, noun: "book", files: 24, at: now).hasPrefix("11 books · 24 files · scanned "))
        XCTAssertTrue(SourceRowView.scanSummary(items: 1, noun: "comic", files: 1, at: now).hasPrefix("1 comic · 1 file · scanned "))
        XCTAssertTrue(SourceRowView.scanSummary(items: 0, noun: "book", files: 0, at: now).hasPrefix("Empty · checked "))
        XCTAssertEqual(SourceRowView.scanSummary(items: 3, noun: "book", files: 3, at: nil), "Not scanned yet")
    }
}

/// The goal card's pace line: where you'd be now if the year's goal were read evenly.
final class GoalPaceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testPaceAgainstTheShareOfTheYearGone() throws {
        let midYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))   // day 183 of 365
        XCTAssertEqual(GoalRing.pace(done: 25, goal: 50, on: midYear, calendar: calendar), "Right on pace.")
        XCTAssertEqual(GoalRing.pace(done: 30, goal: 50, on: midYear, calendar: calendar), "5 ahead of pace.")
        XCTAssertEqual(GoalRing.pace(done: 10, goal: 50, on: midYear, calendar: calendar), "15 behind pace.")
    }
}

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

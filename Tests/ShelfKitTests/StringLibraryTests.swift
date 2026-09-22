import XCTest
@testable import ShelfKit

/// Shelf identity and sort order in both apps come from these; a change here renames shelves
/// and moves saved state, so the expectations are pinned exactly.
final class StringLibraryTests: XCTestCase {
    func testNaturalOrder() {
        let sorted = ["page10.jpg", "page2.jpg", "page1.jpg"].sorted { $0.naturallyPrecedes($1) }
        XCTAssertEqual(sorted, ["page1.jpg", "page2.jpg", "page10.jpg"])
        XCTAssertTrue("Disc 1/01.mp3".naturallyPrecedes("Disc 2/01.mp3"))
        XCTAssertTrue("02 - b".naturallyPrecedes("10 - a"))
    }

    func testMatchingBreaksWordsAtPunctuation() {
        XCTAssertEqual("JoJo's Bizarre Adventure".normalizedForMatching, "jojo s bizarre adventure")
        XCTAssertEqual("One_Punch  Man".normalizedForMatching, "one punch man")
        XCTAssertEqual("Jane Austen".normalizedForMatching, "jane austen")
    }

    func testIdentityDropsPunctuationWithoutBreakingWords() {
        XCTAssertEqual("JoJo's Bizarre Adventure".normalizedForIdentity, "jojosbizarreadventure")
        XCTAssertEqual("JoJo's Bizarre Adventure".normalizedForIdentity, "JoJos Bizarre Adventure".normalizedForIdentity)
    }

    func testDisplayNamesAndEmptiness() {
        XCTAssertEqual("The_Spouter__Inn ".cleanedDisplayName, "The Spouter Inn")
        XCTAssertNil("   ".nilIfEmpty)
        XCTAssertEqual("  Dune ".nilIfEmpty, "Dune")
    }
}

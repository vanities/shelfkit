import XCTest
@testable import ShelfKit

/// The lock's one decision: whether coming back asks for Face ID. And the saved modes both
/// apps wrote must still read.
final class AppLockTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testOffNeverLocks() {
        XCTAssertFalse(AppLock.shouldLock(mode: .off, backgroundedAt: now.addingTimeInterval(-86_400), now: now))
    }

    func testImmediatelyLocksOnAnyReturn() {
        XCTAssertTrue(AppLock.shouldLock(mode: .immediately, backgroundedAt: now, now: now))
    }

    func testAGracePeriodLetsAQuickReturnIn() {
        XCTAssertFalse(AppLock.shouldLock(mode: .afterOneMinute, backgroundedAt: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(AppLock.shouldLock(mode: .afterOneMinute, backgroundedAt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(AppLock.shouldLock(mode: .afterFifteenMinutes, backgroundedAt: now.addingTimeInterval(-600), now: now))
    }

    /// Launch counts as coming back from nowhere: with the lock on, it asks.
    func testNoBackgroundTimeMeansLock() {
        XCTAssertTrue(AppLock.shouldLock(mode: .afterFifteenMinutes, backgroundedAt: nil, now: now))
    }

    func testSavedModesStillRead() {
        XCTAssertEqual(["off", "immediately", "afterOneMinute", "afterFifteenMinutes"].compactMap(LockMode.init(rawValue:)),
                       [.off, .immediately, .afterOneMinute, .afterFifteenMinutes])
    }
}

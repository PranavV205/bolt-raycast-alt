import XCTest
@testable import Bolt

final class SemverTests: XCTestCase {

    func testBasicComparisons() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.1.0", than: "1.2.0"))
    }

    func testEqualIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.3.1", than: "1.3.1"))
    }

    func testNumericNotLexicographic() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0", than: "1.10.0"))
    }

    func testUnequalLengthsPadWithZeros() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2.0", than: "1.2"))
    }
}

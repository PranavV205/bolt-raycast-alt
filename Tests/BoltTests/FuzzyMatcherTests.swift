import XCTest
@testable import Bolt

final class FuzzyMatcherTests: XCTestCase {

    func testExactMatchScoresOne() {
        XCTAssertEqual(FuzzyMatcher.score(query: "safari", candidate: "Safari"), 1.0)
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "vsco", candidate: "Visual Studio Code"))
        XCTAssertNotNil(FuzzyMatcher.score(query: "am", candidate: "Activity Monitor"))
    }

    func testNonSubsequenceReturnsNil() {
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: "Safari"))
        XCTAssertNil(FuzzyMatcher.score(query: "safarii", candidate: "Safari"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "SAFARI", candidate: "safari"))
    }

    func testPrefixBeatsScattered() {
        let prefix = FuzzyMatcher.score(query: "cal", candidate: "Calendar")!
        let scattered = FuzzyMatcher.score(query: "cal", candidate: "Clipboard Manager Log")!
        XCTAssertGreaterThan(prefix, scattered)
    }

    func testWordBoundaryBeatsMidword() {
        let boundary = FuzzyMatcher.score(query: "am", candidate: "Activity Monitor")!
        let midword = FuzzyMatcher.score(query: "am", candidate: "Beamer")!
        XCTAssertGreaterThan(boundary, midword)
    }

    func testEmptyQueryScoresZero() {
        XCTAssertEqual(FuzzyMatcher.score(query: "", candidate: "anything"), 0)
    }

    func testFieldsTakesBest() {
        let single = FuzzyMatcher.score(query: "gh", candidate: "GitHub")!
        let best = FuzzyMatcher.score(query: "gh", fields: ["nope", "GitHub"])!
        XCTAssertEqual(single, best)
    }
}

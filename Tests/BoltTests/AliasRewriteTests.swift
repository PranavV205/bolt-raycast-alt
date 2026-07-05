import XCTest
@testable import Bolt

final class AliasRewriteTests: XCTestCase {

    private let aliases = ["dm": "dark mode", "gs": "gh"]

    func testFirstWordRewritten() {
        XCTAssertEqual(AliasStore.rewrite("dm", aliases: aliases), "dark mode")
    }

    func testTrailingWordsAppended() {
        XCTAssertEqual(AliasStore.rewrite("gs swift fuzzy", aliases: aliases), "gh swift fuzzy")
    }

    func testCaseInsensitiveKeyword() {
        XCTAssertEqual(AliasStore.rewrite("DM", aliases: aliases), "dark mode")
    }

    func testNonAliasUntouched() {
        XCTAssertEqual(AliasStore.rewrite("darkmode", aliases: aliases), "darkmode")
        XCTAssertEqual(AliasStore.rewrite("xdm", aliases: aliases), "xdm")
    }

    func testAliasMustBeFirstWord() {
        XCTAssertEqual(AliasStore.rewrite("toggle dm", aliases: aliases), "toggle dm")
    }

    func testEmptyAndWhitespaceSafe() {
        XCTAssertEqual(AliasStore.rewrite("", aliases: aliases), "")
        XCTAssertEqual(AliasStore.rewrite("   ", aliases: aliases), "   ")
    }

    func testEmptyAliasesNoop() {
        XCTAssertEqual(AliasStore.rewrite("dm", aliases: [:]), "dm")
    }
}

import XCTest
@testable import Bolt

final class SnippetCursorTests: XCTestCase {

    private func snippet(_ content: String) -> Snippet {
        Snippet(keyword: ";t", name: "test", content: content)
    }

    func testCursorMarkerRemovedAndCounted() {
        let (text, caretBack) = snippet("Hello {cursor}, bye").expandedWithCursor()
        XCTAssertEqual(text, "Hello , bye")
        XCTAssertEqual(caretBack, 5)
    }

    func testCursorAtEndMeansNoMove() {
        let (text, caretBack) = snippet("Hello{cursor}").expandedWithCursor()
        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(caretBack, 0)
    }

    func testNoMarkerMeansNoMove() {
        let (text, caretBack) = snippet("Hello").expandedWithCursor()
        XCTAssertEqual(text, "Hello")
        XCTAssertEqual(caretBack, 0)
    }

    func testOnlyFirstMarkerHonored() {
        let (text, caretBack) = snippet("a{cursor}b{cursor}c").expandedWithCursor()
        XCTAssertEqual(text, "ab{cursor}c")
        XCTAssertEqual(caretBack, 10)
    }

    func testMultilineContent() {
        let (text, caretBack) = snippet("Dear {cursor},\nBest").expandedWithCursor()
        XCTAssertEqual(text, "Dear ,\nBest")
        XCTAssertEqual(caretBack, 6)
    }

    func testExpandedContentStripsMarker() {
        XCTAssertEqual(snippet("a{cursor}b").expandedContent(), "ab")
    }
}

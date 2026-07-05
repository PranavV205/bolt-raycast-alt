import XCTest
@testable import Bolt

final class ExpressionParserTests: XCTestCase {

    func testBasicArithmetic() {
        XCTAssertEqual(ExpressionParser.evaluate("2+2"), 4)
        XCTAssertEqual(ExpressionParser.evaluate("10-4"), 6)
        XCTAssertEqual(ExpressionParser.evaluate("6*7"), 42)
        XCTAssertEqual(ExpressionParser.evaluate("15/4"), 3.75)
    }

    func testPrecedenceAndParens() {
        XCTAssertEqual(ExpressionParser.evaluate("2+3*4"), 14)
        XCTAssertEqual(ExpressionParser.evaluate("(2+3)*4"), 20)
        XCTAssertEqual(ExpressionParser.evaluate("2^10"), 1024)
    }

    func testUnaryMinus() {
        XCTAssertEqual(ExpressionParser.evaluate("-5+3"), -2)
    }

    func testThousandsSeparatorsAndSpaces() {
        XCTAssertEqual(ExpressionParser.evaluate("1,920 * 2"), 3840)
        XCTAssertEqual(ExpressionParser.evaluate(" 1 + 1 "), 2)
    }

    func testMultiplicationAliases() {
        XCTAssertEqual(ExpressionParser.evaluate("3x4"), 12)
        XCTAssertEqual(ExpressionParser.evaluate("3×4"), 12)
        XCTAssertEqual(ExpressionParser.evaluate("8÷2"), 4)
    }

    func testMalformedInputReturnsNilNotCrash() {
        XCTAssertNil(ExpressionParser.evaluate("2+"))
        XCTAssertNil(ExpressionParser.evaluate("(2+3"))
        XCTAssertNil(ExpressionParser.evaluate("hello"))
        XCTAssertNil(ExpressionParser.evaluate(""))
        XCTAssertNil(ExpressionParser.evaluate("1/0")) // infinite -> nil
    }

    func testLooksLikeMathGate() {
        XCTAssertTrue(ExpressionParser.looksLikeMath("2+2"))
        XCTAssertTrue(ExpressionParser.looksLikeMath("sqrt(16)"))
        XCTAssertFalse(ExpressionParser.looksLikeMath("safari"))
        XCTAssertFalse(ExpressionParser.looksLikeMath("kill 3000"))
    }
}

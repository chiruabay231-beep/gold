import XCTest
@testable import BacktestKit

final class ParserTests: XCTestCase {
    func testPrecedence() throws {
        let program = try Parser.parse("1 + 2 * 3 ^ 2 > 10 and not close < 5")
        guard case .expression(let expr) = program.statements[0] else { return XCTFail() }
        XCTAssertEqual(expr.description, "(((1 + (2 * (3 ^ 2))) > 10) and (not (close < 5)))")
    }

    func testStatementsAndComments() throws {
        let program = try Parser.parse("""
        // comment
        fast = ema(close,
                   9)   # newline inside parens is ignored
        slow = ema(close, 21); fast - slow
        """)
        XCTAssertEqual(program.statements.count, 3)
        XCTAssertEqual(program.assignedNames, ["fast", "slow"])
    }

    func testHistoryAndTernary() throws {
        let program = try Parser.parse("x = close[1] > open ? 1 : -1")
        guard case .assign(_, let expr, _) = program.statements[0] else { return XCTFail() }
        XCTAssertEqual(expr.description, "((close[1] > open) ? 1 : (- 1))")
    }

    func testErrorsHaveLocations() {
        XCTAssertThrowsError(try Parser.parse("a = ema(close, 9\nb = 1")) { error in
            XCTAssertNotNil((error as? ScriptError)?.location)
        }
        XCTAssertThrowsError(try Parser.parse("close = 1 = 2"))
        XCTAssertThrowsError(try Parser.parse("if close = open"))
        XCTAssertThrowsError(try Parser.parse(""))
        XCTAssertThrowsError(try Parser.parse("a & b"))
    }
}

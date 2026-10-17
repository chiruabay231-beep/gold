import XCTest
@testable import BacktestKit

final class EvaluatorTests: XCTestCase {
    let data = makeData(closes: [10, 11, 12, 13, 14, 13, 12, 11, 12, 13])

    func testArithmeticBroadcast() throws {
        assertSeries(try evaluate("close * 2 + 1", data), data.close.map { $0 * 2 + 1 })
    }

    func testHistoryOperator() throws {
        let s = try evaluate("close - close[1]", data)
        XCTAssertTrue(s[0].isNaN)
        XCTAssertEqual(s[1], 1)
        XCTAssertEqual(s[5], -1)
    }

    func testNegativeHistoryRejected() {
        XCTAssertThrowsError(try evaluate("close[-1]", data))
    }

    func testVariablesAndBindings() throws {
        let s = try evaluate("x = close + k\nx * 2", data, bindings: ["k": .scalar(1)])
        XCTAssertEqual(s[0], 22)
    }

    func testTernaryAndLogic() throws {
        let s = try evaluate("close > 12 and close < 14 ? 1 : 0", data)
        assertSeries(s, [0, 0, 0, 1, 0, 1, 0, 0, 0, 1])
    }

    func testFunctionCallsAndDefaults() throws {
        assertSeries(try evaluate("sma(close, 3)", data), TA.sma(data.close, 3))
        assertSeries(try evaluate("ta.sma(close, 3)", data), TA.sma(data.close, 3))
        assertSeries(try evaluate("rsi(close)", data), TA.rsi(data.close, 14))
        // Zero-argument function without parentheses.
        assertSeries(try evaluate("tr", data), TA.trueRange(high: data.high, low: data.low, close: data.close))
    }

    func testArgumentErrors() {
        XCTAssertThrowsError(try evaluate("ema(close)", data))
        XCTAssertThrowsError(try evaluate("ema(close, close)", data)) { error in
            XCTAssertTrue((error as? ScriptError)?.message.contains("hằng số") ?? false)
        }
        XCTAssertThrowsError(try evaluate("ema(close, 0)", data))
        XCTAssertThrowsError(try evaluate("nope(close)", data))
        XCTAssertThrowsError(try evaluate("unknown_var + 1", data))
    }

    func testPlots() throws {
        let context = EvaluationContext(data: data)
        let result = try Evaluator.run("a = sma(close, 2)\nplot(a)\nplot(close, \"Giá\")\nhline(12)", context: context)
        XCTAssertEqual(result.plots.map(\.title), ["a", "Giá", "12"])
        XCTAssertTrue(result.plots[2].isHorizontalLine)
    }

    func testVariadicMinMax() throws {
        assertSeries(try evaluate("max(open, close, 12)", data),
                     data.close.indices.map { Swift.max(data.open[$0], data.close[$0], 12) })
        let s = try evaluate("min(3, 1, 2)", data)
        XCTAssertEqual(s[0], 1)
    }

    func testSession() throws {
        // Bars start at 2023-11-14 22:13:20 UTC, hourly.
        let s = try evaluate("session(23, 2)", data)
        XCTAssertEqual(s[0], 0)   // 22:13
        XCTAssertEqual(s[1], 1)   // 23:13
        XCTAssertEqual(s[3], 1)   // 01:13
        XCTAssertEqual(s[4], 0)   // 02:13
    }

    func testCustomIndicatorCallable() throws {
        let indicator = CustomIndicator(name: "spread", title: "Spread",
                                        parameters: [ScriptParameter(name: "len", defaultValue: 2)],
                                        script: "close - sma(close, len)")
        let library = FunctionLibrary.standard.adding([indicator])
        let expected = zip(data.close, TA.sma(data.close, 3)).map { $0 - $1 }
        assertSeries(try evaluate("spread(3)", data, library: library), expected)
        // Default parameter.
        assertSeries(try evaluate("spread()", data, library: library),
                     zip(data.close, TA.sma(data.close, 2)).map { $0 - $1 })
        // Nested: an indicator using another custom indicator.
        let outer = CustomIndicator(name: "spread_ema", title: "x", script: "ema(spread(3), 2)")
        let library2 = FunctionLibrary.standard.adding([indicator, outer])
        assertSeries(try evaluate("spread_ema()", data, library: library2), TA.ema(expected, 2))
    }

    func testRecursiveIndicatorFails() {
        let loop = CustomIndicator(name: "loop", title: "Loop", script: "loop() + 1")
        let library = FunctionLibrary.standard.adding([loop])
        XCTAssertThrowsError(try evaluate("loop()", data, library: library))
    }

    func testCustomIndicatorCannotShadowBuiltin() {
        let bad = CustomIndicator(name: "ema", title: "x", script: "close")
        XCTAssertThrowsError(try bad.validate(against: .standard))
        XCTAssertThrowsError(try CustomIndicator(name: "1abc", title: "x", script: "close").validate(against: .standard))
        XCTAssertThrowsError(try CustomIndicator(name: "close", title: "x", script: "close").validate(against: .standard))
        XCTAssertNoThrow(try CustomIndicator(name: "my_osc", title: "x", script: "close").validate(against: .standard))
    }

    func testSamplesAreValid() throws {
        let sample = PriceData(candles: SampleData.candles(count: 2000))
        let library = FunctionLibrary.standard.adding(Samples.indicators)
        for indicator in Samples.indicators {
            try indicator.validate(against: .standard)
            let plots = try indicator.compute(context: EvaluationContext(data: sample, library: library))
            XCTAssertFalse(plots.isEmpty, indicator.name)
        }
        for strategy in Samples.strategies {
            try strategy.validate()
            let result = try BacktestEngine.run(strategy: strategy, data: sample,
                                                config: BacktestConfig(timeZoneIdentifier: "Asia/Ho_Chi_Minh"),
                                                library: library)
            XCTAssertGreaterThan(result.metrics.totalTrades, 0, strategy.name)
        }
    }
}

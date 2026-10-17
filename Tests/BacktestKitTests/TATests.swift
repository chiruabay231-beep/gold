import XCTest
@testable import BacktestKit

final class TATests: XCTestCase {
    func testSMA() {
        assertSeries(TA.sma([1, 2, 3, 4, 5], 3), [.nan, .nan, 2, 3, 4])
        assertSeries(TA.sma([1, .nan, 3, 4, 5, 6], 2), [.nan, .nan, .nan, 3.5, 4.5, 5.5])
    }

    func testEMASeededWithSMA() {
        let ema = TA.ema([1, 2, 3, 4, 5], 3)
        XCTAssertTrue(ema[1].isNaN)
        XCTAssertEqual(ema[2], 2)
        XCTAssertEqual(ema[3], 0.5 * 4 + 0.5 * 2)
        XCTAssertEqual(ema[4], 0.5 * 5 + 0.5 * 3)
    }

    func testEMAOfSeriesWithLeadingNaN() {
        let ema = TA.ema([.nan, .nan, 2, 4, 6], 2)
        assertSeries(ema, [.nan, .nan, .nan, 3, 3 + (6 - 3) * 2.0 / 3])
    }

    func testRSIBounds() {
        let up = TA.rsi((1...30).map(Double.init), 14)
        XCTAssertEqual(up.last, 100)
        let down = TA.rsi((1...30).reversed().map(Double.init), 14)
        XCTAssertEqual(down.last, 0)
        let values = SampleData.candles(count: 300).map(\.close)
        for v in TA.rsi(values, 14) where !v.isNaN {
            XCTAssertTrue((0...100).contains(v))
        }
    }

    func testRSIKnownValue() {
        // Alternating +2 / -1 moves: average gain/loss converge to 1 / 0.5 → RSI ≈ 66.67.
        var price = 100.0
        var closes = [price]
        for i in 0..<400 {
            price += i % 2 == 0 ? 2 : -1
            closes.append(price)
        }
        XCTAssertEqual(TA.rsi(closes, 14).last!, 66.67, accuracy: 3)
    }

    func testHighestLowestStdev() {
        let s: Series = [3, 1, 4, 1, 5, 9, 2, 6]
        assertSeries(TA.highest(s, 3), [.nan, .nan, 4, 4, 5, 9, 9, 9])
        assertSeries(TA.lowest(s, 3), [.nan, .nan, 1, 1, 1, 1, 2, 2])
        XCTAssertEqual(TA.stdev([2, 4, 4, 4, 5, 5, 7, 9], 8).last!, 2, accuracy: 1e-12)
    }

    func testCrosses() {
        let a: Series = [1, 2, 3, 2, 1]
        let b: Series = [2, 2, 2, 2, 2]
        assertSeries(TA.crossover(a, b), [0, 0, 1, 0, 0])
        assertSeries(TA.crossunder(a, b), [0, 0, 0, 0, 1])
    }

    func testTrueRangeAndATR() {
        let data = makeData([(10, 12, 9, 11), (11, 15, 10, 14), (14, 14, 8, 9)])
        assertSeries(TA.trueRange(high: data.high, low: data.low, close: data.close), [3, 5, 6])
        assertSeries(TA.atr(high: data.high, low: data.low, close: data.close, length: 2), [.nan, 4, 5])
    }

    func testMACDAndBollinger() {
        let closes = SampleData.candles(count: 200).map(\.close)
        let macd = TA.macd(closes)
        let i = 150
        XCTAssertEqual(macd.line[i], TA.ema(closes, 12)[i] - TA.ema(closes, 26)[i], accuracy: 1e-9)
        XCTAssertEqual(macd.histogram[i], macd.line[i] - macd.signal[i], accuracy: 1e-9)
        let bands = TA.bollinger(closes, length: 20, multiplier: 2)
        XCTAssertGreaterThan(bands.upper[i], bands.middle[i])
        XCTAssertEqual(bands.upper[i] - bands.middle[i], bands.middle[i] - bands.lower[i], accuracy: 1e-9)
    }

    func testPivotsHaveNoLookahead() {
        let s: Series = [1, 2, 5, 2, 1, 0]
        // Pivot at index 2 is only reported at index 4 (after 2 confirming bars).
        assertSeries(TA.pivothigh(s, left: 2, right: 2), [.nan, .nan, .nan, .nan, 5, .nan])
    }

    func testBarsSinceAndValueWhen() {
        let cond: Series = [0, 1, 0, 0, 1, 0]
        assertSeries(TA.barssince(cond), [.nan, 0, 1, 2, 0, 1])
        let src: Series = [10, 11, 12, 13, 14, 15]
        assertSeries(TA.valuewhen(cond, src, 0), [.nan, 11, 11, 11, 14, 14])
        assertSeries(TA.valuewhen(cond, src, 1), [.nan, .nan, .nan, .nan, 11, 11])
    }

    func testSupertrendDirectionFlips() {
        let up = (0..<60).map { 100 + Double($0) }
        let down = (0..<60).map { 160 - 2 * Double($0) }
        let data = makeData(closes: up + down)
        let st = TA.supertrend(high: data.high, low: data.low, close: data.close, length: 10, multiplier: 3)
        XCTAssertEqual(st.direction[55], 1)
        XCTAssertEqual(st.direction.last, -1)
        XCTAssertLessThan(st.line[55], data.close[55])
        XCTAssertGreaterThan(st.line.last!, data.close.last!)
    }

    func testNoFunctionLooksAhead() throws {
        // Changing the future must not change past values.
        let full = PriceData(candles: SampleData.candles(count: 400))
        let truncated = full.slice(0..<300)
        let library = FunctionLibrary.standard
        let scripts = ["ema(close, 20)", "rsi(close, 14)", "atr(14)", "adx(14)", "supertrend(10, 3)",
                       "pivothigh(high, 5, 5)", "vwap", "stoch(14, 3)", "cci(20)", "kama(close, 10)",
                       "daily_high()", "swing_low(3, 3)", "hma(close, 16)", "bb_upper(close, 20, 2)"]
        for script in scripts {
            let a = try evaluate(script, full, library: library)
            let b = try evaluate(script, truncated, library: library)
            assertSeries(Array(a[0..<300]), b, accuracy: 1e-9)
        }
    }
}

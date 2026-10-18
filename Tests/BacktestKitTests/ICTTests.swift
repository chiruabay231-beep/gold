import XCTest
@testable import BacktestKit

final class ICTTests: XCTestCase {
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testNewYorkSessionsFollowDaylightSaving() {
        // Summer (EDT, UTC-4): 14:00 UTC = 10:00 NY. Winter (EST, UTC-5): 15:00 UTC = 10:00 NY.
        let times = ["2024-07-01T14:00:00Z", "2024-07-01T13:00:00Z", "2024-01-15T15:00:00Z", "2024-01-15T14:00:00Z"].map(date)
        let clock = ICT.NewYorkClock(time: times)
        XCTAssertEqual(clock.session(10, 11), [1, 0, 1, 0])
        XCTAssertEqual(clock.hour[0], 10, accuracy: 1e-9)
        XCTAssertEqual(clock.hour[3], 9, accuracy: 1e-9)
    }

    func testSessionFunctionsInScripts() throws {
        let start = date("2024-07-01T00:00:00Z")   // 20:00 NY on 30 June
        let candles = (0..<24).map { i in
            Candle(time: start.addingTimeInterval(Double(i) * 3600), open: 100, high: 101, low: 99, close: 100)
        }
        let data = PriceData(candles: candles)
        // UTC hour h -> NY hour h-4. Silver Bullet AM 10–11 NY = 14 UTC. London KZ 2–5 NY = 6–8 UTC.
        let sb = try evaluate("silver_bullet()", data)
        XCTAssertEqual(sb.indices.filter { sb[$0] == 1 }, [14])
        let london = try evaluate("kz_london()", data)
        XCTAssertEqual(london.indices.filter { london[$0] == 1 }, [6, 7, 8])
        let asia = try evaluate("kz_asia()", data)
        XCTAssertEqual(asia.indices.filter { asia[$0] == 1 }, [0, 1, 2, 3])
    }

    func testAsiaRangeAndMidnightOpen() {
        // Hourly bars from 18:00 NY (22:00 UTC, EDT) for 10 hours.
        let start = date("2024-07-01T22:00:00Z")
        let highs: [Double] = [10, 11, 15, 12, 13, 14, 9, 9, 9, 9]   // Asia = indices 2...5 (20–24 NY)
        let lows: [Double] = [5, 5, 4, 3, 6, 7, 5, 5, 5, 5]
        let candles = highs.indices.map { i in
            Candle(time: start.addingTimeInterval(Double(i) * 3600),
                   open: Double(100 + i), high: highs[i], low: lows[i], close: 8)
        }
        let clock = ICT.NewYorkClock(time: candles.map(\.time))
        let range = ICT.asiaRange(high: highs, low: lows, clock: clock)
        XCTAssertTrue(range.high[5].isNaN)          // session still running
        XCTAssertEqual(range.high[6], 15)           // completed at 00:00 NY
        XCTAssertEqual(range.low[9], 3)
        let open = ICT.midnightOpen(open: candles.map { $0.open }, clock: clock)
        XCTAssertEqual(open[5], 100)                // 23:00 NY: still the first day's level
        XCTAssertEqual(open[6], 106)                // 00:00 NY bar opens the new day
        XCTAssertEqual(open[9], 106)
    }

    func testSessionLevelsAndWindows() {
        // 1-minute bars from 08:45 NY (12:45 UTC, EDT) for 30 minutes.
        let start = date("2024-07-01T12:45:00Z")
        let candles: [Candle] = (0..<30).map { (i: Int) -> Candle in
            let base = Double(100 + i)
            return Candle(time: start.addingTimeInterval(Double(i) * 60), open: base,
                          high: base + 1, low: base - 1, close: base)
        }
        let clock = ICT.NewYorkClock(time: candles.map(\.time))
        // Macro 08:50–09:10 -> bars 5...24.
        XCTAssertEqual(ICT.sessionWindows(clock: clock, start: 8 + 50.0 / 60, end: 9 + 10.0 / 60), [5...24])
        // 09:00 open is bar 15's open.
        let open9 = ICT.openAt(open: candles.map { $0.open }, clock: clock, hour: 9)
        XCTAssertTrue(open9[14].isNaN)
        XCTAssertEqual(open9[15], 115)
        XCTAssertEqual(open9[29], 115)
        // Session range completes when the window ends.
        let range = ICT.sessionRange(high: candles.map { $0.high }, low: candles.map { $0.low }, clock: clock,
                                     start: 8 + 50.0 / 60, end: 9 + 10.0 / 60)
        XCTAssertTrue(range.high[24].isNaN)
        XCTAssertEqual(range.high[25], 125)
        XCTAssertEqual(range.low[25], 104)
    }

    func testPreviousNewYorkDay() {
        // Bars at 23:00 and 01:00 NY on consecutive days (EDT).
        let times = ["2024-07-02T03:00:00Z", "2024-07-02T05:00:00Z", "2024-07-02T06:00:00Z"].map(date)
        let clock = ICT.NewYorkClock(time: times)
        let r = ICT.previousDay(high: [10, 20, 30], low: [5, 15, 25], clock: clock)
        XCTAssertTrue(r.high[0].isNaN)
        XCTAssertEqual(r.high[1], 10)       // 01:00 NY next day sees the previous day's 10
        XCTAssertEqual(r.low[2], 5)
    }

    func testStructureBreaksShiftsAndSweeps() {
        //            0   1   2   3   4   5   6   7   8   9  10  11
        let high: Series = [10, 12, 11, 10,  9,  8, 9.5, 10, 12.5, 13, 11, 10]
        let low: Series  = [ 9, 10,  9,  8,  6,  7,  7,  8,  9,  11,  9,  8]
        let close: Series = [9.5, 11, 10, 9, 7, 7.5, 9, 9.8, 12.4, 12.8, 10, 8.5]
        let s = ICT.structure(high: high, low: low, close: close, left: 1, right: 1)
        // Swing high 12 at bar 1 confirmed at bar 2; swing low 6 at bar 4 confirmed at bar 5.
        XCTAssertEqual(s.swingHigh[2], 12)
        XCTAssertEqual(s.swingLow[5], 6)
        // Bar 8 closes above 12 -> bullish break; no prior trend, so not a shift.
        XCTAssertTrue(s.bullBreak[8])
        XCTAssertFalse(s.bullShift[8])
        XCTAssertEqual(s.trend[8], 1)
        // Swing low 9 at bar 10? (low 9 at 10, 8 at 11) -> not confirmed yet; close 8.5 > 6, no bear break.
        XCTAssertFalse(s.bearBreak.contains(true))
    }

    func testShiftAndSweepDetection() {
        // left = right = 1. Traced by hand:
        // bar 2 confirms swing high 12 (bar 1); bar 4 confirms swing low 6 (bar 3);
        // bar 5 closes 5.5 < 6 -> bearish break (no prior trend, not a shift);
        // bar 6 confirms swing low 5 (bar 5); bar 7 confirms swing high 9 (bar 6);
        // bar 8 closes 9.6 > 9 while bearish -> bullish break AND shift (MSS).
        let high: Series  = [10, 12, 11, 9, 8, 7.5, 9, 8.5, 10]
        let low: Series   = [ 9, 10,  8, 6, 7, 5,   6, 7,   8]
        let close: Series = [9.5, 11, 8.5, 6.5, 7.5, 5.5, 8, 8, 9.6]
        let s = ICT.structure(high: high, low: low, close: close, left: 1, right: 1)
        XCTAssertTrue(s.bearBreak[5])
        XCTAssertFalse(s.bearShift[5])
        XCTAssertEqual(s.trend[5], -1)
        XCTAssertTrue(s.bullBreak[8])
        XCTAssertTrue(s.bullShift[8])
        XCTAssertEqual(s.trend[8], 1)
        XCTAssertEqual(s.swingHigh[8], 9)
        XCTAssertEqual(s.swingLow[8], 5)

        // Same data but bar 5 closes back above 6: a sell-side sweep, not a break.
        var swept = close
        swept[5] = 6.2
        let s2 = ICT.structure(high: high, low: low, close: swept, left: 1, right: 1)
        XCTAssertTrue(s2.sellSideSweep[5])
        XCTAssertFalse(s2.bearBreak[5])
        XCTAssertFalse(s2.bullShift[8])   // no bearish trend before the break
    }

    func testFairValueGaps() {
        // Bullish FVG at bar 2: high[0]=10 < low[2]=11. Filled at bar 5 (low 9.5 <= 10).
        let high: Series = [10, 12, 13, 13, 12, 11, 11]
        let low: Series  = [ 9, 10, 11, 12, 10.5, 9.5, 10]
        let z = ICT.fairValueGaps(high: high, low: low)
        XCTAssertTrue(z.bullTop[1].isNaN)
        XCTAssertEqual(z.bullTop[2], 11)
        XCTAssertEqual(z.bullBottom[2], 10)
        XCTAssertEqual(z.bullTop[4], 11)            // partly filled, still active
        XCTAssertTrue(z.bullTop[5].isNaN)           // fully filled
        // Bearish FVG: low[n1] > high[n3].
        let zb = ICT.fairValueGaps(high: [12, 11, 9, 9.5, 12.5], low: [10, 9, 8, 8, 9])
        XCTAssertEqual(zb.bearTop[2], 10)
        XCTAssertEqual(zb.bearBottom[2], 9)
        XCTAssertEqual(zb.bearTop[3], 10)
        XCTAssertTrue(zb.bearTop[4].isNaN)
    }

    func testOrderBlockAndScripts() throws {
        let data = PriceData(candles: SampleData.candles(count: 3000))
        let library = FunctionLibrary.standard
        for script in ["structure(5, 5)", "mss_bull(3, 3)", "sweep_ssl()", "equilibrium()", "bull_fvg_top()",
                       "bear_fvg_ce(0.5)", "bull_ob_bottom(5, 5, 20)", "asia_high()", "ny_midnight_open()",
                       "prev_week_low()", "kz_ny_am() or silver_bullet_pm()", "london_high()",
                       "am_open()", "ny_pdh()", "ny_pdl()"] {
            let s = try evaluate(script, data, library: library)
            XCTAssertEqual(s.count, data.count, script)
        }
        // Order block lies below the breaking close and is a bearish candle's range.
        let d = data
        let s = ICT.structure(high: d.high, low: d.low, close: d.close, left: 5, right: 5)
        let ob = ICT.orderBlocks(open: d.open, high: d.high, low: d.low, close: d.close, structure: s)
        guard let i = s.bullBreak.firstIndex(of: true) else { return XCTFail("no break") }
        XCTAssertFalse(ob.bullTop[i].isNaN)
        XCTAssertLessThan(ob.bullBottom[i], d.close[i])
    }

    func testICTNoLookahead() throws {
        let full = PriceData(candles: SampleData.candles(count: 1200, interval: 900))
        let cut = full.slice(0..<900)
        for script in ["structure(3, 3)", "mss_bear(3, 3)", "sweep_bsl(3, 3)", "equilibrium(3, 3)",
                       "bear_fvg_top()", "bull_ob_top(3, 3)", "asia_low()", "ny_midnight_open()", "prev_week_high()"] {
            let a = try evaluate(script, full)
            let b = try evaluate(script, cut)
            assertSeries(Array(a[0..<900]), b)
        }
    }

    func testICTSampleStrategiesTrade() throws {
        let data = PriceData(candles: SampleData.candles(count: 6000, interval: 900))
        let library = FunctionLibrary.standard.adding(Samples.indicators)
        for strategy in Samples.strategies where strategy.name.hasPrefix("ICT") {
            try strategy.validate()
            let result = try BacktestEngine.run(strategy: strategy, data: data, config: BacktestConfig(), library: library)
            XCTAssertGreaterThan(result.trades.count, 0, strategy.name)
        }
    }

    func testICTM1TrendStrategyOnOneMinuteBars() throws {
        let strategy = try XCTUnwrap(Samples.strategies.first { $0.name.hasPrefix("ICT M1 Trend") })
        try strategy.validate()
        let data = PriceData(candles: SampleData.candles(count: 20_000, interval: 60))
        let result = try BacktestEngine.run(strategy: strategy, data: data, config: BacktestConfig(),
                                            library: FunctionLibrary.standard.adding(Samples.indicators))
        XCTAssertGreaterThan(result.trades.count, 0)
        print("ICT M1 Trend on 20k synthetic M1 bars: \(result.trades.count) trades, win rate \(result.metrics.winRate), net \(result.metrics.netProfit)")
    }
}

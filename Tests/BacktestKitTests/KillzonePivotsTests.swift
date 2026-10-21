import XCTest
@testable import BacktestKit

final class KillzonePivotsTests: XCTestCase {
    /// Three days of 15-minute bars from Monday 2026-10-12 00:00 New York (EDT).
    private func candles(_ edit: (inout [Candle]) -> Void = { _ in }) -> [Candle] {
        var components = DateComponents(year: 2026, month: 10, day: 12, hour: 0, minute: 0)
        components.timeZone = TimeZone(identifier: "America/New_York")
        let t0 = Calendar(identifier: .gregorian).date(from: components)!
        var result = (0..<288).map { i -> Candle in
            Candle(time: t0.addingTimeInterval(Double(i) * 900), open: 100, high: 100.5, low: 99.5, close: 100)
        }
        edit(&result)
        return result
    }

    func testLondonPivotExtendsUntilMitigated() {
        let data = candles { c in
            c[12].high = 110   // 03:00, inside London 02:00–05:00
            c[40].high = 111   // 10:00, trades through the London high
        }
        let output = KillzonePivots.compute(candles: data, barInterval: 900, config: KillzonePivots.Config())
        let londonBox = output.boxes.first { $0.session == 1 }
        XCTAssertEqual(londonBox?.range, 8...19)
        XCTAssertEqual(londonBox?.high, 110)
        let pivot = output.levels.first { $0.kind == .pivotHigh(session: 1) && $0.price == 110 }
        XCTAssertNotNil(pivot)
        XCTAssertEqual(pivot?.start, 12)
        XCTAssertEqual(pivot?.end, 40)
        XCTAssertEqual(pivot?.mitigated, true)
        XCTAssertEqual(pivot?.label, "LO.H")

        var past = KillzonePivots.Config()
        past.pivotExtension = .pastMitigation
        let extended = KillzonePivots.compute(candles: data, barInterval: 900, config: past)
            .levels.first { $0.kind == .pivotHigh(session: 1) && $0.price == 110 }
        XCTAssertNil(extended?.end)

        var hidden = KillzonePivots.Config()
        hidden.showMitigated = false
        XCTAssertNil(KillzonePivots.compute(candles: data, barInterval: 900, config: hidden)
            .levels.first { $0.kind == .pivotHigh(session: 1) && $0.price == 110 })
    }

    func testLivePivotsFollowAnOpenSession() {
        // Bars up to 03:15: London (02:00–05:00) is still open.
        let data = Array(candles { c in c[12].high = 110 }.prefix(14))
        let output = KillzonePivots.compute(candles: data, barInterval: 900, config: KillzonePivots.Config())
        let live = output.levels.first { $0.kind == .pivotHigh(session: 1) }
        XCTAssertEqual(live?.price, 110)
        XCTAssertEqual(live?.start, 12)
        XCTAssertNil(live?.end)
        XCTAssertEqual(live?.label, "LO.H")
        XCTAssertNotNil(output.levels.first { $0.kind == .pivotLow(session: 1) })

        var off = KillzonePivots.Config()
        off.livePivots = false
        XCTAssertNil(KillzonePivots.compute(candles: data, barInterval: 900, config: off)
            .levels.first { $0.kind == .pivotHigh(session: 1) })
    }

    func testDaysCountBackFromTheFocusedBar() {
        let data = candles()   // three days of 15-minute bars
        var config = KillzonePivots.Config()
        config.maxDays = 1
        let latest = KillzonePivots.compute(candles: data, barInterval: 900, config: config)
        XCTAssertTrue(latest.boxes.allSatisfy { $0.range.lowerBound >= 192 })
        // Scrolled back to the first day: its sessions are drawn too.
        let scrolled = KillzonePivots.compute(candles: data, barInterval: 900, config: config, focusIndex: 50)
        XCTAssertTrue(scrolled.boxes.contains { $0.range.lowerBound < 96 })
    }

    func testLiquiditySweepNeedsCloseBackInside() {
        let swept = candles { c in
            c[12].high = 110   // London high
            c[40].high = 111   // wick through it, close stays at 100
        }
        let sweep = KillzonePivots.compute(candles: swept, barInterval: 900, config: KillzonePivots.Config())
            .sweeps.first { $0.label == "LO.H" }
        XCTAssertEqual(sweep?.index, 40)
        XCTAssertEqual(sweep?.levelStart, 12)
        XCTAssertEqual(sweep?.bullish, false)
        XCTAssertEqual(sweep?.price, 110)

        let broken = candles { c in
            c[12].high = 110
            c[40].high = 112
            c[40].close = 111   // closes above: a break, not a sweep
        }
        XCTAssertNil(KillzonePivots.compute(candles: broken, barInterval: 900, config: KillzonePivots.Config())
            .sweeps.first { $0.label == "LO.H" })
    }

    func testSMTDivergence() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        func bars(_ highs: [Int: Double], lows: [Int: Double] = [:]) -> [Candle] {
            (0..<40).map { i in
                Candle(time: t0.addingTimeInterval(Double(i) * 300), open: 100, high: highs[i] ?? 100.5,
                       low: lows[i] ?? 99.5, close: 100)
            }
        }
        // Gold makes a higher high, silver a lower high: bearish SMT.
        let gold = bars([10: 105, 20: 106])
        let silver = bars([10: 105, 20: 104])
        let smt = KillzonePivots.smtDivergences(gold, silver, config: KillzonePivots.Config())
        XCTAssertEqual(smt.count, 1)
        XCTAssertEqual(smt.first?.bullish, false)
        XCTAssertEqual(smt.first?.start, 10)
        XCTAssertEqual(smt.first?.end, 20)
        // Both make higher highs: no divergence.
        XCTAssertTrue(KillzonePivots.smtDivergences(gold, bars([10: 105, 20: 107]), config: KillzonePivots.Config()).isEmpty)

        // Inverse market (DXY): gold lower low while DXY makes a lower high = bullish SMT.
        var inverse = KillzonePivots.Config()
        inverse.smtInverse = true
        let goldLows = bars([:], lows: [10: 95, 20: 94])
        let dxy = bars([10: 105, 20: 104])
        let bullish = KillzonePivots.smtDivergences(goldLows, dxy, config: inverse)
        XCTAssertEqual(bullish.first?.bullish, true)
        XCTAssertEqual(bullish.first?.end, 20)
    }

    func testOpensCutoffStampsAndLimit() {
        let data = candles { c in c[96].open = 105 }   // Tuesday 00:00
        var config = KillzonePivots.Config()
        config.cutoffEnabled = true
        config.cutoffHour = 15
        config.showPreviousDay = true
        config.showDayOfWeek = true
        let output = KillzonePivots.compute(candles: data, barInterval: 900, config: config)
        let dailyOpens = output.levels.filter { $0.kind == .open(mark: 0) }
        XCTAssertEqual(dailyOpens.map(\.start), [96, 192])   // day 1 starts at bar 0 with no bar before it
        XCTAssertEqual(dailyOpens.first?.price, 105)
        XCTAssertEqual(dailyOpens.first?.end, 96 + 60)      // cut off at 15:00
        XCTAssertEqual(output.levels.first { $0.kind == .open(mark: 2) }?.start, 38)  // 09:30
        XCTAssertEqual(output.stamps.map(\.index), [96, 192])
        XCTAssertEqual(output.levels.filter { $0.kind == .previousDay }.map(\.label), ["PDH", "PDL"])
        XCTAssertEqual(output.dayLabels.map(\.weekday), [2, 3, 4])   // Mon, Tue, Wed
        XCTAssertEqual(output.ranges.count, 5)

        let hourly = KillzonePivots.compute(candles: data, barInterval: 3600, config: config)
        XCTAssertTrue(hourly.hiddenByTimeframe)
        // Only the day highs/lows stay above the killzone timeframe limit.
        XCTAssertTrue(hourly.levels.allSatisfy {
            switch $0.kind {
            case .dayHigh, .dayLow: return true
            default: return false
            }
        })
    }

    func testConfigDecodesWithMissingKeys() throws {
        let config = try JSONDecoder().decode(KillzonePivots.Config.self, from: Data(#"{"maxDays": 7}"#.utf8))
        XCTAssertEqual(config.maxDays, 7)
        XCTAssertEqual(config.sessions.count, 5)
        XCTAssertEqual(config.sessions[2].start, 9.5)
        let roundTrip = try JSONDecoder().decode(KillzonePivots.Config.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(roundTrip, config)
    }

    func testMacroBoxes() {
        let data = candles { c in c[36].high = 120 }   // 09:00, inside the 08:50–09:10 macro
        let output = KillzonePivots.compute(candles: data, barInterval: 900, config: KillzonePivots.Config())
        let amMacro = output.macroBoxes.first { $0.macro == 2 && $0.range.contains(36) }
        XCTAssertEqual(amMacro?.range, 36...36)   // 15m bars: only the 09:00 bar is inside
        XCTAssertEqual(amMacro?.high, 120)
        var config = KillzonePivots.Config()
        config.macroTimeframeLimitMinutes = 5
        XCTAssertTrue(KillzonePivots.compute(candles: data, barInterval: 900, config: config).macroBoxes.isEmpty)
    }

    func testFairValueGapsRunUntilTouched() {
        let data = candles { c in
            // Bullish gap: bar 102 low (103) above bar 100 high (101).
            c[100].high = 101; c[101].high = 104; c[101].close = 104; c[102].low = 103; c[102].high = 105
            for j in 103..<288 { c[j].low = 104; c[j].high = 105; c[j].open = 104.5; c[j].close = 104.5 }
        }
        var config = KillzonePivots.Config()
        config.fvgMinSize = 0.5
        let gap = KillzonePivots.compute(candles: data, barInterval: 900, config: config).fvgs.first { $0.bullish && $0.start == 101 }
        XCTAssertEqual(gap?.bottom, 101)
        XCTAssertEqual(gap?.top, 103)
        XCTAssertEqual(gap?.mid, 102)
        // Never touched: runs to the forming bar.
        XCTAssertEqual(gap?.end, 287)
        XCTAssertEqual(gap?.touched, false)

        // A wick into the gap ends it at that bar; it held, so it stays 15 minutes after the touch.
        var touched = data
        touched[150].low = 102.5
        XCTAssertNil(KillzonePivots.compute(candles: touched, barInterval: 900, config: config).fvgs.first { $0.start == 101 },
                     "gone long after the touch")
        let recent = Array(touched.prefix(151))   // the touch is the last bar
        let ended = KillzonePivots.compute(candles: recent, barInterval: 900, config: config).fvgs.first { $0.start == 101 }
        XCTAssertEqual(ended?.end, 150)
        XCTAssertEqual(ended?.touched, true)
        XCTAssertEqual(ended?.filled, false)
        // Traded through: gone at once.
        var through = recent
        through[150].low = 100.5
        XCTAssertNil(KillzonePivots.compute(candles: through, barInterval: 900, config: config).fvgs.first { $0.start == 101 })
        config.fvgHideFilled = true
        XCTAssertNil(KillzonePivots.compute(candles: recent, barInterval: 900, config: config).fvgs.first { $0.start == 101 })
        config.fvgHideFilled = false

        // M1 to D1 by default; not on weekly bars. Still drawn above the killzone limit.
        XCTAssertFalse(KillzonePivots.compute(candles: data, barInterval: 60, config: config).fvgs.isEmpty)
        let hourly = KillzonePivots.compute(candles: data, barInterval: 3600, config: config)
        XCTAssertTrue(hourly.hiddenByTimeframe)
        XCTAssertFalse(hourly.fvgs.isEmpty)
        XCTAssertTrue(KillzonePivots.compute(candles: data, barInterval: 604_800, config: config).fvgs.isEmpty)
    }

    func testStrongFairValueGapsOnlyAndVolumeImbalance() {
        let data = candles { c in
            // Weak gap: the middle candle has a small body.
            c[100].high = 101; c[101].open = 101.2; c[101].close = 101.4; c[101].low = 100.9; c[101].high = 103.1
            c[102].low = 103; c[102].high = 104
            for j in 103..<150 { c[j].low = 104; c[j].high = 105; c[j].open = 104.5; c[j].close = 104.5 }
            // Strong gap: a big up candle 105 → 112.
            c[150].low = 104.9; c[150].high = 105.2; c[151].open = 105; c[151].close = 112; c[151].low = 104.9; c[151].high = 112.2
            c[152].low = 108; c[152].high = 113; c[152].open = 112; c[152].close = 112.5
            for j in 153..<288 { c[j].low = 112; c[j].high = 113; c[j].open = 112.5; c[j].close = 112.5 }
        }
        var config = KillzonePivots.Config()
        config.showVI = false
        let strong = KillzonePivots.compute(candles: data, barInterval: 900, config: config).fvgs
        XCTAssertNotNil(strong.first { $0.start == 151 })
        XCTAssertNil(strong.first { $0.start == 101 }, "weak gap filtered")
        config.fvgStrongOnly = false
        XCTAssertNotNil(KillzonePivots.compute(candles: data, barInterval: 900, config: config).fvgs.first { $0.start == 101 })

        // Volume imbalance: two up candles, gap between the first close and the second open, wicks overlapping.
        var vi = data
        vi[200].open = 112.2; vi[200].close = 112.6; vi[200].low = 112.1; vi[200].high = 113
        vi[201].open = 112.9; vi[201].close = 113.5; vi[201].low = 112.8; vi[201].high = 113.6
        config.showVI = true
        let fresh = KillzonePivots.compute(candles: Array(vi.prefix(202)), barInterval: 900, config: config)
            .volumeImbalances.first { $0.start == 200 }
        XCTAssertEqual(fresh?.bullish, true)
        XCTAssertEqual(fresh?.bottom, 112.6)
        XCTAssertEqual(fresh?.top, 112.9)
        let imbalance = KillzonePivots.compute(candles: vi, barInterval: 900, config: config).volumeImbalances.first { $0.start == 200 }
        // Bar 202 trades down to 112, through the whole gap: the VI is gone at once.
        XCTAssertNil(imbalance)
        // Only a touch that holds keeps it (for 15 minutes).
        var held = vi
        for j in 202..<288 { held[j].low = 112.7; held[j].high = 113.4; held[j].open = 113; held[j].close = 113.1 }
        let bounce = KillzonePivots.compute(candles: Array(held.prefix(203)), barInterval: 900, config: config)
            .volumeImbalances.first { $0.start == 200 }
        XCTAssertEqual(bounce?.touched, true)
        XCTAssertEqual(bounce?.end, 202)
    }

    func testDailyHighsAndLowsStopWhenTouched() {
        // 15-minute bars from Monday 12 Oct 2026 00:00 New York: three days of 96 bars.
        let data = candles { c in
            for j in 0..<c.count { c[j].high = 100.5; c[j].low = 99.5 }
            c[40].high = 105        // Monday high, never taken again
            c[50].low = 95          // Monday low, swept on Tuesday
            c[120].low = 94         // Tuesday takes Monday's low
            c[130].high = 103       // Tuesday high, still there
        }
        var config = KillzonePivots.Config()
        config.showFVG = false
        config.showMSS = false
        let levels = KillzonePivots.compute(candles: data, barInterval: 900, config: config).levels.filter {
            if case .dayHigh = $0.kind { return true }
            if case .dayLow = $0.kind { return true }
            return false
        }
        // Monday (weekday 2): the high runs on; the low stops at the bar that reached it, dotted.
        XCTAssertTrue(levels.contains { $0.kind == .dayHigh(weekday: 2) && $0.price == 105 && $0.start == 40 && $0.end == nil && !$0.mitigated })
        XCTAssertTrue(levels.contains { $0.kind == .dayLow(weekday: 2) && $0.price == 95 && $0.start == 50 && $0.end == 120 && $0.mitigated })
        // Tuesday (weekday 3): both kept; the running Wednesday is not drawn.
        XCTAssertTrue(levels.contains { $0.kind == .dayHigh(weekday: 3) && $0.price == 103 })
        XCTAssertTrue(levels.contains { $0.kind == .dayLow(weekday: 3) && $0.price == 94 })
        XCTAssertFalse(levels.contains { $0.kind == .dayHigh(weekday: 4) })
        // A touch is enough (no need to trade beyond it).
        var exact = data
        exact[160].high = 105
        XCTAssertTrue(KillzonePivots.compute(candles: exact, barInterval: 900, config: config).levels.contains {
            $0.kind == .dayHigh(weekday: 2) && $0.end == 160 && $0.mitigated
        })
        config.dailyLevelsKeepTouched = false
        XCTAssertFalse(KillzonePivots.compute(candles: data, barInterval: 900, config: config).levels.contains {
            $0.kind == .dayLow(weekday: 2)
        })
        config.showDailyLevels = false
        XCTAssertFalse(KillzonePivots.compute(candles: data, barInterval: 900, config: config).levels.contains {
            if case .dayHigh = $0.kind { return true } else { return false }
        })
    }

    func testFairValueGapConfluenceWithHigherTimeframe() {
        // M1 bars from a 5-minute boundary.
        let t0 = Date(timeIntervalSince1970: 1_700_000_100)
        var ranges: [(Double, Double)] = Array(repeating: (100, 101), count: 5)
        ranges += [(100.5, 102), (101.5, 106), (103, 107), (104, 110), (104, 109)]
        ranges += Array(repeating: (105, 108), count: 5)
        ranges += Array(repeating: (106, 107), count: 45)
        let data = ranges.enumerated().map { i, r in
            Candle(time: t0.addingTimeInterval(Double(i) * 60), open: r.0, high: r.1, low: r.0, close: r.1)
        }
        XCTAssertEqual(KillzonePivots.higherTimeframe(60), 300)
        let fiveMinute = KillzonePivots.aggregate(data, seconds: 300)
        XCTAssertEqual(fiveMinute.bars.count, 12)
        XCTAssertEqual(fiveMinute.first[1], 5)
        XCTAssertEqual(fiveMinute.bars[1].high, 110)

        var config = KillzonePivots.Config()
        let gaps = KillzonePivots.compute(candles: data, barInterval: 60, config: config).fvgs
        // M1 gaps [101, 101.5] and [102, 103] sit inside the M5 gap [101, 105].
        let inner = gaps.first { $0.start == 6 }
        XCTAssertEqual(inner?.bottom, 102)
        XCTAssertEqual(inner?.top, 103)
        XCTAssertEqual(inner?.confluence, true)
        XCTAssertEqual(inner?.end, 59)
        XCTAssertEqual(gaps.first { $0.start == 5 }?.confluence, true)

        config.fvgConfluence = false
        XCTAssertTrue(KillzonePivots.compute(candles: data, barInterval: 60, config: config).fvgs.allSatisfy { !$0.confluence })
    }

    func testMarketStructureShift() {
        // Up leg with a swing high at 20, down leg breaking the swing low, then a rally through the last swing high.
        var prices: [Double] = []
        prices += (0...20).map { 100 + Double($0) }          // to 120
        prices += (1...15).map { 120 - Double($0) * 1.5 }    // to 97.5
        prices += (1...10).map { 97.5 + Double($0) * 0.5 }   // to 102.5
        prices += (1...10).map { 102.5 - Double($0) }        // to 92.5 (breaks swing low)
        prices += (1...30).map { 92.5 + Double($0) * 1.2 }   // to 128.5 (breaks swing highs)
        let t0 = Date(timeIntervalSince1970: 0)
        let data = prices.enumerated().map { i, p in
            Candle(time: t0.addingTimeInterval(Double(i) * 900), open: p, high: p + 0.2, low: p - 0.2, close: p)
        }
        var config = KillzonePivots.Config()
        config.swingLength = 3
        config.showBOS = true
        let breaks = KillzonePivots.compute(candles: data, barInterval: 900, config: config).breaks
        XCTAssertTrue(breaks.contains { !$0.bullish })
        let mss = breaks.first { $0.bullish && $0.shift }
        XCTAssertNotNil(mss)
        XCTAssertLessThan(mss!.start, mss!.end)
        config.showBOS = false
        XCTAssertTrue(KillzonePivots.compute(candles: data, barInterval: 900, config: config).breaks.allSatisfy(\.shift))
    }
}

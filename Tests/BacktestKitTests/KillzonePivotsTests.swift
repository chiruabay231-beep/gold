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
        XCTAssertTrue(hourly.levels.isEmpty)
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

    func testFairValueGapsAndTimeframeRule() {
        let data = candles { c in
            // Bullish gap: bar 102 low (103) above bar 100 high (101).
            c[100].high = 101; c[101].high = 104; c[101].close = 104; c[102].low = 103; c[102].high = 105
            for j in 103..<288 { c[j].low = 104; c[j].high = 105; c[j].open = 104.5; c[j].close = 104.5 }
        }
        var config = KillzonePivots.Config()
        config.fvgMinSize = 0.5
        let gaps = KillzonePivots.compute(candles: data, barInterval: 900, config: config).fvgs
        let gap = gaps.first { $0.bullish && $0.start == 101 }
        XCTAssertEqual(gap?.bottom, 101)
        XCTAssertEqual(gap?.top, 103)
        XCTAssertEqual(gap?.end, 102)       // 2-bar box
        XCTAssertEqual(gap?.mid, 102)
        XCTAssertEqual(gap?.filled, false)
        // M1 is below the M5 minimum.
        XCTAssertTrue(KillzonePivots.compute(candles: data, barInterval: 60, config: config).fvgs.isEmpty)
        // FVG still drawn above the killzone timeframe limit.
        let hourly = KillzonePivots.compute(candles: data, barInterval: 3600, config: config)
        XCTAssertTrue(hourly.hiddenByTimeframe)
        XCTAssertFalse(hourly.fvgs.isEmpty)
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

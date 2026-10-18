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
}

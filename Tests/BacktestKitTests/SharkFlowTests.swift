import XCTest
@testable import BacktestKit

final class SharkFlowTests: XCTestCase {
    private func bar(_ i: Int, _ o: Double, _ h: Double, _ l: Double, _ c: Double, _ v: Double) -> Candle {
        Candle(time: Date(timeIntervalSince1970: Double(i) * 60), open: o, high: h, low: l, close: c, volume: v)
    }

    func testMoneyFlowAndSharks() {
        var candles = (0..<30).map { bar($0, 100, 101, 99, 100.6, 10) }       // closes near the high: buying
        candles.append(bar(30, 100, 101, 95, 95.2, 60))                       // big red bar, 6× volume: shark selling
        candles += (31..<40).map { bar($0, 100, 101, 99, 99.2, 10) }          // closes near the low: selling
        let out = SharkFlow.compute(candles: candles, config: SharkFlow.Config(flowLength: 10, volumeLength: 20, sharkMultiple: 2.5))
        XCTAssertTrue(out.flow[8].isNaN)
        XCTAssertEqual(out.flow[29], 0.6, accuracy: 1e-9)                     // money coming in
        XCTAssertLessThan(out.current ?? 0, -0.5)                             // then going out
        XCTAssertEqual(out.sharks.count, 1)
        XCTAssertEqual(out.sharks.first?.index, 30)
        XCTAssertEqual(out.sharks.first?.buying, false)
        XCTAssertEqual(out.sharks.first?.ratio ?? 0, 6, accuracy: 1e-9)
    }

    func testPriceAgainstMoney() {
        // Price creeps up while every bar closes near its low: a weak rise.
        let up = (0..<40).map { i -> Candle in
            let base = 100 + Double(i) * 0.5
            return bar(i, base, base + 1, base - 1, base - 0.8, 10)
        }
        let out = SharkFlow.compute(candles: up, config: SharkFlow.Config(flowLength: 10))
        XCTAssertEqual(out.situation, .weakUp)
        XCTAssertEqual(out.divergences.first?.index, 10)
        XCTAssertEqual(out.divergences.first?.bullish, false)
        // Price falling with closes near the highs: dip being bought.
        let down = (0..<40).map { i -> Candle in
            let base = 120 - Double(i) * 0.5
            return bar(i, base, base + 1, base - 1, base + 0.8, 10)
        }
        XCTAssertEqual(SharkFlow.compute(candles: down, config: SharkFlow.Config(flowLength: 10)).situation, .weakDown)
    }

    func testRangeStandsInWithoutVolume() {
        var candles = (0..<25).map { bar($0, 100, 100.5, 99.5, 100.4, 0) }
        candles.append(bar(25, 100, 104, 99.9, 103.9, 0))                    // wide green bar
        let out = SharkFlow.compute(candles: candles)
        XCTAssertEqual(out.sharks.last?.index, 25)
        XCTAssertEqual(out.sharks.last?.buying, true)
    }
}

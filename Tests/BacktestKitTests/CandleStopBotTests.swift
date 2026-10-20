import XCTest
@testable import BacktestKit

final class CandleStopBotTests: XCTestCase {
    private func bar(_ i: Int, _ o: Double, _ h: Double, _ l: Double, _ c: Double) -> Candle {
        Candle(time: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 60), open: o, high: h, low: l, close: c)
    }

    func testOrdersAroundTheCandle() {
        var config = CandleStopBot.Config()
        config.offset = 0.5
        config.rr = 2
        let orders = CandleStopBot.orders(after: bar(0, 100, 104, 98, 103), config: config)
        XCTAssertEqual(orders.count, 2)
        let buy = orders.first { $0.side == .long }
        XCTAssertEqual(buy?.entry, 104.5)
        XCTAssertEqual(buy?.stop, 97.5)
        XCTAssertEqual(buy?.target, 118.5)  // 104.5 + 2 × 7
        let sell = orders.first { $0.side == .short }
        XCTAssertEqual(sell?.entry, 97.5)
        XCTAssertEqual(sell?.stop, 104.5)
        XCTAssertEqual(sell?.target, 83.5)

        config.direction = .long
        config.stopMode = .fixed
        config.stopDistance = 3
        config.rr = 0
        let only = CandleStopBot.orders(after: bar(0, 100, 104, 98, 103), config: config)
        XCTAssertEqual(only.count, 1)
        XCTAssertEqual(only[0].stop, 101.5)
        XCTAssertNil(only[0].target)

        config.minRange = 10
        XCTAssertTrue(CandleStopBot.orders(after: bar(0, 100, 104, 98, 103), config: config).isEmpty)
    }

    func testBacktestFillsOneSideAndHitsTarget() {
        var config = CandleStopBot.Config()
        config.rr = 1
        config.lots = 1
        let candles = [
            bar(0, 100, 101, 99, 100.5),   // buy stop 101 (SL 99, TP 103), sell stop 99 (SL 101, TP 97)
            bar(1, 100.5, 103.5, 100.2, 103.2), // breaks up: buy fills at 101, TP 103 reached; sell cancelled
            bar(2, 103.2, 103.4, 103.0, 103.1),
        ]
        let report = CandleStopBot.backtest(candles: candles, symbol: "BTCUSDT", config: config)
        XCTAssertEqual(report.trades.first?.side, .long)
        XCTAssertEqual(report.trades.first?.reason, .target)
        XCTAssertEqual(report.trades.first?.profit ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(report.wins, 1)
        // The last candle's two orders wait for the next one.
        XCTAssertEqual(report.account.pending.count, 2)
        // The sell side never filled.
        XCTAssertFalse(report.trades.contains { $0.side == .short })
    }

    func testOnePositionAtATimeAndStop() {
        var config = CandleStopBot.Config()
        config.rr = 5
        config.lots = 1
        let candles = [
            bar(0, 100, 101, 99, 100),
            bar(1, 100, 101.5, 100.5, 101.2),  // buy fills at 101 (SL 99, TP 111); still open
            bar(2, 101.2, 101.3, 98.5, 98.8),  // stop at 99
        ]
        let report = CandleStopBot.backtest(candles: candles, symbol: "BTCUSDT", config: config)
        XCTAssertEqual(report.trades.count, 1)
        XCTAssertEqual(report.trades[0].reason, .stop)
        XCTAssertEqual(report.netProfit, -2, accuracy: 1e-9)
        // None after bar 1 while the position was open; bar 0 and bar 2 place two each.
        XCTAssertEqual(report.ordersPlaced, 4)
    }
}

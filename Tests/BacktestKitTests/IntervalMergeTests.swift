import Foundation
import XCTest
@testable import BacktestKit

/// 2m, 4m, 6m, 10m, 12m and 20m bars: Binance has no such klines, so they are built from 1m / 3m / 5m ones.
final class IntervalMergeTests: XCTestCase {
    private func minute(_ i: Int, _ o: Double, _ h: Double, _ l: Double, _ c: Double, v: Double = 1) -> Candle {
        Candle(time: Date(timeIntervalSince1970: Double(i) * 60), open: o, high: h, low: l, close: c, volume: v)
    }

    func testIntervalsAndTheirKlines() {
        XCTAssertEqual(BinanceClient.Interval.m2.seconds, 120)
        XCTAssertEqual(BinanceClient.Interval.m20.seconds, 1200)
        XCTAssertEqual(BinanceClient.Interval.m6.binanceKline.name, "3m")
        XCTAssertEqual(BinanceClient.Interval.m6.binanceKline.factor, 2)
        XCTAssertEqual(BinanceClient.Interval.m10.binanceKline.name, "5m")
        XCTAssertEqual(BinanceClient.Interval.m3.binanceKline.factor, 1)
        XCTAssertEqual(BinanceClient.Interval(rawValue: "4m"), .m4)
        XCTAssertEqual(OandaClient.granularity(.m10), "M10")
        XCTAssertEqual(OandaClient.mergedFromM1(.m6), 6)
        XCTAssertNil(OandaClient.mergedFromM1(.m4))
        // Every bar length divides a day: the bars line up with midnight.
        for interval in BinanceClient.Interval.allCases where interval.seconds <= 86_400 {
            XCTAssertEqual(86_400.truncatingRemainder(dividingBy: interval.seconds), 0, interval.rawValue)
        }
    }

    func testHistoryMergedAndAPartialFirstBarDropped() {
        // 1m bars from minute 1 to 8: the 2m bar at minute 0 is missing its first minute.
        let bars = (1...8).map { minute($0, Double($0), Double($0) + 0.5, Double($0) - 0.5, Double($0) + 0.2) }
        let merged = BinanceClient.merged(bars, interval: .m2, count: 10)
        XCTAssertEqual(merged.map { $0.time.timeIntervalSince1970 }, [120, 240, 360, 480])
        XCTAssertEqual(merged[0].open, 2)
        XCTAssertEqual(merged[0].close, 3.2)
        XCTAssertEqual(merged[0].high, 3.5)
        XCTAssertEqual(merged[0].low, 1.5)
        XCTAssertEqual(merged[0].volume, 2)
        XCTAssertEqual(BinanceClient.merged(bars, interval: .m2, count: 2).count, 2)
    }

    func testLiveKlinesMergeWithoutCountingAMinuteTwice() {
        var merger = KlineMerger(seconds: 240)
        // The forming 1m bar is sent again and again as it grows.
        var bar = merger.add(minute(0, 10, 11, 9, 10.5, v: 1), last: nil)
        bar = merger.add(minute(0, 10, 12, 9, 11, v: 2), last: bar)
        XCTAssertEqual(bar.volume, 2)
        bar = merger.add(minute(1, 11, 11.5, 8, 9, v: 3), last: bar)
        XCTAssertEqual(bar.time.timeIntervalSince1970, 0)
        XCTAssertEqual(bar.open, 10)
        XCTAssertEqual(bar.high, 12)
        XCTAssertEqual(bar.low, 8)
        XCTAssertEqual(bar.close, 9)
        XCTAssertEqual(bar.volume, 5)
        // The next 4m bar starts fresh.
        bar = merger.add(minute(4, 9, 9.5, 8.5, 9.2, v: 1), last: bar)
        XCTAssertEqual(bar.time.timeIntervalSince1970, 240)
        XCTAssertEqual(bar.open, 9)
        XCTAssertEqual(bar.volume, 1)
    }

    func testStreamAsksForTheShorterKline() {
        let url = BinanceStreamEvent.url(host: URL(string: "wss://stream.binance.com:9443")!, symbol: "BTCUSDT", interval: .m10)
        XCTAssertTrue(url.absoluteString.contains("btcusdt@kline_5m"))
    }
}

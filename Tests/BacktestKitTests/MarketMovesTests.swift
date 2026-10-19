import XCTest
@testable import BacktestKit

final class MarketMovesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    /// 1-minute bars wobbling ±$1 around 4000, with a +$30 jump over bars 100–103.
    private func bars() -> [Candle] {
        var price = 4000.0
        return (0..<200).map { i in
            price += (i % 2 == 0 ? 1 : -1)
            if (100...103).contains(i) { price += 7.5 }
            return Candle(time: t0.addingTimeInterval(Double(i) * 60), open: price, high: price + 0.5,
                          low: price - 0.5, close: price)
        }
    }

    func testFindsTheJumpOnce() {
        let spikes = MarketMoves.spikes(bars())
        XCTAssertEqual(spikes.count, 1)
        let spike = spikes[0]
        XCTAssertTrue(spike.isUp)
        XCTAssertGreaterThan(spike.change, 25)
        XCTAssertTrue(spike.start <= t0.addingTimeInterval(100 * 60))
        XCTAssertTrue(spike.end >= t0.addingTimeInterval(103 * 60))
    }

    func testQuietMarketHasNoSpikes() {
        var price = 4000.0
        let calm = (0..<200).map { i -> Candle in
            price += (i % 3 == 0 ? 0.8 : -0.4)
            return Candle(time: t0.addingTimeInterval(Double(i) * 60), open: price, high: price, low: price, close: price)
        }
        XCTAssertTrue(MarketMoves.spikes(calm).isEmpty)
    }

    func testClassifiesHeadlines() {
        XCTAssertEqual(NewsCategory.classify("Iran launches missiles at Israel"), .geopolitics)
        XCTAssertEqual(NewsCategory.classify("Trump announces new tariffs on China"), .trade)
        XCTAssertEqual(NewsCategory.classify("Powell says Fed in no hurry to cut"), .centralBank)
        XCTAssertEqual(NewsCategory.classify("Giá vàng tăng vọt khi xung đột Trung Đông leo thang"), .geopolitics)
        XCTAssertEqual(NewsCategory.classify("Dollar slides as Treasury yields fall"), .dollar)
        // Whole words only: "federal" is not "fed", "warning" is not "war".
        XCTAssertNil(NewsCategory.classify("Federal holiday warning for travellers"))
    }

    func testExplainsWithCalendarOrHeadlines() {
        let spike = MarketMoves.spikes(bars())[0]
        let cpi = EconomicEvent(title: "CPI m/m", country: "USD", date: spike.start, impact: .high, forecast: "", previous: "")
        let war = NewsHeadline(title: "Explosions reported as Israel strikes Iran", link: "a", source: "Reuters",
                               date: spike.start.addingTimeInterval(5 * 60))
        let old = NewsHeadline(title: "Iran talks resume", link: "b", source: "AP", date: spike.start.addingTimeInterval(-6 * 3600))
        let byNews = MarketMoves.explain([spike], events: [], headlines: [war, old])[0]
        XCTAssertEqual(byNews.cause, .geopolitics)
        XCTAssertEqual(byNews.headlines.map(\.headline.link), ["a"])
        let byData = MarketMoves.explain([spike], events: [cpi], headlines: [war])[0]
        XCTAssertEqual(byData.cause, .economic)
        XCTAssertNil(MarketMoves.explain([spike], events: [], headlines: [old])[0].cause)
    }
}

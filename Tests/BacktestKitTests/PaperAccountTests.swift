import XCTest
@testable import BacktestKit

final class PaperAccountTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 0)

    func testMarketLongHitsTarget() {
        var account = PaperAccount(startingBalance: 1000)
        account.openMarket(symbol: "XAUUSDT", side: .long, lots: 0.1, price: 4000, stop: 3990, target: 4020, time: t)
        XCTAssertTrue(account.process(symbol: "XAUUSDT", price: 4010, time: t).isEmpty)
        XCTAssertEqual(account.equity { _ in 4010 }, 1100, accuracy: 1e-9)   // 10 × 0.1 lot × 100 oz
        let events = account.process(symbol: "XAUUSDT", price: 4021, time: t)
        guard case .closed(let trade)? = events.first else { return XCTFail() }
        XCTAssertEqual(trade.reason, .target)
        XCTAssertEqual(trade.exitPrice, 4020)
        XCTAssertEqual(trade.profit, 200, accuracy: 1e-9)
        XCTAssertEqual(account.balance, 1200, accuracy: 1e-9)
        XCTAssertTrue(account.positions.isEmpty)
    }

    func testShortStopAndOtherSymbolsIgnored() {
        var account = PaperAccount()
        account.openMarket(symbol: "EURUSD", side: .short, lots: 1, price: 1.1000, stop: 1.1010, target: 1.0950, time: t)
        XCTAssertTrue(account.process(symbol: "XAUUSDT", price: 5, time: t).isEmpty)
        guard case .closed(let trade)? = account.process(symbol: "EURUSD", price: 1.1012, time: t).first else { return XCTFail() }
        XCTAssertEqual(trade.reason, .stop)
        XCTAssertEqual(trade.profit, -100, accuracy: 1e-6)    // 10 pips × 100 000
    }

    func testPendingOrdersFillAtEntry() {
        var account = PaperAccount()
        // Buy limit below the market and sell stop below the market.
        account.placePending(symbol: "XAUUSDT", side: .long, lots: 0.01, entry: 3995, stop: 3990, target: 4005,
                             currentPrice: 4000, time: t)
        account.placePending(symbol: "XAUUSDT", side: .short, lots: 0.01, entry: 3980, stop: 3990, target: 3970,
                             currentPrice: 4000, time: t)
        let first = account.process(symbol: "XAUUSDT", price: 3994, time: t)
        XCTAssertEqual(first.count, 1)
        guard case .opened(let position)? = first.first else { return XCTFail() }
        XCTAssertEqual(position.entryPrice, 3995)
        XCTAssertEqual(account.pending.count, 1)
        let second = account.process(symbol: "XAUUSDT", price: 3979, time: t)
        // The short fills; the long's stop (3990) is hit by the same price.
        XCTAssertEqual(second.count, 2)
        XCTAssertTrue(account.pending.isEmpty)
        XCTAssertEqual(account.positions.count, 1)
        XCTAssertEqual(account.history.first?.reason, .stop)
    }

    func testContractSizes() {
        XCTAssertEqual(PaperAccount.contractSize(for: "XAU_USD"), 100)
        XCTAssertEqual(PaperAccount.contractSize(for: "XAGUSDT"), 5000)
        XCTAssertEqual(PaperAccount.contractSize(for: "EUR_USD"), 100_000)
        XCTAssertEqual(PaperAccount.contractSize(for: "BTCUSDT"), 1)
    }

    func testModifyPendingFlipsTrigger() {
        var account = PaperAccount()
        let order = account.placePending(symbol: "XAUUSDT", side: .short, lots: 0.1, entry: 4010, stop: 4020, target: 3990,
                                         currentPrice: 4000, time: t)
        XCTAssertTrue(order.triggersAbove)   // sell limit above the market
        account.modifyPending(orderID: order.id, entry: 3995, stop: 4005, target: 3980, currentPrice: 4000)
        XCTAssertEqual(account.pending.first?.triggersAbove, false)   // now a sell stop
        XCTAssertEqual(account.pending.first?.stop, 4005)
        XCTAssertTrue(account.process(symbol: "XAUUSDT", price: 3996, time: t).isEmpty)
        XCTAssertEqual(account.process(symbol: "XAUUSDT", price: 3994, time: t).count, 1)
    }
}

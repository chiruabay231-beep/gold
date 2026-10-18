import XCTest
@testable import BacktestKit

final class TradeManagementTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 0)

    func testStopMovesToLockAtTwoR() {
        var account = PaperAccount()
        account.openMarket(symbol: "X", side: .long, lots: 1, price: 100, stop: 95, target: nil, time: t)
        var rules = TradeManagement()
        rules.triggerR = 2
        rules.lockR = 1
        _ = account.process(symbol: "X", price: 108, time: t)   // 1.6R: nothing yet
        XCTAssertTrue(account.manage(symbol: "X", price: 108, time: t, rules: rules).isEmpty)
        _ = account.process(symbol: "X", price: 110.5, time: t) // 2.1R
        let events = account.manage(symbol: "X", price: 110.5, time: t, rules: rules)
        guard case .stopMoved(let p)? = events.first else { return XCTFail() }
        XCTAssertEqual(p.stop, 105)        // +1R locked
        XCTAssertEqual(p.initialStop, 95)  // 1R stays the original risk
        // Not moved again at the same level.
        XCTAssertTrue(account.manage(symbol: "X", price: 110.5, time: t, rules: rules).isEmpty)
        // Price comes back: stopped out in profit.
        guard case .closed(let trade)? = account.process(symbol: "X", price: 104, time: t).first else { return XCTFail() }
        XCTAssertEqual(trade.exitPrice, 105)
        XCTAssertGreaterThan(trade.profit, 0)
    }

    func testStepTrailingForShorts() {
        var account = PaperAccount()
        account.openMarket(symbol: "X", side: .short, lots: 1, price: 100, stop: 102, target: nil, time: t)
        var rules = TradeManagement()
        rules.triggerR = 2; rules.lockR = 0; rules.trailStepR = 1
        _ = account.process(symbol: "X", price: 93.5, time: t)  // 3.25R
        _ = account.manage(symbol: "X", price: 93.5, time: t, rules: rules)
        XCTAssertEqual(account.positions.first?.stop, 98)       // lock 0 + 1 step = 1R
    }

    func testCloseOnEngulfingOnlyInProfit() {
        var rules = TradeManagement()
        rules.closeOnReversal = true
        rules.reversalStructure = false
        rules.minProfitR = 1
        let bull = Candle(time: t.addingTimeInterval(60), open: 109, high: 112, low: 108.5, close: 111)
        let bearEngulf = Candle(time: t.addingTimeInterval(120), open: 111.5, high: 112, low: 107, close: 108)
        var account = PaperAccount()
        account.openMarket(symbol: "X", side: .long, lots: 1, price: 100, stop: 95, target: nil, time: t)
        let events = account.manage(symbol: "X", price: 108, time: t, rules: rules, closed: [bull, bearEngulf])
        guard case .closed(let trade)? = events.first else { return XCTFail() }
        XCTAssertEqual(trade.reason, .reversal)
        // In loss (below +1R) the same candle does not close the trade.
        var losing = PaperAccount()
        losing.openMarket(symbol: "X", side: .long, lots: 1, price: 107, stop: 102, target: nil, time: t)
        XCTAssertTrue(losing.manage(symbol: "X", price: 108, time: t, rules: rules, closed: [bull, bearEngulf]).isEmpty)
    }

    func testGiveback() {
        var rules = TradeManagement()
        rules.moveStop = false
        rules.closeOnReversal = true
        rules.reversalStructure = false
        rules.reversalEngulfing = false
        rules.givebackPercent = 50
        rules.minProfitR = 0.5
        var account = PaperAccount()
        account.openMarket(symbol: "X", side: .long, lots: 1, price: 100, stop: 90, target: nil, time: t)
        _ = account.process(symbol: "X", price: 120, time: t)   // peak +20
        let bar = [Candle(time: t.addingTimeInterval(60), open: 112, high: 112, low: 109, close: 109)]
        XCTAssertFalse(account.manage(symbol: "X", price: 109, time: t, rules: rules, closed: bar).isEmpty)  // +9 ≤ 50% of 20
    }
}

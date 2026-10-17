import XCTest
@testable import BacktestKit

final class EngineTests: XCTestCase {
    private let noCost = BacktestConfig(initialCapital: 1000, sizingMode: .fixedQuantity, sizingValue: 1,
                                        commissionPercent: 0)

    func testFillsAtNextOpen() {
        let data = makeData([(10, 11, 9, 10), (12, 13, 11, 12), (13, 15, 12, 14), (15, 16, 14, 15), (16, 17, 15, 16)])
        let signals = StrategySignals(longEntry: [1, 0, 0, 0, 0], longExit: [0, 0, 1, 0, 0])
        let result = BacktestEngine.run(signals: signals, data: data, config: noCost)
        XCTAssertEqual(result.trades.count, 1)
        let trade = result.trades[0]
        XCTAssertEqual(trade.entryIndex, 1)
        XCTAssertEqual(trade.entryPrice, 12)     // open of bar 1
        XCTAssertEqual(trade.exitIndex, 3)
        XCTAssertEqual(trade.exitPrice, 15)      // open of bar 3
        XCTAssertEqual(trade.profit, 3)
        XCTAssertEqual(trade.exitReason, .signal)
        XCTAssertEqual(result.metrics.finalEquity, 1003)
        XCTAssertEqual(result.equity[2], 1002)   // marked at close 14
    }

    func testStopLossHitsFirstWhenBothTouched() {
        let data = makeData([(10, 10, 10, 10), (10, 10.5, 9.5, 10), (10, 13, 7, 10), (10, 10, 10, 10)])
        let signals = StrategySignals(longEntry: [1, 0, 0, 0], longStop: [8, 8, 8, 8], longTarget: [12, 12, 12, 12])
        let result = BacktestEngine.run(signals: signals, data: data, config: noCost)
        XCTAssertEqual(result.trades.count, 1)
        XCTAssertEqual(result.trades[0].exitReason, .stopLoss)
        XCTAssertEqual(result.trades[0].exitPrice, 8)
        XCTAssertEqual(result.trades[0].profit, -2)
    }

    func testTakeProfitAndGap() {
        let data = makeData([(10, 10, 10, 10), (10, 10.5, 9.5, 10), (14, 15, 13.5, 14.5), (14, 14, 14, 14)])
        let signals = StrategySignals(longEntry: [1, 0, 0, 0], longTarget: [12, 12, 12, 12])
        let result = BacktestEngine.run(signals: signals, data: data, config: noCost)
        // Gapped above the target: filled at the open, not the target.
        XCTAssertEqual(result.trades[0].exitReason, .takeProfit)
        XCTAssertEqual(result.trades[0].exitPrice, 14)
    }

    func testShortAndReverse() {
        let data = makeData([(10, 10, 10, 10), (10, 10, 10, 10), (8, 8, 8, 8), (8, 8, 8, 8), (11, 11, 11, 11), (11, 11, 11, 11)])
        let signals = StrategySignals(longEntry: [0, 0, 1, 0, 0, 0], shortEntry: [1, 0, 0, 0, 0, 0])
        let result = BacktestEngine.run(signals: signals, data: data, config: noCost)
        XCTAssertEqual(result.trades.count, 2)
        XCTAssertEqual(result.trades[0].direction, .short)
        XCTAssertEqual(result.trades[0].profit, 2)          // sold 10, bought back 8
        XCTAssertEqual(result.trades[0].exitReason, .reverse)
        XCTAssertEqual(result.trades[1].direction, .long)
        XCTAssertEqual(result.trades[1].entryPrice, 8)
        XCTAssertEqual(result.trades[1].exitReason, .endOfData)
        XCTAssertEqual(result.trades[1].profit, 3)
    }

    func testCommissionSlippageAndSizing() {
        let data = makeData([(100, 100, 100, 100), (100, 100, 100, 100), (110, 110, 110, 110), (110, 110, 110, 110)])
        let signals = StrategySignals(longEntry: [1, 0, 0, 0], longExit: [0, 1, 0, 0])
        let config = BacktestConfig(initialCapital: 1000, sizingMode: .percentOfEquity, sizingValue: 50,
                                    commissionPercent: 0.1, slippage: 1)
        let trade = BacktestEngine.run(signals: signals, data: data, config: config).trades[0]
        XCTAssertEqual(trade.entryPrice, 101)
        XCTAssertEqual(trade.exitPrice, 109)
        XCTAssertEqual(trade.quantity, 500 / 101, accuracy: 1e-9)
        let commission = (101 + 109) * trade.quantity * 0.001
        XCTAssertEqual(trade.commission, commission, accuracy: 1e-9)
        XCTAssertEqual(trade.profit, 8 * trade.quantity - commission, accuracy: 1e-9)
    }

    func testRiskPercentSizing() {
        let data = makeData([(100, 100, 100, 100), (100, 101, 99, 100), (100, 100, 100, 100)])
        let signals = StrategySignals(longEntry: [1, 0, 0], longStop: [95, 95, 95])
        let config = BacktestConfig(initialCapital: 10_000, sizingMode: .riskPercent, sizingValue: 1, commissionPercent: 0)
        let trade = BacktestEngine.run(signals: signals, data: data, config: config).trades[0]
        XCTAssertEqual(trade.quantity, 100 / 5, accuracy: 1e-9)   // risk $100 over $5
        XCTAssertEqual(trade.rMultiple ?? .nan, 0, accuracy: 1e-9)

        let noStop = BacktestEngine.run(signals: StrategySignals(longEntry: [1, 0, 0]), data: data, config: config)
        XCTAssertTrue(noStop.trades.isEmpty)
        XCTAssertFalse(noStop.warnings.isEmpty)
    }

    func testPercentStopFallbackAndDisabledShorts() {
        let data = makeData([(100, 100, 100, 100), (100, 100, 100, 100), (100, 100, 89, 90), (90, 90, 90, 90)])
        var config = noCost
        config.stopLossPercent = 5
        let result = BacktestEngine.run(signals: StrategySignals(longEntry: [1, 0, 0, 0]), data: data, config: config)
        XCTAssertEqual(result.trades[0].exitPrice, 95)
        config.allowShort = false
        let shorts = BacktestEngine.run(signals: StrategySignals(shortEntry: [1, 0, 0, 0]), data: data, config: config)
        XCTAssertTrue(shorts.trades.isEmpty)
    }

    func testTradingStartIgnoresEarlierSignals() {
        let data = makeData(closes: [10, 10, 11, 12, 13, 14, 15])
        let signals = StrategySignals(longEntry: [1, 0, 0, 1, 0, 0, 0])
        let result = BacktestEngine.run(signals: signals, data: data, config: noCost, tradingStart: 2)
        XCTAssertEqual(result.trades.count, 1)
        XCTAssertEqual(result.trades[0].entryIndex, 4)
        XCTAssertEqual(result.startIndex, 2)
        XCTAssertEqual(result.equity.count, 5)
        XCTAssertEqual(result.metrics.buyAndHoldPercent, 100 * (15.0 / 11 - 1), accuracy: 1e-9)
    }

    func testMetrics() {
        let data = makeData([(10, 10, 10, 10), (10, 10, 10, 10), (12, 12, 12, 12), (12, 12, 12, 12), (11, 11, 11, 11), (11, 11, 11, 11)])
        let signals = StrategySignals(longEntry: [1, 0, 1, 0, 0, 0], longExit: [0, 1, 0, 0, 0, 0])
        let m = BacktestEngine.run(signals: signals, data: data, config: noCost).metrics
        XCTAssertEqual(m.totalTrades, 2)
        XCTAssertEqual(m.winningTrades, 1)
        XCTAssertEqual(m.grossProfit, 2)
        XCTAssertEqual(m.grossLoss, 1)
        XCTAssertEqual(m.profitFactor, 2)
        XCTAssertEqual(m.winRate, 50)
        XCTAssertEqual(m.netProfit, 1)
        XCTAssertEqual(m.maxDrawdown, 1)
        XCTAssertEqual(m.buyAndHoldPercent, 10, accuracy: 1e-9)
    }

    func testStrategyScriptEndToEnd() throws {
        let data = PriceData(candles: SampleData.candles(count: 1500))
        let strategy = Samples.strategies[0]
        let result = try BacktestEngine.run(strategy: strategy, data: data)
        XCTAssertGreaterThan(result.trades.count, 5)
        XCTAssertEqual(result.plots.count, 2)
        for trade in result.trades {
            XCTAssertGreaterThan(trade.entryIndex, 0)
            XCTAssertGreaterThanOrEqual(trade.exitIndex, trade.entryIndex)
        }
        // Equity at the end equals initial capital plus the sum of trade profits.
        let total = result.trades.reduce(0) { $0 + $1.profit }
        XCTAssertEqual(result.metrics.finalEquity, 10_000 + total, accuracy: 1e-6)
    }

    func testStrategyNeedsEntry() {
        let bad = StrategyDefinition(name: "x", script: "a = close")
        XCTAssertThrowsError(try bad.validate())
        XCTAssertThrowsError(try BacktestEngine.run(strategy: bad, data: makeData(closes: [1, 2, 3])))
    }

    func testOptimizer() {
        let data = PriceData(candles: SampleData.candles(count: 800))
        let ranges = [Optimizer.Range(name: "fast_len", from: 5, to: 9, step: 2),
                      Optimizer.Range(name: "slow_len", from: 20, to: 30, step: 10)]
        XCTAssertEqual(Optimizer.combinations(ranges).count, 6)
        let runs = Optimizer.run(strategy: Samples.strategies[0], data: data, config: BacktestConfig(),
                                 ranges: ranges, objective: .netProfit)
        XCTAssertEqual(runs.count, 6)
        XCTAssertGreaterThanOrEqual(runs[0].score, runs[5].score)
    }
}

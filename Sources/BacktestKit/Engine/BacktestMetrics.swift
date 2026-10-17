import Foundation

public struct BacktestMetrics: Codable, Hashable, Sendable {
    public var initialCapital: Double
    public var finalEquity: Double
    public var netProfit: Double
    public var netProfitPercent: Double
    public var grossProfit: Double
    public var grossLoss: Double
    /// Gross profit / gross loss; `.infinity` when nothing lost.
    public var profitFactor: Double
    public var totalTrades: Int
    public var winningTrades: Int
    public var losingTrades: Int
    public var winRate: Double
    public var averageTrade: Double
    public var averageWin: Double
    public var averageLoss: Double
    public var largestWin: Double
    public var largestLoss: Double
    public var maxConsecutiveLosses: Int
    public var averageBarsHeld: Double
    /// Largest peak-to-trough fall of equity, in money and in percent.
    public var maxDrawdown: Double
    public var maxDrawdownPercent: Double
    public var sharpeRatio: Double
    public var sortinoRatio: Double
    /// Compound annual growth rate, in percent.
    public var cagr: Double
    public var buyAndHoldPercent: Double
    /// Share of bars with an open position, in percent.
    public var exposurePercent: Double
    public var totalCommission: Double
    public var averageR: Double?

    public init(trades: [Trade], equity: Series, drawdown: Series, data: PriceData, config: BacktestConfig) {
        initialCapital = config.initialCapital
        finalEquity = equity.last ?? config.initialCapital
        netProfit = finalEquity - initialCapital
        netProfitPercent = initialCapital == 0 ? 0 : 100 * netProfit / initialCapital

        let wins = trades.filter(\.isWin)
        let losses = trades.filter { !$0.isWin }
        grossProfit = wins.reduce(0) { $0 + $1.profit }
        grossLoss = -losses.reduce(0) { $0 + $1.profit }
        profitFactor = grossLoss == 0 ? (grossProfit > 0 ? .infinity : 0) : grossProfit / grossLoss
        totalTrades = trades.count
        winningTrades = wins.count
        losingTrades = losses.count
        winRate = trades.isEmpty ? 0 : 100 * Double(wins.count) / Double(trades.count)
        averageTrade = trades.isEmpty ? 0 : (grossProfit - grossLoss) / Double(trades.count)
        averageWin = wins.isEmpty ? 0 : grossProfit / Double(wins.count)
        averageLoss = losses.isEmpty ? 0 : -grossLoss / Double(losses.count)
        largestWin = wins.map(\.profit).max() ?? 0
        largestLoss = losses.map(\.profit).min() ?? 0
        var streak = 0
        var worst = 0
        for trade in trades {
            streak = trade.isWin ? 0 : streak + 1
            worst = max(worst, streak)
        }
        maxConsecutiveLosses = worst
        averageBarsHeld = trades.isEmpty ? 0 : Double(trades.reduce(0) { $0 + $1.barsHeld }) / Double(trades.count)
        totalCommission = trades.reduce(0) { $0 + $1.commission }
        let rs = trades.compactMap(\.rMultiple)
        averageR = rs.isEmpty ? nil : rs.reduce(0, +) / Double(rs.count)

        var peak = -Double.infinity
        var deepest = 0.0
        for value in equity {
            peak = max(peak, value)
            deepest = max(deepest, peak - value)
        }
        maxDrawdown = deepest
        maxDrawdownPercent = -(drawdown.min() ?? 0)

        var returns: [Double] = []
        returns.reserveCapacity(equity.count)
        for i in stride(from: 1, to: equity.count, by: 1) where equity[i - 1] > 0 {
            returns.append(equity[i] / equity[i - 1] - 1)
        }
        let interval = data.medianBarInterval
        let barsPerYear = interval > 0 ? 365.25 * 86_400 / interval : 252
        let mean = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)
        let variance = returns.isEmpty ? 0 : returns.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(returns.count)
        let downside = returns.isEmpty ? 0 : returns.reduce(0) { $0 + min($1, 0) * min($1, 0) } / Double(returns.count)
        sharpeRatio = variance > 0 ? mean / variance.squareRoot() * barsPerYear.squareRoot() : 0
        sortinoRatio = downside > 0 ? mean / downside.squareRoot() * barsPerYear.squareRoot() : 0

        if let first = data.time.first, let last = data.time.last, initialCapital > 0, finalEquity > 0 {
            let years = last.timeIntervalSince(first) / (365.25 * 86_400)
            cagr = years > 0 ? 100 * (pow(finalEquity / initialCapital, 1 / years) - 1) : 0
        } else {
            cagr = finalEquity <= 0 ? -100 : 0
        }

        if let first = data.close.first, let last = data.close.last, first != 0 {
            buyAndHoldPercent = 100 * (last / first - 1)
        } else {
            buyAndHoldPercent = 0
        }

        let barsInMarket = trades.reduce(0) { $0 + max(1, $1.barsHeld) }
        exposurePercent = data.count == 0 ? 0 : min(100, 100 * Double(barsInMarket) / Double(data.count))
    }
}

import Foundation

public struct BacktestResult: Sendable {
    public var config: BacktestConfig
    public var trades: [Trade]
    /// First bar where trading was allowed. `equity` and `drawdown` start
    /// here; trade indices refer to the full data set.
    public var startIndex: Int
    /// Mark-to-market equity at every bar's close from `startIndex` on.
    public var equity: Series
    /// Drawdown from the running equity peak at every bar, in percent (≤ 0).
    public var drawdown: Series
    public var metrics: BacktestMetrics
    /// Lines the strategy plotted, for charting.
    public var plots: [Plot]
    public var warnings: [String]
}

/// Bar-by-bar simulation of a single position (long, short or flat).
///
/// Execution model:
/// - Signals are read at the close of bar `i` and filled at the open of bar `i + 1`.
/// - Stops and targets are checked against each bar's high/low, starting with
///   the entry bar. If both are touched in the same bar the stop is assumed to
///   fill first. A gap through the level fills at the open.
/// - An entry in the opposite direction closes the current position and opens
///   the new one at the same price.
/// - Any open position is closed at the last bar's close.
public enum BacktestEngine {
    public static func run(strategy: StrategyDefinition,
                           data: PriceData,
                           config: BacktestConfig = BacktestConfig(),
                           library: FunctionLibrary = .standard,
                           parameterValues: [String: Double] = [:],
                           tradingStart: Int = 0) throws -> BacktestResult {
        let context = EvaluationContext(data: data, library: library, timeZone: config.timeZone)
        let signals = try strategy.signals(context: context, values: parameterValues)
        return run(signals: signals, data: data, config: config, tradingStart: tradingStart)
    }

    private struct Position {
        var direction: TradeDirection
        var quantity: Double
        var entryIndex: Int
        var entryPrice: Double
        var entryCommission: Double
        var stop: Double?
        var target: Double?
    }

    private enum Order {
        case enter(TradeDirection, signalIndex: Int)
        case exit
        case reverse(TradeDirection, signalIndex: Int)
    }

    /// Bars before `tradingStart` are only used to warm up indicators; no
    /// signal before it is acted on and metrics cover the rest.
    public static func run(signals: StrategySignals, data: PriceData, config: BacktestConfig,
                           tradingStart: Int = 0) -> BacktestResult {
        let n = data.count
        let start = min(max(0, tradingStart), max(0, n - 1))
        var balance = config.initialCapital
        var position: Position?
        var pending: Order?
        var trades: [Trade] = []
        var equity = Series(repeating: config.initialCapital, count: n)
        var warnings = Set<String>()

        func flag(_ series: Series?, _ i: Int) -> Bool { series.map { $0[i].isTruthy } ?? false }
        func level(_ series: Series?, _ i: Int) -> Double? {
            guard let v = series?[i], v.isFinite, v > 0 else { return nil }
            return v
        }
        func commission(_ price: Double, _ quantity: Double) -> Double {
            price * quantity * config.commissionPercent / 100 + config.commissionPerTrade
        }

        func close(at rawPrice: Double, index: Int, reason: ExitReason, applySlippage: Bool = true) {
            guard let p = position else { return }
            let price = applySlippage ? rawPrice - p.direction.sign * config.slippage : rawPrice
            let exitCommission = commission(price, p.quantity)
            let gross = p.direction.sign * (price - p.entryPrice) * p.quantity
            balance += gross - exitCommission
            trades.append(Trade(id: trades.count + 1, direction: p.direction,
                                entryIndex: p.entryIndex, entryTime: data.time[p.entryIndex], entryPrice: p.entryPrice,
                                exitIndex: index, exitTime: data.time[index], exitPrice: price,
                                quantity: p.quantity, stopPrice: p.stop, targetPrice: p.target,
                                commission: p.entryCommission + exitCommission,
                                profit: gross - p.entryCommission - exitCommission,
                                exitReason: reason))
            position = nil
        }

        func open(_ direction: TradeDirection, at index: Int, signalIndex: Int) {
            guard balance > 0 else {
                warnings.insert("Tài khoản đã hết vốn, ngừng mở lệnh mới.")
                return
            }
            let price = data.open[index] + direction.sign * config.slippage
            var stop = direction == .long ? level(signals.longStop, signalIndex) : level(signals.shortStop, signalIndex)
            var target = direction == .long ? level(signals.longTarget, signalIndex) : level(signals.shortTarget, signalIndex)
            if stop == nil, let percent = config.stopLossPercent, percent > 0 {
                stop = price * (1 - direction.sign * percent / 100)
            }
            if target == nil, let percent = config.takeProfitPercent, percent > 0 {
                target = price * (1 + direction.sign * percent / 100)
            }
            // A level on the wrong side of the fill price cannot work; drop it.
            if let s = stop, direction.sign * (price - s) <= 0 { stop = nil }
            if let t = target, direction.sign * (t - price) <= 0 { target = nil }

            let quantity: Double
            switch config.sizingMode {
            case .percentOfEquity:
                quantity = balance * config.sizingValue / 100 / price
            case .fixedQuantity:
                quantity = config.sizingValue
            case .fixedCash:
                quantity = config.sizingValue / price
            case .riskPercent:
                guard let s = stop else {
                    warnings.insert("Chế độ rủi ro % cần giá cắt lỗ; các tín hiệu không có cắt lỗ đã bị bỏ qua.")
                    return
                }
                quantity = balance * config.sizingValue / 100 / abs(price - s)
            }
            guard quantity.isFinite, quantity > 0 else { return }
            let entryCommission = commission(price, quantity)
            balance -= entryCommission
            position = Position(direction: direction, quantity: quantity, entryIndex: index, entryPrice: price,
                                entryCommission: entryCommission, stop: stop, target: target)
        }

        for i in 0..<n {
            // 1. Fill the order decided at the previous close.
            if let order = pending {
                pending = nil
                switch order {
                case .exit:
                    close(at: data.open[i], index: i, reason: .signal)
                case .enter(let direction, let signalIndex):
                    open(direction, at: i, signalIndex: signalIndex)
                case .reverse(let direction, let signalIndex):
                    close(at: data.open[i], index: i, reason: .reverse)
                    open(direction, at: i, signalIndex: signalIndex)
                }
            }

            // 2. Stops and targets inside the bar.
            if let p = position {
                let isLong = p.direction == .long
                let open = data.open[i]
                if let stop = p.stop, isLong ? data.low[i] <= stop : data.high[i] >= stop {
                    let gapped = isLong ? open < stop : open > stop
                    close(at: gapped && i > p.entryIndex ? open : stop, index: i, reason: .stopLoss, applySlippage: true)
                } else if let target = p.target, isLong ? data.high[i] >= target : data.low[i] <= target {
                    let gapped = isLong ? open > target : open < target
                    close(at: gapped && i > p.entryIndex ? open : target, index: i, reason: .takeProfit, applySlippage: false)
                }
            }

            // 3. Signals at this bar's close, executed on the next bar.
            if i < n - 1, i >= start {
                let wantLong = config.allowLong && flag(signals.longEntry, i)
                let wantShort = config.allowShort && flag(signals.shortEntry, i)
                if let p = position {
                    if p.direction == .long {
                        if wantShort && !wantLong {
                            pending = .reverse(.short, signalIndex: i)
                        } else if flag(signals.longExit, i) {
                            pending = .exit
                        }
                    } else {
                        if wantLong && !wantShort {
                            pending = .reverse(.long, signalIndex: i)
                        } else if flag(signals.shortExit, i) {
                            pending = .exit
                        }
                    }
                } else if wantLong != wantShort {
                    pending = .enter(wantLong ? .long : .short, signalIndex: i)
                }
            }

            // 4. Mark to market.
            if let p = position {
                equity[i] = balance + p.direction.sign * (data.close[i] - p.entryPrice) * p.quantity
            } else {
                equity[i] = balance
            }
        }

        if position != nil, n > 0 {
            close(at: data.close[n - 1], index: n - 1, reason: .endOfData, applySlippage: false)
            equity[n - 1] = balance
        }

        let tradedEquity = n > 0 ? Array(equity[start...]) : []
        let tradedData = n > 0 && start > 0 ? data.slice(start..<n) : data
        let drawdown = Self.drawdown(tradedEquity)
        let metrics = BacktestMetrics(trades: trades, equity: tradedEquity, drawdown: drawdown, data: tradedData, config: config)
        return BacktestResult(config: config, trades: trades, startIndex: start, equity: tradedEquity, drawdown: drawdown,
                              metrics: metrics, plots: signals.plots, warnings: warnings.sorted())
    }

    static func drawdown(_ equity: Series) -> Series {
        var peak = -Double.infinity
        return equity.map { value in
            peak = max(peak, value)
            return peak > 0 ? 100 * (value - peak) / peak : 0
        }
    }
}

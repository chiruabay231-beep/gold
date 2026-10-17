import Foundation

/// Grid search over strategy parameters.
public enum Optimizer {
    public struct Range: Hashable, Sendable {
        public var name: String
        public var from: Double
        public var to: Double
        public var step: Double

        public init(name: String, from: Double, to: Double, step: Double) {
            self.name = name
            self.from = from
            self.to = to
            self.step = step
        }

        public var values: [Double] {
            guard step > 0, to >= from else { return [from] }
            var out: [Double] = []
            var v = from
            while v <= to + step * 1e-9 {
                out.append((v * 1e9).rounded() / 1e9)
                v += step
            }
            return out
        }
    }

    public enum Objective: String, CaseIterable, Codable, Sendable {
        case netProfit, profitFactor, sharpe, winRate, returnOverDrawdown

        public var label: String {
            switch self {
            case .netProfit: return "Lợi nhuận ròng"
            case .profitFactor: return "Profit factor"
            case .sharpe: return "Sharpe"
            case .winRate: return "Tỉ lệ thắng"
            case .returnOverDrawdown: return "Lợi nhuận / Drawdown"
            }
        }

        func score(_ m: BacktestMetrics) -> Double {
            switch self {
            case .netProfit: return m.netProfit
            case .profitFactor: return m.profitFactor.isFinite ? m.profitFactor : 1e9
            case .sharpe: return m.sharpeRatio
            case .winRate: return m.winRate
            case .returnOverDrawdown:
                return m.maxDrawdownPercent > 0 ? m.netProfitPercent / m.maxDrawdownPercent : m.netProfitPercent
            }
        }
    }

    public struct Run: Identifiable, Sendable {
        public var id: Int
        public var values: [String: Double]
        public var metrics: BacktestMetrics
        public var score: Double
    }

    public static func combinations(_ ranges: [Range]) -> [[String: Double]] {
        ranges.reduce([[:]]) { partial, range in
            partial.flatMap { combo in
                range.values.map { value in
                    var next = combo
                    next[range.name] = value
                    return next
                }
            }
        }
    }

    /// Runs every combination (up to `maxRuns`) and returns them best first.
    /// Combinations that fail (e.g. a length of 0) are skipped. `minTrades`
    /// discards results based on too few trades to mean anything.
    public static func run(strategy: StrategyDefinition,
                           data: PriceData,
                           config: BacktestConfig,
                           library: FunctionLibrary = .standard,
                           ranges: [Range],
                           objective: Objective = .netProfit,
                           minTrades: Int = 1,
                           maxRuns: Int = 1000,
                           progress: ((Double) -> Void)? = nil) -> [Run] {
        let combos = Array(combinations(ranges).prefix(maxRuns))
        var runs: [Run] = []
        for (index, values) in combos.enumerated() {
            progress?(Double(index) / Double(max(1, combos.count)))
            guard let result = try? BacktestEngine.run(strategy: strategy, data: data, config: config,
                                                       library: library, parameterValues: values),
                  result.metrics.totalTrades >= minTrades
            else { continue }
            runs.append(Run(id: index, values: values, metrics: result.metrics, score: objective.score(result.metrics)))
        }
        progress?(1)
        return runs.sorted { $0.score > $1.score }
    }
}

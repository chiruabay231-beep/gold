import Foundation

/// "Stop theo nến": after every closed candle, a buy stop above its high and a
/// sell stop below its low (a breakout of that candle). The stop loss sits on
/// the other side of the candle (or a fixed distance), the target is a
/// multiple of the risk. Orders not filled by the next close are replaced;
/// when one side fills the other is cancelled (OCO).
public enum CandleStopBot {
    public enum Direction: String, Codable, CaseIterable, Sendable {
        case both, long, short
    }

    public enum StopMode: String, Codable, CaseIterable, Sendable {
        /// The other end of the candle (± the offset).
        case candle
        /// A fixed price distance from the entry.
        case fixed
    }

    public struct Config: Codable, Hashable, Sendable {
        public var direction = Direction.both
        /// Price added above the high / below the low for the entries (and stops).
        public var offset = 0.0
        public var stopMode = StopMode.candle
        public var stopDistance = 5.0
        /// Target = entry ± rr × risk; 0 = no target.
        public var rr = 2.0
        public var lots = 0.01
        /// Candles with a high − low smaller than this are skipped (0 = all).
        public var minRange = 0.0
        /// Candles bigger than this are skipped (0 = no limit).
        public var maxRange = 0.0
        /// When one order fills, cancel the other side.
        public var oco = true
        /// No new orders while a position of the bot is open.
        public var onePosition = true

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Config()
            direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? d.direction
            offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? d.offset
            stopMode = try c.decodeIfPresent(StopMode.self, forKey: .stopMode) ?? d.stopMode
            stopDistance = try c.decodeIfPresent(Double.self, forKey: .stopDistance) ?? d.stopDistance
            rr = try c.decodeIfPresent(Double.self, forKey: .rr) ?? d.rr
            lots = try c.decodeIfPresent(Double.self, forKey: .lots) ?? d.lots
            minRange = try c.decodeIfPresent(Double.self, forKey: .minRange) ?? d.minRange
            maxRange = try c.decodeIfPresent(Double.self, forKey: .maxRange) ?? d.maxRange
            oco = try c.decodeIfPresent(Bool.self, forKey: .oco) ?? d.oco
            onePosition = try c.decodeIfPresent(Bool.self, forKey: .onePosition) ?? d.onePosition
        }
    }

    public struct Order: Hashable, Sendable {
        public var side: PaperAccount.Side
        public var entry: Double
        public var stop: Double
        public var target: Double?
    }

    /// The orders to place after `candle` closed.
    public static func orders(after candle: Candle, config: Config) -> [Order] {
        let range = candle.high - candle.low
        guard range > 0, range >= config.minRange, config.maxRange <= 0 || range <= config.maxRange else { return [] }
        let offset = max(config.offset, 0)
        var result: [Order] = []
        if config.direction != .short {
            let entry = candle.high + offset
            let stop = config.stopMode == .candle ? candle.low - offset : entry - max(config.stopDistance, 0)
            if entry > stop {
                result.append(Order(side: .long, entry: entry, stop: stop,
                                    target: config.rr > 0 ? entry + config.rr * (entry - stop) : nil))
            }
        }
        if config.direction != .long {
            let entry = candle.low - offset
            let stop = config.stopMode == .candle ? candle.high + offset : entry + max(config.stopDistance, 0)
            if stop > entry {
                result.append(Order(side: .short, entry: entry, stop: stop,
                                    target: config.rr > 0 ? entry - config.rr * (stop - entry) : nil))
            }
        }
        return result
    }

    public struct Report: Sendable {
        public var account: PaperAccount
        /// Orders placed (two per candle when both sides are on).
        public var ordersPlaced: Int
        public var trades: [PaperAccount.ClosedTrade] { account.history.reversed() }
        public var wins: Int { account.history.filter { $0.profit > 0 }.count }
        public var winRate: Double { account.history.isEmpty ? 0 : Double(wins) / Double(account.history.count) }
        public var netProfit: Double { account.balance - account.startingBalance }

        /// Largest fall of the balance from a previous high.
        public var maxDrawdown: Double {
            var peak = account.startingBalance, balance = account.startingBalance, worst = 0.0
            for trade in trades {
                balance += trade.profit
                peak = max(peak, balance)
                worst = max(worst, peak - balance)
            }
            return worst
        }
    }

    /// Runs the bot over `candles` like the live bot would: orders from each
    /// closed candle wait during the next one (open, then the extreme reached
    /// first, the other extreme, the close). No spread.
    public static func backtest(candles: [Candle], symbol: String, config: Config,
                                startingBalance: Double = 10_000) -> Report {
        var account = PaperAccount(startingBalance: startingBalance)
        var placed = 0
        for (i, c) in candles.enumerated() {
            if i > 0 {
                let path = c.close >= c.open ? [c.open, c.low, c.high, c.close] : [c.open, c.high, c.low, c.close]
                for price in path {
                    let events = account.process(symbol: symbol, price: price, time: c.time)
                    if config.oco, events.contains(where: { if case .opened = $0 { return true } else { return false } }) {
                        account.pending.removeAll()
                    }
                }
                // Unfilled orders live for one candle.
                account.pending.removeAll()
            }
            if config.onePosition, !account.positions.isEmpty { continue }
            for order in orders(after: c, config: config) {
                account.placePending(symbol: symbol, side: order.side, lots: config.lots, entry: order.entry, stop: order.stop,
                                     target: order.target, currentPrice: c.close, time: c.time)
                placed += 1
            }
        }
        // Positions still open at the end are closed at the last price.
        if let last = candles.last {
            for position in account.positions {
                account.close(positionID: position.id, price: last.close, time: last.time)
            }
        }
        return Report(account: account, ordersPlaced: placed)
    }
}

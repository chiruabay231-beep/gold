import Foundation

/// A simulated (paper) trading account driven by live prices: market and
/// pending orders with stop loss / take profit, positions and closed trades.
public struct PaperAccount: Codable, Hashable, Sendable {
    public enum Side: String, Codable, Sendable {
        case long, short

        public var sign: Double { self == .long ? 1 : -1 }
    }

    public enum ExitReason: String, Codable, Sendable {
        case target, stop, manual
        /// Closed automatically on a reversal sign (trade management).
        case reversal
    }

    /// An order waiting for price to reach `entry` (limit or stop, decided by
    /// where price was when it was placed).
    public struct PendingOrder: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var symbol: String
        public var side: Side
        public var lots: Double
        public var entry: Double
        public var stop: Double?
        public var target: Double?
        public var contractSize: Double
        /// True when the order fills as price rises to the entry (buy stop / sell limit).
        public var triggersAbove: Bool
        public var createdAt: Date
    }

    public struct Position: Codable, Hashable, Identifiable, Sendable {
        public var id = UUID()
        public var symbol: String
        public var side: Side
        public var lots: Double
        public var entryPrice: Double
        public var stop: Double?
        public var target: Double?
        public var contractSize: Double
        public var openTime: Date
        /// The stop when the position opened; 1R = |entry − initial stop|.
        public var initialStop: Double? = nil
        /// Best price reached since opening (highest for longs, lowest for shorts).
        public var peakPrice: Double? = nil

        public func profit(at price: Double) -> Double {
            (price - entryPrice) * side.sign * lots * contractSize
        }

        /// Price distance of 1R, if the position had a stop.
        public var riskDistance: Double? {
            guard let initialStop else { return nil }
            let d = abs(entryPrice - initialStop)
            return d > 0 ? d : nil
        }

        /// Profit in R at `price` (nil without an initial stop).
        public func rMultiple(at price: Double) -> Double? {
            riskDistance.map { (price - entryPrice) * side.sign / $0 }
        }
    }

    public struct ClosedTrade: Codable, Hashable, Identifiable, Sendable {
        public var id: UUID
        public var symbol: String
        public var side: Side
        public var lots: Double
        public var entryPrice: Double
        public var exitPrice: Double
        public var openTime: Date
        public var closeTime: Date
        public var reason: ExitReason
        public var profit: Double
        /// SL and TP when it closed, and the first SL (moved since if they differ).
        public var stop: Double? = nil
        public var target: Double? = nil
        public var initialStop: Double? = nil
    }

    public enum Event: Hashable, Sendable {
        case opened(Position)
        case closed(ClosedTrade)
        /// Trade management moved the stop of a position.
        case stopMoved(Position)
    }

    public var startingBalance: Double
    public var balance: Double
    public var pending: [PendingOrder] = []
    public var positions: [Position] = []
    public var history: [ClosedTrade] = []

    public init(startingBalance: Double = 10_000) {
        self.startingBalance = startingBalance
        self.balance = startingBalance
    }

    /// Units per lot: 100 oz for gold, 5 000 oz for silver, 100 000 for
    /// forex pairs, 1 for crypto and indices.
    /// Accepts app keys ("BINANCE_FUTURES:XAUUSDT"), OANDA names (XAU_USD) and
    /// broker suffixes (XAUUSDm, EURUSD.r, #EURUSD).
    public static func contractSize(for symbol: String) -> Double {
        var s = symbol.uppercased()
        if let colon = s.lastIndex(of: ":") { s = String(s[s.index(after: colon)...]) }
        s = s.filter { $0.isLetter || $0.isNumber }
        if s.hasPrefix("XAU") || s.hasPrefix("PAXG") { return 100 }
        if s.hasPrefix("XAG") { return 5_000 }
        let currencies = ["EUR", "GBP", "USD", "JPY", "AUD", "NZD", "CAD", "CHF"]
        let pair = s.prefix(6)
        // A 6-letter pair, possibly with a short broker suffix (EURUSDm) but not a USDT/USDC coin pair.
        if (6...8).contains(s.count), !s.hasSuffix("USDT"), !s.hasSuffix("USDC"),
           currencies.contains(String(pair.prefix(3))), currencies.contains(String(pair.suffix(3))) { return 100_000 }
        return 1
    }

    public func equity(price: (String) -> Double?) -> Double {
        balance + positions.reduce(0) { sum, p in sum + (price(p.symbol).map { p.profit(at: $0) } ?? 0) }
    }

    @discardableResult
    public mutating func openMarket(symbol: String, side: Side, lots: Double, price: Double, stop: Double?, target: Double?,
                                    time: Date) -> Position {
        let position = Position(symbol: symbol, side: side, lots: lots, entryPrice: price, stop: stop, target: target,
                                contractSize: Self.contractSize(for: symbol), openTime: time, initialStop: stop, peakPrice: price)
        positions.append(position)
        return position
    }

    /// Places a pending order at `entry`; `currentPrice` decides whether it
    /// waits for price to rise or fall to the entry.
    @discardableResult
    public mutating func placePending(symbol: String, side: Side, lots: Double, entry: Double, stop: Double?, target: Double?,
                                      currentPrice: Double, time: Date) -> PendingOrder {
        let order = PendingOrder(symbol: symbol, side: side, lots: lots, entry: entry, stop: stop, target: target,
                                 contractSize: Self.contractSize(for: symbol), triggersAbove: entry > currentPrice, createdAt: time)
        pending.append(order)
        return order
    }

    public mutating func cancel(orderID: UUID) {
        pending.removeAll { $0.id == orderID }
    }

    @discardableResult
    public mutating func close(positionID: UUID, price: Double, time: Date, reason: ExitReason = .manual) -> ClosedTrade? {
        guard let index = positions.firstIndex(where: { $0.id == positionID }) else { return nil }
        let p = positions.remove(at: index)
        let trade = ClosedTrade(id: p.id, symbol: p.symbol, side: p.side, lots: p.lots, entryPrice: p.entryPrice,
                                exitPrice: price, openTime: p.openTime, closeTime: time, reason: reason, profit: p.profit(at: price),
                                stop: p.stop, target: p.target, initialStop: p.initialStop)
        balance += trade.profit
        history.insert(trade, at: 0)
        return trade
    }

    public mutating func modify(positionID: UUID, stop: Double?, target: Double?) {
        guard let index = positions.firstIndex(where: { $0.id == positionID }) else { return }
        positions[index].stop = stop
        positions[index].target = target
        // A stop added later defines 1R from then on.
        if positions[index].initialStop == nil { positions[index].initialStop = stop }
    }

    /// Moves a pending order; whether it waits for price to rise or fall is
    /// decided again from `currentPrice`.
    public mutating func modifyPending(orderID: UUID, entry: Double, stop: Double?, target: Double?, currentPrice: Double) {
        guard let index = pending.firstIndex(where: { $0.id == orderID }) else { return }
        pending[index].entry = entry
        pending[index].stop = stop
        pending[index].target = target
        pending[index].triggersAbove = entry > currentPrice
    }

    /// Applies a whole bar (bar replay): open, then the extreme reached
    /// first (the low for an up bar, the high for a down bar), the other
    /// extreme and the close.
    public mutating func process(symbol: String, candle c: Candle) -> [Event] {
        let path = c.close >= c.open ? [c.open, c.low, c.high, c.close] : [c.open, c.high, c.low, c.close]
        return path.flatMap { process(symbol: symbol, price: $0, time: c.time) }
    }

    /// Applies a new price of `symbol` with no spread.
    public mutating func process(symbol: String, price: Double, time: Date) -> [Event] {
        process(symbol: symbol, bid: price, ask: price, time: time)
    }

    /// Applies a new quote of `symbol`, like a broker: buys open at the ask and
    /// close at the bid, sells the other way round. Pending buys fill when the
    /// ask reaches their entry, pending sells on the bid; long stops and targets
    /// trigger on the bid, short ones on the ask (fills at the stop/target price).
    public mutating func process(symbol: String, bid: Double, ask: Double, time: Date) -> [Event] {
        var events: [Event] = []
        for order in pending where order.symbol == symbol {
            let price = order.side == .long ? ask : bid
            let reached = order.triggersAbove ? price >= order.entry : price <= order.entry
            guard reached else { continue }
            cancel(orderID: order.id)
            var position = Position(symbol: symbol, side: order.side, lots: order.lots, entryPrice: order.entry,
                                    stop: order.stop, target: order.target, contractSize: order.contractSize, openTime: time,
                                    initialStop: order.stop, peakPrice: order.entry)
            position.id = order.id
            positions.append(position)
            events.append(.opened(position))
        }
        for i in positions.indices where positions[i].symbol == symbol {
            let peak = positions[i].peakPrice ?? positions[i].entryPrice
            positions[i].peakPrice = positions[i].side == .long ? max(peak, bid) : min(peak, ask)
        }
        for position in positions where position.symbol == symbol {
            let isLong = position.side == .long
            let price = isLong ? bid : ask
            if let stop = position.stop, isLong ? price <= stop : price >= stop,
               let trade = close(positionID: position.id, price: stop, time: time, reason: .stop) {
                events.append(.closed(trade))
            } else if let target = position.target, isLong ? price >= target : price <= target,
                      let trade = close(positionID: position.id, price: target, time: time, reason: .target) {
                events.append(.closed(trade))
            }
        }
        return events
    }
}

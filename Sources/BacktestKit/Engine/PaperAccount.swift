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

        public func profit(at price: Double) -> Double {
            (price - entryPrice) * side.sign * lots * contractSize
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
    }

    public enum Event: Hashable, Sendable {
        case opened(Position)
        case closed(ClosedTrade)
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
    public static func contractSize(for symbol: String) -> Double {
        let s = symbol.uppercased().replacingOccurrences(of: "_", with: "")
        if s.hasPrefix("XAU") || s.hasPrefix("PAXG") { return 100 }
        if s.hasPrefix("XAG") { return 5_000 }
        let currencies = ["EUR", "GBP", "USD", "JPY", "AUD", "NZD", "CAD", "CHF"]
        if s.count == 6, currencies.contains(String(s.prefix(3))), currencies.contains(String(s.suffix(3))) { return 100_000 }
        return 1
    }

    public func equity(price: (String) -> Double?) -> Double {
        balance + positions.reduce(0) { sum, p in sum + (price(p.symbol).map { p.profit(at: $0) } ?? 0) }
    }

    @discardableResult
    public mutating func openMarket(symbol: String, side: Side, lots: Double, price: Double, stop: Double?, target: Double?,
                                    time: Date) -> Position {
        let position = Position(symbol: symbol, side: side, lots: lots, entryPrice: price, stop: stop, target: target,
                                contractSize: Self.contractSize(for: symbol), openTime: time)
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
                                exitPrice: price, openTime: p.openTime, closeTime: time, reason: reason, profit: p.profit(at: price))
        balance += trade.profit
        history.insert(trade, at: 0)
        return trade
    }

    public mutating func modify(positionID: UUID, stop: Double?, target: Double?) {
        guard let index = positions.firstIndex(where: { $0.id == positionID }) else { return }
        positions[index].stop = stop
        positions[index].target = target
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

    /// Applies a new price of `symbol`: fills pending orders, then closes
    /// positions whose stop or target was reached (at the stop/target price).
    public mutating func process(symbol: String, price: Double, time: Date) -> [Event] {
        var events: [Event] = []
        for order in pending where order.symbol == symbol {
            let reached = order.triggersAbove ? price >= order.entry : price <= order.entry
            guard reached else { continue }
            cancel(orderID: order.id)
            var position = Position(symbol: symbol, side: order.side, lots: order.lots, entryPrice: order.entry,
                                    stop: order.stop, target: order.target, contractSize: order.contractSize, openTime: time)
            position.id = order.id
            positions.append(position)
            events.append(.opened(position))
        }
        for position in positions where position.symbol == symbol {
            let isLong = position.side == .long
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

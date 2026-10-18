import Foundation

/// Automatic management of open positions: move the stop once price has
/// gone far enough (break-even / lock profit, optional step trailing) and
/// close on signs of a reversal.
public struct TradeManagement: Codable, Hashable, Sendable {
    /// Move the stop when profit reaches `triggerR`.
    public var moveStop = true
    public var triggerR = 2.0
    /// Where the stop goes, in R from the entry (0 = break-even, 1 = lock +1R).
    public var lockR = 1.0
    /// After the trigger, move the stop again every `trailStepR` (0 = off).
    public var trailStepR = 0.0

    /// Close when price shows a reversal (only checked on closed bars).
    public var closeOnReversal = false
    /// Close on a market structure break against the position.
    public var reversalStructure = true
    public var swingLength = 3
    /// Close on an engulfing candle against the position.
    public var reversalEngulfing = true
    /// Close when price gives back this share of the best open profit (0 = off).
    public var givebackPercent = 0.0
    /// Reversal exits only once profit has reached this many R.
    public var minProfitR = 1.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TradeManagement()
        moveStop = try c.decodeIfPresent(Bool.self, forKey: .moveStop) ?? d.moveStop
        triggerR = try c.decodeIfPresent(Double.self, forKey: .triggerR) ?? d.triggerR
        lockR = try c.decodeIfPresent(Double.self, forKey: .lockR) ?? d.lockR
        trailStepR = try c.decodeIfPresent(Double.self, forKey: .trailStepR) ?? d.trailStepR
        closeOnReversal = try c.decodeIfPresent(Bool.self, forKey: .closeOnReversal) ?? d.closeOnReversal
        reversalStructure = try c.decodeIfPresent(Bool.self, forKey: .reversalStructure) ?? d.reversalStructure
        swingLength = try c.decodeIfPresent(Int.self, forKey: .swingLength) ?? d.swingLength
        reversalEngulfing = try c.decodeIfPresent(Bool.self, forKey: .reversalEngulfing) ?? d.reversalEngulfing
        givebackPercent = try c.decodeIfPresent(Double.self, forKey: .givebackPercent) ?? d.givebackPercent
        minProfitR = try c.decodeIfPresent(Double.self, forKey: .minProfitR) ?? d.minProfitR
    }

    /// Stop a position should have at its best price so far, if it is better
    /// than the current one.
    public func improvedStop(for p: PaperAccount.Position) -> Double? {
        guard moveStop, let risk = p.riskDistance, let peak = p.peakPrice,
              let peakR = p.rMultiple(at: peak), peakR >= triggerR else { return nil }
        var lock = lockR
        if trailStepR > 0 {
            // One more step of lock for every full step beyond the trigger.
            lock += floor((peakR - triggerR) / trailStepR) * trailStepR
        }
        let newStop = p.entryPrice + p.side.sign * lock * risk
        guard let current = p.stop else { return newStop }
        return (newStop - current) * p.side.sign > 1e-12 ? newStop : nil
    }

    /// Why a position should be closed after the last closed bar, if it should.
    public func reversalReason(for p: PaperAccount.Position, closed candles: [Candle], price: Double) -> String? {
        guard closeOnReversal, let last = candles.last, last.time >= p.openTime else { return nil }
        // Only protect trades that are already in enough profit.
        let r = p.rMultiple(at: price) ?? (p.profit(at: price) > 0 ? .infinity : -.infinity)
        guard r >= minProfitR else { return nil }
        let isLong = p.side == .long

        if givebackPercent > 0, let peak = p.peakPrice {
            let best = (peak - p.entryPrice) * p.side.sign
            let now = (price - p.entryPrice) * p.side.sign
            if best > 0, now <= best * (1 - givebackPercent / 100) {
                return "Trả lại \(Int(givebackPercent))% lợi nhuận"
            }
        }
        if reversalEngulfing, candles.count >= 2 {
            let prev = candles[candles.count - 2]
            let body = abs(last.close - last.open)
            let engulfs = isLong
                ? last.close < last.open && prev.close > prev.open && last.open >= prev.close && last.close <= prev.open
                : last.close > last.open && prev.close < prev.open && last.open <= prev.close && last.close >= prev.open
            if engulfs, body > 0 { return "Nến nhấn chìm ngược chiều" }
        }
        if reversalStructure {
            var config = KillzonePivots.Config()
            config.showMSS = true
            config.showBOS = true
            config.swingLength = swingLength
            let recent = Array(candles.suffix(400))
            if let brk = KillzonePivots.structureBreaks(recent, config: config).last,
               brk.end == recent.count - 1, brk.bullish != isLong {
                return brk.shift ? "MSS ngược chiều" : "Phá cấu trúc ngược chiều"
            }
        }
        return nil
    }
}

extension PaperAccount {
    /// Applies trade management to the positions of `symbol`: moves stops and,
    /// when `closed` bars are given (a bar just closed), closes on reversals.
    public mutating func manage(symbol: String, price: Double, time: Date, rules: TradeManagement,
                                closed: [Candle]? = nil) -> [Event] {
        var events: [Event] = []
        for position in positions where position.symbol == symbol {
            if let closed, rules.reversalReason(for: position, closed: closed, price: price) != nil {
                if let trade = close(positionID: position.id, price: price, time: time, reason: .reversal) {
                    events.append(.closed(trade))
                }
                continue
            }
            if let stop = rules.improvedStop(for: position),
               let index = positions.firstIndex(where: { $0.id == position.id }) {
                positions[index].stop = stop
                events.append(.stopMoved(positions[index]))
            }
        }
        return events
    }
}

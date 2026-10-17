import Foundation

public enum TradeDirection: String, Codable, Sendable {
    case long, short

    public var sign: Double { self == .long ? 1 : -1 }
}

public enum ExitReason: String, Codable, Sendable {
    case signal
    case stopLoss
    case takeProfit
    case reverse
    case endOfData

    public var label: String {
        switch self {
        case .signal: return "Tín hiệu"
        case .stopLoss: return "Cắt lỗ"
        case .takeProfit: return "Chốt lời"
        case .reverse: return "Đảo chiều"
        case .endOfData: return "Hết dữ liệu"
        }
    }
}

public struct Trade: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var direction: TradeDirection
    public var entryIndex: Int
    public var entryTime: Date
    public var entryPrice: Double
    public var exitIndex: Int
    public var exitTime: Date
    public var exitPrice: Double
    public var quantity: Double
    public var stopPrice: Double?
    public var targetPrice: Double?
    public var commission: Double
    /// Net profit after commission.
    public var profit: Double
    public var exitReason: ExitReason

    public var barsHeld: Int { exitIndex - entryIndex }
    public var notional: Double { entryPrice * quantity }
    /// Net profit relative to the position's notional, in percent.
    public var returnPercent: Double { notional == 0 ? 0 : 100 * profit / notional }
    public var isWin: Bool { profit > 0 }
    /// Result in multiples of the initial risk, when a stop was set.
    public var rMultiple: Double? {
        guard let stopPrice, stopPrice != entryPrice else { return nil }
        let risk = abs(entryPrice - stopPrice) * quantity
        return risk == 0 ? nil : profit / risk
    }
}

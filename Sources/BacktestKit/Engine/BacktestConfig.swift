import Foundation

public enum PositionSizingMode: String, Codable, CaseIterable, Sendable {
    /// `value`% of current equity as notional (100 = no leverage).
    case percentOfEquity
    /// A fixed amount of the asset, e.g. 1 BTC or 100 oz (1 lot XAUUSD).
    case fixedQuantity
    /// A fixed notional amount of money per trade.
    case fixedCash
    /// Risk `value`% of equity between entry and stop. Needs a stop loss.
    case riskPercent
}

public struct BacktestConfig: Codable, Hashable, Sendable {
    public var initialCapital: Double
    public var sizingMode: PositionSizingMode
    public var sizingValue: Double
    /// Commission per side, as a percentage of notional.
    public var commissionPercent: Double
    /// Fixed commission per side, in money.
    public var commissionPerTrade: Double
    /// Price units added against you on every fill (spread / slippage).
    public var slippage: Double
    public var allowLong: Bool
    public var allowShort: Bool
    /// Fallback stop loss in % from the fill price when the script sets none.
    public var stopLossPercent: Double?
    /// Fallback take profit in % from the fill price when the script sets none.
    public var takeProfitPercent: Double?
    /// Time zone used by `hour`, `session()`, `vwap()`… in scripts.
    public var timeZoneIdentifier: String

    public init(initialCapital: Double = 10_000,
                sizingMode: PositionSizingMode = .percentOfEquity,
                sizingValue: Double = 100,
                commissionPercent: Double = 0.05,
                commissionPerTrade: Double = 0,
                slippage: Double = 0,
                allowLong: Bool = true,
                allowShort: Bool = true,
                stopLossPercent: Double? = nil,
                takeProfitPercent: Double? = nil,
                timeZoneIdentifier: String = "UTC") {
        self.initialCapital = initialCapital
        self.sizingMode = sizingMode
        self.sizingValue = sizingValue
        self.commissionPercent = commissionPercent
        self.commissionPerTrade = commissionPerTrade
        self.slippage = slippage
        self.allowLong = allowLong
        self.allowShort = allowShort
        self.stopLossPercent = stopLossPercent
        self.takeProfitPercent = takeProfitPercent
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "UTC")!
    }
}

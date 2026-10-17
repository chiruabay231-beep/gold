import Foundation

/// One OHLCV bar.
public struct Candle: Codable, Hashable, Sendable {
    public var time: Date
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double

    public init(time: Date, open: Double, high: Double, low: Double, close: Double, volume: Double = 0) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

/// A numeric time series aligned with the candles. Missing values are `.nan`.
public typealias Series = [Double]

/// Column-oriented view of a candle array, which is what indicators and the
/// script evaluator work with.
public struct PriceData: Sendable {
    public let candles: [Candle]
    public let time: [Date]
    public let open: Series
    public let high: Series
    public let low: Series
    public let close: Series
    public let volume: Series

    public init(candles: [Candle]) {
        self.candles = candles
        time = candles.map(\.time)
        open = candles.map(\.open)
        high = candles.map(\.high)
        low = candles.map(\.low)
        close = candles.map(\.close)
        volume = candles.map(\.volume)
    }

    public var count: Int { candles.count }

    /// Median spacing between bars, in seconds. Used to annualise metrics.
    public var medianBarInterval: TimeInterval {
        guard count > 1 else { return 0 }
        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(count - 1)
        for i in 1..<count {
            deltas.append(time[i].timeIntervalSince(time[i - 1]))
        }
        deltas.sort()
        return deltas[deltas.count / 2]
    }

    /// Returns the bars in `range` as a new `PriceData`.
    public func slice(_ range: Range<Int>) -> PriceData {
        PriceData(candles: Array(candles[range]))
    }
}

public extension Double {
    /// Truthiness used by the script language: non-zero and not NaN.
    var isTruthy: Bool { !isNaN && self != 0 }
}

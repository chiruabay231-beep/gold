import Foundation

/// Deterministic synthetic price data so the app and tests work offline.
public enum SampleData {
    /// Generates `count` hourly candles from a seeded random walk with
    /// alternating trend regimes, roughly in the price range of gold.
    public static func candles(count: Int = 2000,
                               start: Date = Date(timeIntervalSince1970: 1_704_067_200),
                               interval: TimeInterval = 3600,
                               startPrice: Double = 2050,
                               seed: UInt64 = 42) -> [Candle] {
        var rng = SplitMix64(seed: seed)
        var candles: [Candle] = []
        candles.reserveCapacity(count)
        var price = startPrice
        var drift = 0.0
        for i in 0..<count {
            if i % 150 == 0 { drift = (rng.nextDouble() - 0.5) * 0.0012 }
            let volatility = 0.002 + rng.nextDouble() * 0.002
            let open = price
            let change = drift + (rng.nextDouble() - 0.5) * 2 * volatility
            let close = open * (1 + change)
            let wickUp = abs(rng.nextDouble()) * volatility * open * 0.6
            let wickDown = abs(rng.nextDouble()) * volatility * open * 0.6
            let high = max(open, close) + wickUp
            let low = min(open, close) - wickDown
            let volume = 500 + rng.nextDouble() * 1500
            candles.append(Candle(time: start.addingTimeInterval(Double(i) * interval),
                                  open: open, high: high, low: low, close: close, volume: volume))
            price = close
        }
        return candles
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

import Foundation

/// "Dòng tiền cá mập": a simple read of where the money goes.
///
/// * Money flow: for each bar, how much of its volume closed near the high
///   (buyers in control) or near the low (sellers in control); summed over the
///   last `flowLength` bars it gives a score from −100 % (all money leaving) to
///   +100 % (all money coming in).
/// * Sharks: bars whose volume is at least `sharkMultiple` × the average of the
///   bars before and that close clearly up or down: a big player buying or selling.
///
/// Without volume (some forex feeds) each bar's range stands in for it.
public enum SharkFlow {
    public struct Config: Codable, Hashable, Sendable {
        public var flowLength = 20
        public var volumeLength = 20
        public var sharkMultiple = 2.5

        public init(flowLength: Int = 20, volumeLength: Int = 20, sharkMultiple: Double = 2.5) {
            self.flowLength = flowLength
            self.volumeLength = volumeLength
            self.sharkMultiple = sharkMultiple
        }
    }

    public struct Shark: Hashable, Sendable {
        public var index: Int
        public var buying: Bool
        /// Volume ÷ average volume.
        public var ratio: Double
    }

    public struct Output: Sendable {
        /// Per bar: −1 (closed at the low) … +1 (closed at the high), weighted by volume below.
        public var pressure: [Double] = []
        /// Money flow score of the last `flowLength` bars, −1 … +1 (NaN before enough bars).
        public var flow: [Double] = []
        public var sharks: [Shark] = []

        public init() {}

        /// The latest score.
        public var current: Double? { flow.last.flatMap { $0.isFinite ? $0 : nil } }
    }

    public static func compute(candles c: [Candle], config: Config = Config()) -> Output {
        var out = Output()
        let n = c.count
        guard n > 1 else { return out }
        let useVolume = c.contains { $0.volume > 0 }
        let weight = c.map { useVolume ? $0.volume : max($0.high - $0.low, 0) }
        out.pressure = c.map { bar in
            let range = bar.high - bar.low
            return range > 0 ? ((bar.close - bar.low) - (bar.high - bar.close)) / range : 0
        }
        let length = max(config.flowLength, 1)
        var flow = [Double](repeating: .nan, count: n)
        var money = 0.0, total = 0.0
        for i in 0..<n {
            money += out.pressure[i] * weight[i]
            total += weight[i]
            if i >= length {
                money -= out.pressure[i - length] * weight[i - length]
                total -= weight[i - length]
            }
            if i >= length - 1, total > 0 { flow[i] = max(-1, min(1, money / total)) }
        }
        out.flow = flow

        let lookback = max(config.volumeLength, 1)
        var sum = 0.0
        for i in 0..<n {
            if i >= lookback {
                let average = sum / Double(lookback)
                let ratio = average > 0 ? weight[i] / average : 0
                // A clear close: in the top or bottom third of the bar.
                if ratio >= config.sharkMultiple, abs(out.pressure[i]) >= 0.33 {
                    out.sharks.append(Shark(index: i, buying: out.pressure[i] > 0, ratio: ratio))
                }
                sum -= weight[i - lookback]
            }
            sum += weight[i]
        }
        return out
    }
}

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
        /// Supply / demand: bars read, price rows and zones kept on each side.
        public var zoneLookback = 300
        public var zoneRows = 120
        public var zoneCount = 2

        public init(flowLength: Int = 20, volumeLength: Int = 20, sharkMultiple: Double = 2.5,
                    zoneLookback: Int = 300, zoneRows: Int = 120, zoneCount: Int = 2) {
            self.flowLength = flowLength
            self.volumeLength = volumeLength
            self.sharkMultiple = sharkMultiple
            self.zoneLookback = zoneLookback
            self.zoneRows = zoneRows
            self.zoneCount = zoneCount
        }
    }

    /// Where the big players bought (demand, under the price: they wait to buy there again)
    /// or sold (supply, above it: they wait to sell), read from volume at each price.
    public struct Zone: Hashable, Sendable {
        /// true = demand (buyers), under the current price.
        public var demand: Bool
        public var top: Double
        public var bottom: Double
        /// The zone's share of its side's surplus: of all the buying beyond selling under the price
        /// (demand) or selling beyond buying above it (supply), 0…1.
        public var strength: Double
        /// First bar that traded in the zone (where the box starts).
        public var start: Int
        /// The zone's busiest price row (its middle).
        public var peak: Double
    }

    public struct Shark: Hashable, Sendable {
        public var index: Int
        public var buying: Bool
        /// Volume ÷ average volume.
        public var ratio: Double
    }

    /// Price against money over the last `flowLength` bars, in plain words.
    public enum Situation: String, Sendable {
        /// Price up and money coming in: a healthy rise.
        case strongUp
        /// Price up while money leaves: a weak rise, may turn down.
        case weakUp
        /// Price down and money leaving: a healthy fall.
        case strongDown
        /// Price down while money comes in: someone is buying the dip, may turn up.
        case weakDown
        case flat
    }

    /// Where price and money start to disagree (start of a weakUp / weakDown run).
    public struct Divergence: Hashable, Sendable {
        public var index: Int
        /// true = price falling while money comes in (may turn up).
        public var bullish: Bool
    }

    public struct Output: Sendable {
        /// Per bar: −1 (closed at the low) … +1 (closed at the high), weighted by volume below.
        public var pressure: [Double] = []
        /// Money flow score of the last `flowLength` bars, −1 … +1 (NaN before enough bars).
        public var flow: [Double] = []
        public var sharks: [Shark] = []
        /// Per bar (nil before enough bars).
        public var situations: [Situation?] = []
        public var divergences: [Divergence] = []
        /// Strongest demand zones under the price, then supply zones above it (strongest first).
        public var zones: [Zone] = []

        public init() {}

        public var situation: Situation? { situations.last ?? nil }

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

        // Price move over the same bars, against half the average bar range.
        var situations = [Situation?](repeating: nil, count: n)
        var rangeSum = 0.0
        for i in 0..<n {
            rangeSum += c[i].high - c[i].low
            if i >= length { rangeSum -= c[i - length].high - c[i - length].low }
            guard i >= length, flow[i].isFinite else { continue }
            let change = c[i].close - c[i - length].close
            let threshold = rangeSum / Double(length) * 0.5
            if change > threshold {
                situations[i] = flow[i] < -0.05 ? .weakUp : .strongUp
            } else if change < -threshold {
                situations[i] = flow[i] > 0.05 ? .weakDown : .strongDown
            } else {
                situations[i] = .flat
            }
            let state = situations[i]
            if state == .weakUp || state == .weakDown, situations[i - 1] != state {
                out.divergences.append(Divergence(index: i, bullish: state == .weakDown))
            }
        }
        out.situations = situations

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
        out.zones = zones(c, pressure: out.pressure, weight: weight, sharks: out.sharks, config: config)
        return out
    }

    /// Volume at price over the last `zoneLookback` bars, split into buying and selling by where each bar
    /// closed (shark bars count `ratio` times). Rows under the price where buying beat selling the most are
    /// demand, rows above it where selling won are supply; neighbouring rows at least 80 % as strong join,
    /// three rows at most.
    public static func zones(_ c: [Candle], pressure: [Double], weight: [Double], sharks: [Shark], config: Config) -> [Zone] {
        let n = c.count, rows = max(config.zoneRows, 4)
        let from = max(0, n - max(config.zoneLookback, 10))
        guard n - from >= 10 else { return [] }
        let window = c[from..<n]
        guard let lo = window.map(\.low).min(), let hi = window.map(\.high).max(), hi > lo else { return [] }
        let step = (hi - lo) / Double(rows)
        var buy = [Double](repeating: 0, count: rows), sell = buy
        let boost = Dictionary(sharks.map { ($0.index, $0.ratio) }, uniquingKeysWith: max)
        let row = { (price: Double) in min(rows - 1, max(0, Int((price - lo) / step))) }
        for i in from..<n {
            let w = weight[i] * (boost[i] ?? 1)
            guard w > 0 else { continue }
            let buying = (1 + pressure[i]) / 2
            let a = row(c[i].low), b = row(c[i].high)
            let span = max(c[i].high - c[i].low, step * 1e-9)
            for k in a...b {
                // The bar's volume spread over the rows it covers, by how much of it each holds.
                let overlap = a == b ? 1 : max(0, min(c[i].high, lo + Double(k + 1) * step) - max(c[i].low, lo + Double(k) * step)) / span
                buy[k] += w * overlap * buying
                sell[k] += w * overlap * (1 - buying)
            }
        }
        let total = zip(buy, sell).reduce(0) { $0 + $1.0 + $1.1 }
        guard total > 0, let price = c.last?.close else { return [] }
        let below = row(price) - 1, above = row(price) + 1
        func pick(_ demand: Bool) -> [Zone] {
            let indices = demand ? Array(0...max(below, 0)).filter { $0 <= below } : Array(min(above, rows)..<rows)
            var score = [Double](repeating: 0, count: rows)
            for k in indices { score[k] = max(0, demand ? buy[k] - sell[k] : sell[k] - buy[k]) }
            // Strength: the zone's share of all this side's surplus (of the buyers under the price, the sellers above).
            let sideTotal = indices.reduce(0) { $0 + score[$1] }
            var used = Set<Int>(), found: [Zone] = []
            while found.count < max(config.zoneCount, 1) {
                guard let best = indices.filter({ !used.contains($0) && score[$0] > 0 }).max(by: { score[$0] < score[$1] }) else { break }
                // Tight: the strongest row and its strongest neighbours at 80 % of it or more, three rows at most.
                let ok = { (k: Int, part: Double) in
                    k >= 0 && k < rows && indices.contains(k) && !used.contains(k) && score[k] >= score[best] * part
                }
                var a = best, b = best
                while b - a < 2 {
                    let left = ok(a - 1, 0.8) ? score[a - 1] : -1, right = ok(b + 1, 0.8) ? score[b + 1] : -1
                    if left < 0, right < 0 { break }
                    if left >= right { a -= 1 } else { b += 1 }
                }
                // The whole area around it (rows half as strong) is used up, so the next zone is somewhere else.
                var ua = a, ub = b
                while ok(ua - 1, 0.5) { ua -= 1 }
                while ok(ub + 1, 0.5) { ub += 1 }
                for k in max(0, ua - 1)...min(rows - 1, ub + 1) { used.insert(k) }
                let bottom = lo + Double(a) * step, top = lo + Double(b + 1) * step
                let start = (from..<n).first { c[$0].low <= top && c[$0].high >= bottom } ?? from
                found.append(Zone(demand: demand, top: top, bottom: bottom, strength: score[a...b].reduce(0, +) / sideTotal,
                                  start: start, peak: lo + (Double(best) + 0.5) * step))
            }
            return found
        }
        return pick(true) + pick(false)
    }
}

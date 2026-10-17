import Foundation

/// Vectorised technical-analysis functions. Every function returns a series
/// of the same length as its input, with `.nan` where the value is not yet
/// defined (warm-up period). Values at bar `i` only use bars `0...i`, so no
/// function looks into the future.
public enum TA {
    // MARK: - Moving averages

    public static func sma(_ source: Series, _ length: Int) -> Series {
        let n = source.count
        var out = Series(repeating: .nan, count: n)
        guard length > 0 else { return out }
        var sum = 0.0
        var nanCount = 0
        for i in 0..<n {
            let x = source[i]
            if x.isNaN { nanCount += 1 } else { sum += x }
            if i >= length {
                let old = source[i - length]
                if old.isNaN { nanCount -= 1 } else { sum -= old }
            }
            if i >= length - 1, nanCount == 0 {
                out[i] = sum / Double(length)
            }
        }
        return out
    }

    /// Exponential average seeded with the SMA of the first `length` valid values.
    public static func ema(_ source: Series, _ length: Int) -> Series {
        recursiveAverage(source, length, alpha: 2 / (Double(length) + 1))
    }

    /// Wilder's smoothing (used by RSI, ATR, ADX).
    public static func rma(_ source: Series, _ length: Int) -> Series {
        recursiveAverage(source, length, alpha: 1 / Double(length))
    }

    static func recursiveAverage(_ source: Series, _ length: Int, alpha: Double) -> Series {
        let n = source.count
        var out = Series(repeating: .nan, count: n)
        guard length > 0 else { return out }
        var previous = Double.nan
        var seedSum = 0.0
        var seedCount = 0
        for i in 0..<n {
            let x = source[i]
            if previous.isNaN {
                if x.isNaN {
                    seedSum = 0
                    seedCount = 0
                    continue
                }
                seedSum += x
                seedCount += 1
                if seedCount == length {
                    previous = seedSum / Double(length)
                    out[i] = previous
                }
            } else if !x.isNaN {
                previous = alpha * x + (1 - alpha) * previous
                out[i] = previous
            }
        }
        return out
    }

    public static func wma(_ source: Series, _ length: Int) -> Series {
        let n = source.count
        var out = Series(repeating: .nan, count: n)
        guard length > 0 else { return out }
        let denominator = Double(length * (length + 1)) / 2
        for i in stride(from: length - 1, to: n, by: 1) {
            var total = 0.0
            var valid = true
            for k in 0..<length {
                let x = source[i - k]
                if x.isNaN { valid = false; break }
                total += x * Double(length - k)
            }
            if valid { out[i] = total / denominator }
        }
        return out
    }

    /// Hull moving average.
    public static func hma(_ source: Series, _ length: Int) -> Series {
        let half = wma(source, max(1, length / 2))
        let full = wma(source, length)
        let diff = zip(half, full).map { 2 * $0 - $1 }
        return wma(diff, max(1, Int(Double(length).squareRoot().rounded())))
    }

    public static func vwma(_ source: Series, _ volume: Series, _ length: Int) -> Series {
        let weighted = sma(zip(source, volume).map(*), length)
        let volumes = sma(volume, length)
        return zip(weighted, volumes).map { $1 == 0 ? .nan : $0 / $1 }
    }

    /// Kaufman adaptive moving average.
    public static func kama(_ source: Series, _ length: Int, fast: Int = 2, slow: Int = 30) -> Series {
        let n = source.count
        var out = Series(repeating: .nan, count: n)
        guard length > 0, n > length else { return out }
        let fastSC = 2 / (Double(fast) + 1)
        let slowSC = 2 / (Double(slow) + 1)
        var previous = source[length]
        out[length] = previous
        for i in stride(from: length + 1, to: n, by: 1) {
            let direction = abs(source[i] - source[i - length])
            var volatility = 0.0
            for k in 0..<length { volatility += abs(source[i - k] - source[i - k - 1]) }
            let er = volatility == 0 ? 0 : direction / volatility
            let sc = pow(er * (fastSC - slowSC) + slowSC, 2)
            if source[i].isNaN || previous.isNaN {
                previous = source[i]
                continue
            }
            previous += sc * (source[i] - previous)
            out[i] = previous
        }
        return out
    }

    // MARK: - Rolling statistics

    public static func sum(_ source: Series, _ length: Int) -> Series {
        sma(source, length).map { $0 * Double(length) }
    }

    /// Population standard deviation, like TradingView's `ta.stdev`.
    public static func stdev(_ source: Series, _ length: Int) -> Series {
        variance(source, length).map { $0.squareRoot() }
    }

    public static func variance(_ source: Series, _ length: Int) -> Series {
        let mean = sma(source, length)
        var out = Series(repeating: .nan, count: source.count)
        for i in source.indices where !mean[i].isNaN {
            var total = 0.0
            for k in 0..<length {
                let d = source[i - k] - mean[i]
                total += d * d
            }
            out[i] = total / Double(length)
        }
        return out
    }

    public static func highest(_ source: Series, _ length: Int) -> Series {
        rollingExtreme(source, length, >)
    }

    public static func lowest(_ source: Series, _ length: Int) -> Series {
        rollingExtreme(source, length, <)
    }

    static func rollingExtreme(_ source: Series, _ length: Int, _ better: (Double, Double) -> Bool) -> Series {
        let n = source.count
        var out = Series(repeating: .nan, count: n)
        guard length > 0 else { return out }
        for i in stride(from: length - 1, to: n, by: 1) {
            var best = Double.nan
            for k in 0..<length {
                let x = source[i - k]
                if !x.isNaN, best.isNaN || better(x, best) { best = x }
            }
            out[i] = best
        }
        return out
    }

    public static func shift(_ source: Series, _ offset: Int) -> Series {
        let n = source.count
        guard offset > 0 else { return source }
        guard offset < n else { return Series(repeating: .nan, count: n) }
        return Series(repeating: .nan, count: offset) + source[0..<(n - offset)]
    }

    public static func change(_ source: Series, _ length: Int = 1) -> Series {
        zip(source, shift(source, length)).map { $0 - $1 }
    }

    /// Rate of change in percent.
    public static func roc(_ source: Series, _ length: Int) -> Series {
        zip(source, shift(source, length)).map { (current: Double, previous: Double) -> Double in
            previous == 0 ? .nan : 100 * (current - previous) / previous
        }
    }

    public static func cum(_ source: Series) -> Series {
        var total = 0.0
        return source.map { x in
            if !x.isNaN { total += x }
            return total
        }
    }

    // MARK: - Oscillators

    public static func rsi(_ source: Series, _ length: Int) -> Series {
        let delta = change(source)
        let gains = rma(delta.map { $0.isNaN ? .nan : max($0, 0) }, length)
        let losses = rma(delta.map { $0.isNaN ? .nan : max(-$0, 0) }, length)
        return zip(gains, losses).map { up, down in
            if up.isNaN || down.isNaN { return .nan }
            if down == 0 { return up == 0 ? 50 : 100 }
            return 100 - 100 / (1 + up / down)
        }
    }

    public struct MACD {
        public var line: Series
        public var signal: Series
        public var histogram: Series
    }

    public static func macd(_ source: Series, fast: Int = 12, slow: Int = 26, signal: Int = 9) -> MACD {
        let line = zip(ema(source, fast), ema(source, slow)).map { $0 - $1 }
        let signalLine = ema(line, signal)
        return MACD(line: line, signal: signalLine, histogram: zip(line, signalLine).map { $0 - $1 })
    }

    /// Stochastic %K, optionally smoothed with an SMA.
    public static func stoch(high: Series, low: Series, close: Series, length: Int, smooth: Int = 1) -> Series {
        let hh = highest(high, length)
        let ll = lowest(low, length)
        var k = Series(repeating: .nan, count: close.count)
        for i in close.indices where !hh[i].isNaN && !ll[i].isNaN {
            let range = hh[i] - ll[i]
            k[i] = range == 0 ? 50 : 100 * (close[i] - ll[i]) / range
        }
        return smooth > 1 ? sma(k, smooth) : k
    }

    public static func cci(high: Series, low: Series, close: Series, length: Int) -> Series {
        let tp = typicalPrice(high: high, low: low, close: close)
        let mean = sma(tp, length)
        var out = Series(repeating: .nan, count: tp.count)
        for i in tp.indices where !mean[i].isNaN {
            var deviation = 0.0
            for k in 0..<length { deviation += abs(tp[i - k] - mean[i]) }
            deviation /= Double(length)
            out[i] = deviation == 0 ? 0 : (tp[i] - mean[i]) / (0.015 * deviation)
        }
        return out
    }

    // MARK: - Volatility

    public static func trueRange(high: Series, low: Series, close: Series) -> Series {
        var out = Series(repeating: .nan, count: close.count)
        for i in close.indices {
            if i == 0 {
                out[i] = high[i] - low[i]
            } else {
                let previous = close[i - 1]
                out[i] = max(high[i] - low[i], abs(high[i] - previous), abs(low[i] - previous))
            }
        }
        return out
    }

    public static func atr(high: Series, low: Series, close: Series, length: Int) -> Series {
        rma(trueRange(high: high, low: low, close: close), length)
    }

    public struct Bands {
        public var middle: Series
        public var upper: Series
        public var lower: Series
    }

    public static func bollinger(_ source: Series, length: Int = 20, multiplier: Double = 2) -> Bands {
        let middle = sma(source, length)
        let deviation = stdev(source, length)
        return Bands(middle: middle,
                     upper: zip(middle, deviation).map { $0 + multiplier * $1 },
                     lower: zip(middle, deviation).map { $0 - multiplier * $1 })
    }

    public static func keltner(high: Series, low: Series, close: Series, length: Int = 20, multiplier: Double = 2) -> Bands {
        let middle = ema(close, length)
        let range = atr(high: high, low: low, close: close, length: length)
        return Bands(middle: middle,
                     upper: zip(middle, range).map { $0 + multiplier * $1 },
                     lower: zip(middle, range).map { $0 - multiplier * $1 })
    }

    // MARK: - Trend

    public struct DirectionalMovement {
        public var adx: Series
        public var plusDI: Series
        public var minusDI: Series
    }

    public static func dmi(high: Series, low: Series, close: Series, length: Int = 14) -> DirectionalMovement {
        let n = close.count
        var plusDM = Series(repeating: 0, count: n)
        var minusDM = Series(repeating: 0, count: n)
        for i in stride(from: 1, to: n, by: 1) {
            let up = high[i] - high[i - 1]
            let down = low[i - 1] - low[i]
            plusDM[i] = up > down && up > 0 ? up : 0
            minusDM[i] = down > up && down > 0 ? down : 0
        }
        let range = atr(high: high, low: low, close: close, length: length)
        let plusSmoothed = rma(plusDM, length)
        let minusSmoothed = rma(minusDM, length)
        var plusDI = Series(repeating: .nan, count: n)
        var minusDI = Series(repeating: .nan, count: n)
        var dx = Series(repeating: .nan, count: n)
        for i in 0..<n where !range[i].isNaN && range[i] != 0 {
            plusDI[i] = 100 * plusSmoothed[i] / range[i]
            minusDI[i] = 100 * minusSmoothed[i] / range[i]
            let total = plusDI[i] + minusDI[i]
            dx[i] = total == 0 ? 0 : 100 * abs(plusDI[i] - minusDI[i]) / total
        }
        return DirectionalMovement(adx: rma(dx, length), plusDI: plusDI, minusDI: minusDI)
    }

    public struct Supertrend {
        public var line: Series
        /// 1 in an uptrend, -1 in a downtrend.
        public var direction: Series
    }

    public static func supertrend(high: Series, low: Series, close: Series, length: Int = 10, multiplier: Double = 3) -> Supertrend {
        let n = close.count
        let range = atr(high: high, low: low, close: close, length: length)
        var line = Series(repeating: .nan, count: n)
        var direction = Series(repeating: .nan, count: n)
        var finalUpper = Double.nan
        var finalLower = Double.nan
        var trend = 1.0
        for i in 0..<n where !range[i].isNaN {
            let mid = (high[i] + low[i]) / 2
            let basicUpper = mid + multiplier * range[i]
            let basicLower = mid - multiplier * range[i]
            if finalUpper.isNaN {
                finalUpper = basicUpper
                finalLower = basicLower
            } else {
                let previousClose = close[i - 1]
                finalUpper = basicUpper < finalUpper || previousClose > finalUpper ? basicUpper : finalUpper
                finalLower = basicLower > finalLower || previousClose < finalLower ? basicLower : finalLower
            }
            if trend == 1, close[i] < finalLower {
                trend = -1
            } else if trend == -1, close[i] > finalUpper {
                trend = 1
            }
            line[i] = trend == 1 ? finalLower : finalUpper
            direction[i] = trend
        }
        return Supertrend(line: line, direction: direction)
    }

    // MARK: - Volume

    public static func obv(close: Series, volume: Series) -> Series {
        var out = Series(repeating: 0, count: close.count)
        for i in stride(from: 1, to: close.count, by: 1) {
            let sign: Double = close[i] > close[i - 1] ? 1 : (close[i] < close[i - 1] ? -1 : 0)
            out[i] = out[i - 1] + sign * volume[i]
        }
        return out
    }

    /// Volume-weighted average price, reset at the start of each day in `timeZone`.
    public static func vwap(high: Series, low: Series, close: Series, volume: Series, time: [Date], timeZone: TimeZone) -> Series {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let tp = typicalPrice(high: high, low: low, close: close)
        var out = Series(repeating: .nan, count: close.count)
        var day: DateComponents?
        var priceVolume = 0.0
        var totalVolume = 0.0
        for i in close.indices {
            let components = calendar.dateComponents([.year, .month, .day], from: time[i])
            if components != day {
                day = components
                priceVolume = 0
                totalVolume = 0
            }
            let v = volume[i] > 0 ? volume[i] : 1
            priceVolume += tp[i] * v
            totalVolume += v
            out[i] = priceVolume / totalVolume
        }
        return out
    }

    public static func typicalPrice(high: Series, low: Series, close: Series) -> Series {
        close.indices.map { (high[$0] + low[$0] + close[$0]) / 3 }
    }

    // MARK: - Events

    public static func crossover(_ a: Series, _ b: Series) -> Series {
        cross(a, b) { $0 > $1 && $2 <= $3 }
    }

    public static func crossunder(_ a: Series, _ b: Series) -> Series {
        cross(a, b) { $0 < $1 && $2 >= $3 }
    }

    static func cross(_ a: Series, _ b: Series, _ rule: (Double, Double, Double, Double) -> Bool) -> Series {
        var out = Series(repeating: 0, count: a.count)
        for i in stride(from: 1, to: a.count, by: 1) {
            let values = [a[i], b[i], a[i - 1], b[i - 1]]
            if values.contains(where: \.isNaN) { continue }
            out[i] = rule(a[i], b[i], a[i - 1], b[i - 1]) ? 1 : 0
        }
        return out
    }

    /// Number of bars since `condition` was last true (`.nan` before the first time).
    public static func barssince(_ condition: Series) -> Series {
        var last: Int?
        return condition.indices.map { i in
            if condition[i].isTruthy { last = i }
            return last.map { Double(i - $0) } ?? .nan
        }
    }

    /// Value of `source` at the `occurrence`-th most recent bar where `condition` was true.
    public static func valuewhen(_ condition: Series, _ source: Series, _ occurrence: Int = 0) -> Series {
        var hits: [Double] = []
        return condition.indices.map { i in
            if condition[i].isTruthy { hits.append(source[i]) }
            return hits.count > occurrence ? hits[hits.count - 1 - occurrence] : .nan
        }
    }

    /// 1 when `source` is above every value of the previous `length` bars.
    public static func rising(_ source: Series, _ length: Int) -> Series {
        let previous = highest(shift(source, 1), length)
        return zip(source, previous).map { $1.isNaN ? 0 : ($0 > $1 ? 1 : 0) }
    }

    public static func falling(_ source: Series, _ length: Int) -> Series {
        let previous = lowest(shift(source, 1), length)
        return zip(source, previous).map { $1.isNaN ? 0 : ($0 < $1 ? 1 : 0) }
    }

    /// Swing high confirmed `right` bars later. The value is reported on the
    /// confirmation bar (not the pivot bar), so it never leaks future data.
    public static func pivothigh(_ source: Series, left: Int, right: Int) -> Series {
        pivot(source, left: left, right: right, >)
    }

    public static func pivotlow(_ source: Series, left: Int, right: Int) -> Series {
        pivot(source, left: left, right: right, <)
    }

    static func pivot(_ source: Series, left: Int, right: Int, _ beats: (Double, Double) -> Bool) -> Series {
        var out = Series(repeating: .nan, count: source.count)
        for i in source.indices {
            let p = i - right
            guard p - left >= 0 else { continue }
            let candidate = source[p]
            if candidate.isNaN { continue }
            var isPivot = true
            for j in (p - left)...i where j != p {
                if source[j].isNaN || !beats(candidate, source[j]) {
                    isPivot = false
                    break
                }
            }
            if isPivot { out[i] = candidate }
        }
        return out
    }
}

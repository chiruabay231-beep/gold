import Foundation

/// 24-hour rolling statistics of a symbol.
public struct Ticker24h: Equatable, Sendable {
    public var symbol: String
    public var lastPrice: Double
    public var changePercent: Double
    public var high: Double
    public var low: Double
    /// Volume in the base asset (e.g. BTC).
    public var volume: Double
    /// Volume in the quote asset (e.g. USDT).
    public var quoteVolume: Double

    public init(symbol: String, lastPrice: Double, changePercent: Double, high: Double, low: Double,
                volume: Double, quoteVolume: Double) {
        self.symbol = symbol
        self.lastPrice = lastPrice
        self.changePercent = changePercent
        self.high = high
        self.low = low
        self.volume = volume
        self.quoteVolume = quoteVolume
    }

    /// From `GET /api/v3/ticker/24hr`.
    init?(restJSON data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? { (object[key] as? String).flatMap(Double.init) }
        guard let last = number("lastPrice"), let change = number("priceChangePercent"),
              let high = number("highPrice"), let low = number("lowPrice") else { return nil }
        self.init(symbol: object["symbol"] as? String ?? "", lastPrice: last, changePercent: change,
                  high: high, low: low, volume: number("volume") ?? 0, quoteVolume: number("quoteVolume") ?? 0)
    }
}

/// One trade: the building block of seconds bars.
public struct TradeTick: Equatable, Sendable {
    public var time: Date
    public var price: Double
    public var quantity: Double

    public init(time: Date, price: Double, quantity: Double) {
        self.time = time
        self.price = price
        self.quantity = quantity
    }
}

/// Builds bars of any length in seconds from trades or shorter bars.
public enum CandleAggregator {
    /// Start of the bar that contains `time` (bars aligned to the Unix epoch).
    public static func bucket(_ time: Date, seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: floor(time.timeIntervalSince1970 / seconds) * seconds)
    }

    public static func candles(from trades: [TradeTick], seconds: TimeInterval) -> [Candle] {
        var buffer = LiveCandleBuffer(maxCount: Int.max)
        for trade in trades.sorted(by: { $0.time < $1.time }) { buffer.apply(trade: trade, seconds: seconds) }
        return buffer.candles
    }

    /// Merges shorter bars (e.g. 1s klines) into bars of `seconds`.
    public static func resample(_ candles: [Candle], seconds: TimeInterval) -> [Candle] {
        var result: [Candle] = []
        for c in candles {
            let start = bucket(c.time, seconds: seconds)
            if var last = result.last, last.time == start {
                last.high = max(last.high, c.high)
                last.low = min(last.low, c.low)
                last.close = c.close
                last.volume += c.volume
                result[result.count - 1] = last
            } else {
                result.append(Candle(time: start, open: c.open, high: c.high, low: c.low, close: c.close, volume: c.volume))
            }
        }
        return result
    }
}

/// Messages from Binance's public WebSocket market streams.
public enum BinanceStreamEvent: Equatable, Sendable {
    /// A candle update. `isClosed` is true once for the final state of a bar.
    case kline(symbol: String, candle: Candle, isClosed: Bool)
    case ticker(Ticker24h)
    case trade(symbol: String, TradeTick)
    /// Best bid and ask (the spread).
    case book(symbol: String, bid: Double, ask: Double)

    /// URL of a combined stream with the kline (or, for seconds bars, the
    /// trades), the 24h ticker and the best bid/ask of one symbol.
    public static func url(host: URL, symbol: String, interval: BinanceClient.Interval) -> URL {
        let name = symbol.lowercased()
        let bars = interval.isSeconds ? "\(name)@aggTrade" : "\(name)@kline_\(interval.rawValue)"
        return URL(string: "\(host.absoluteString)/stream?streams=\(bars)/\(name)@ticker/\(name)@bookTicker")!
    }

    /// Parses a raw stream message, with or without the combined-stream wrapper.
    public static func parse(_ data: Data) -> BinanceStreamEvent? {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let inner = object["data"] as? [String: Any] { object = inner }
        func number(_ dictionary: [String: Any], _ key: String) -> Double? {
            if let text = dictionary[key] as? String { return Double(text) }
            return (dictionary[key] as? NSNumber)?.doubleValue
        }
        switch object["e"] as? String {
        case "kline":
            guard let k = object["k"] as? [String: Any],
                  let start = number(k, "t"), let open = number(k, "o"), let high = number(k, "h"),
                  let low = number(k, "l"), let close = number(k, "c")
            else { return nil }
            let candle = Candle(time: Date(timeIntervalSince1970: start / 1000), open: open, high: high,
                                low: low, close: close, volume: number(k, "v") ?? 0)
            let closed = (k["x"] as? Bool) ?? ((k["x"] as? NSNumber)?.boolValue ?? false)
            return .kline(symbol: object["s"] as? String ?? "", candle: candle, isClosed: closed)
        case "aggTrade":
            guard let price = number(object, "p"), let time = number(object, "T") else { return nil }
            return .trade(symbol: object["s"] as? String ?? "",
                          TradeTick(time: Date(timeIntervalSince1970: time / 1000), price: price,
                                    quantity: number(object, "q") ?? 0))
        case "24hrTicker":
            guard let last = number(object, "c"), let change = number(object, "P"),
                  let high = number(object, "h"), let low = number(object, "l")
            else { return nil }
            return .ticker(Ticker24h(symbol: object["s"] as? String ?? "", lastPrice: last, changePercent: change,
                                     high: high, low: low, volume: number(object, "v") ?? 0,
                                     quoteVolume: number(object, "q") ?? 0))
        case "bookTicker", nil:
            // Futures send "e":"bookTicker"; spot book tickers have no event type.
            guard let bid = number(object, "b"), let ask = number(object, "a"), let symbol = object["s"] as? String
            else { return nil }
            return .book(symbol: symbol, bid: bid, ask: ask)
        default:
            return nil
        }
    }
}

/// Candles of a live chart: history plus the bar that is still forming.
public struct LiveCandleBuffer: Sendable {
    public private(set) var candles: [Candle]
    public var maxCount: Int

    public enum Update: Equatable {
        /// The forming bar changed.
        case updatedLast
        /// A new bar started.
        case appended
        /// Older than the last bar; dropped.
        case ignored
    }

    public init(candles: [Candle] = [], maxCount: Int = 2000) {
        self.candles = Array(candles.suffix(maxCount))
        self.maxCount = maxCount
    }

    /// Adds older bars in front of the history; returns how many were added.
    @discardableResult
    public mutating func prepend(_ older: [Candle]) -> Int {
        let first = candles.first?.time ?? .distantFuture
        let fresh = older.filter { $0.time < first }.sorted { $0.time < $1.time }
        let room = max(0, maxCount - candles.count)
        let added = Array(fresh.suffix(room))
        candles.insert(contentsOf: added, at: 0)
        return added.count
    }

    /// Adds a trade to the bar of `seconds` it falls in, starting a new bar when needed.
    @discardableResult
    public mutating func apply(trade: TradeTick, seconds: TimeInterval) -> Update {
        let start = CandleAggregator.bucket(trade.time, seconds: seconds)
        if var last = candles.last, last.time == start {
            last.high = max(last.high, trade.price)
            last.low = min(last.low, trade.price)
            last.close = trade.price
            last.volume += trade.quantity
            candles[candles.count - 1] = last
            return .updatedLast
        }
        return apply(Candle(time: start, open: trade.price, high: trade.price, low: trade.price,
                            close: trade.price, volume: trade.quantity))
    }

    @discardableResult
    public mutating func apply(_ candle: Candle) -> Update {
        guard let last = candles.last else {
            candles.append(candle)
            return .appended
        }
        if candle.time == last.time {
            candles[candles.count - 1] = candle
            return .updatedLast
        }
        guard candle.time > last.time else { return .ignored }
        candles.append(candle)
        if candles.count > maxCount { candles.removeFirst(candles.count - maxCount) }
        return .appended
    }
}

/// An entry or exit produced by a strategy on a closed bar.
public struct LiveSignal: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case longEntry, shortEntry, longExit, shortExit

        public var label: String {
            switch self {
            case .longEntry: return "MUA"
            case .shortEntry: return "BÁN"
            case .longExit: return "Đóng MUA"
            case .shortExit: return "Đóng BÁN"
            }
        }

        public var isEntry: Bool { self == .longEntry || self == .shortEntry }
    }

    public var id: String { "\(Int(time.timeIntervalSince1970))-\(kind.rawValue)" }
    public var time: Date
    public var barIndex: Int
    public var kind: Kind
    /// Close of the signal bar; the order would fill at the next open.
    public var price: Double
    public var stop: Double?
    public var target: Double?
}

/// Runs a strategy over closed bars and lists the signals it produced.
public enum LiveSignalScanner {
    public struct Scan: Sendable {
        public var signals: [LiveSignal]
        public var plots: [Plot]
    }

    public static func scan(strategy: StrategyDefinition, candles: [Candle], config: BacktestConfig,
                            library: FunctionLibrary, parameterValues: [String: Double] = [:]) throws -> Scan {
        let data = PriceData(candles: candles)
        let context = EvaluationContext(data: data, library: library, timeZone: config.timeZone)
        let s = try strategy.signals(context: context, values: parameterValues)
        func at(_ series: Series?, _ i: Int) -> Double? {
            guard let v = series?[i], v.isFinite, v > 0 else { return nil }
            return v
        }
        var signals: [LiveSignal] = []
        for i in candles.indices {
            let time = candles[i].time
            let close = candles[i].close
            if config.allowLong, s.longEntry?[i].isTruthy == true {
                signals.append(LiveSignal(time: time, barIndex: i, kind: .longEntry, price: close,
                                          stop: at(s.longStop, i), target: at(s.longTarget, i)))
            }
            if config.allowShort, s.shortEntry?[i].isTruthy == true {
                signals.append(LiveSignal(time: time, barIndex: i, kind: .shortEntry, price: close,
                                          stop: at(s.shortStop, i), target: at(s.shortTarget, i)))
            }
            if s.longExit?[i].isTruthy == true {
                signals.append(LiveSignal(time: time, barIndex: i, kind: .longExit, price: close))
            }
            if s.shortExit?[i].isTruthy == true {
                signals.append(LiveSignal(time: time, barIndex: i, kind: .shortExit, price: close))
            }
        }
        return Scan(signals: signals, plots: s.plots)
    }
}

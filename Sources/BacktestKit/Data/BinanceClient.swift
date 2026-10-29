import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads public kline (candlestick) data from Binance. No API key needed.
///
/// Useful symbols: `BTCUSDT`, `ETHUSDT`, `PAXGUSDT` (token backed by gold,
/// tracks XAUUSD closely).
public struct BinanceClient {
    public enum Interval: String, CaseIterable, Codable, Sendable {
        /// Seconds: Binance only has 1s klines (spot), so 5s–30s bars are
        /// built from trades; OANDA has S5–S30.
        case s5 = "5s", s10 = "10s", s15 = "15s", s30 = "30s"
        case m1 = "1m", m5 = "5m", m15 = "15m", m30 = "30m"
        case h1 = "1h", h4 = "4h", d1 = "1d", w1 = "1w"

        public var isSeconds: Bool { seconds < 60 }

        public var seconds: TimeInterval {
            switch self {
            case .s5: return 5
            case .s10: return 10
            case .s15: return 15
            case .s30: return 30
            case .m1: return 60
            case .m5: return 300
            case .m15: return 900
            case .m30: return 1800
            case .h1: return 3600
            case .h4: return 14_400
            case .d1: return 86_400
            case .w1: return 604_800
            }
        }
    }

    public enum ClientError: LocalizedError {
        case http(Int, String)
        case malformed

        public var errorDescription: String? {
            switch self {
            case .http(let code, let body):
                return "Binance trả về lỗi \(code): \(body)"
            case .malformed:
                return "Dữ liệu Binance không đúng định dạng."
            }
        }
    }

    /// Spot (BTCUSDT, PAXGUSDT…) or USDⓈ-M futures, which also list gold
    /// and silver perpetuals (XAUUSDT, XAGUSDT) priced from spot XAU/XAG.
    public enum Market: String, Sendable {
        case spot, futures

        /// Spot: main API first, then the public market-data mirror, which is
        /// reachable from some networks where api.binance.com is blocked.
        public var restHosts: [URL] {
            switch self {
            case .spot: return [URL(string: "https://api.binance.com")!, URL(string: "https://data-api.binance.vision")!]
            case .futures: return [URL(string: "https://fapi.binance.com")!]
            }
        }

        /// Futures: the dedicated market-data path first, then the legacy root.
        public var streamHosts: [URL] {
            switch self {
            case .spot: return [URL(string: "wss://stream.binance.com:9443")!, URL(string: "wss://data-stream.binance.vision")!]
            case .futures: return [URL(string: "wss://fstream.binance.com/market")!, URL(string: "wss://fstream.binance.com")!]
            }
        }

        var apiPrefix: String { self == .spot ? "api/v3" : "fapi/v1" }
    }

    public var baseURL: URL
    public var market: Market
    public var session: URLSession

    public static let restHosts = Market.spot.restHosts
    public static let streamHosts = Market.spot.streamHosts

    /// Runs `operation` against each REST host in turn until one succeeds.
    public static func withFallback<T>(market: Market = .spot, _ operation: (BinanceClient) async throws -> T) async throws -> T {
        var lastError: Error = ClientError.malformed
        for host in market.restHosts {
            do {
                return try await operation(BinanceClient(baseURL: host, market: market))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 24-hour statistics for the header of the live screen.
    public func fetchTicker(symbol: String) async throws -> Ticker24h {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(market.apiPrefix)/ticker/24hr"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased())]
        let (data, response) = try await load(URLRequest(url: components.url!))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let ticker = Ticker24h(restJSON: data) else { throw ClientError.malformed }
        return ticker
    }

    public init(baseURL: URL = URL(string: "https://api.binance.com")!, market: Market = .spot, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.market = market
        self.session = session
    }

    /// Fetches the most recent `count` candles, paging backwards 1000 at a time.
    public func fetchCandles(symbol: String, interval: Interval, count: Int) async throws -> [Candle] {
        try await fetchCandles(symbol: symbol, intervalName: interval.rawValue, count: count)
    }

    /// `count` candles that open before `before`, for loading older history.
    public func fetchCandles(symbol: String, interval: Interval, count: Int, before: Date) async throws -> [Candle] {
        try await fetchCandles(symbol: symbol, intervalName: interval.rawValue, count: count,
                               endTime: Int64(before.timeIntervalSince1970 * 1000) - 1)
    }

    /// Recent bars of a seconds interval. Spot: 1-second klines merged into
    /// bigger bars. Futures (no 1s klines): built from aggregate trades.
    public func fetchSecondCandles(symbol: String, seconds: TimeInterval, count: Int,
                                   maxTradePages: Int = 10) async throws -> [Candle] {
        switch market {
        case .spot:
            let oneSecond = try await fetchCandles(symbol: symbol, intervalName: "1s",
                                                   count: min(6000, Int(seconds) * count))
            return CandleAggregator.resample(oneSecond, seconds: seconds)
        case .futures:
            var trades: [TradeTick] = []
            var fromID: Int64?
            for _ in 0..<maxTradePages {
                let page = try await fetchAggTrades(symbol: symbol, fromID: fromID)
                guard let first = page.first else { break }
                trades.insert(contentsOf: page.map { $0.tick }, at: 0)
                guard first.id > 0 else { break }
                fromID = max(0, first.id - 1000)
                if CandleAggregator.candles(from: trades, seconds: seconds).count >= count { break }
            }
            return Array(CandleAggregator.candles(from: trades, seconds: seconds).suffix(count))
        }
    }

    /// Up to 1000 aggregate trades, the newest ones or starting at `fromID`.
    public func fetchAggTrades(symbol: String, fromID: Int64?) async throws -> [(id: Int64, tick: TradeTick)] {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(market.apiPrefix)/aggTrades"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "symbol", value: symbol.uppercased()), URLQueryItem(name: "limit", value: "1000")]
        if let fromID { items.append(URLQueryItem(name: "fromId", value: String(fromID))) }
        components.queryItems = items
        let (data, response) = try await load(URLRequest(url: components.url!))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.parseAggTrades(data)
    }

    /// `[{"a": id, "p": "price", "q": "qty", "T": ms, ...}]`
    public static func parseAggTrades(_ data: Data) throws -> [(id: Int64, tick: TradeTick)] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ClientError.malformed }
        return try rows.map { row in
            guard let id = (row["a"] as? NSNumber)?.int64Value,
                  let price = Double(row["p"] as? String ?? ""),
                  let time = (row["T"] as? NSNumber)?.doubleValue
            else { throw ClientError.malformed }
            return (id, TradeTick(time: Date(timeIntervalSince1970: time / 1000), price: price,
                                  quantity: Double(row["q"] as? String ?? "") ?? 0, atAsk: (row["m"] as? Bool) == false))
        }
    }

    func fetchCandles(symbol: String, intervalName: String, count: Int, endTime start: Int64? = nil) async throws -> [Candle] {
        var result: [Candle] = []
        var endTime: Int64? = start
        while result.count < count {
            let batch = min(1000, count - result.count)
            let page = try await fetchPage(symbol: symbol, intervalName: intervalName, limit: batch, endTime: endTime)
            if page.isEmpty { break }
            result.insert(contentsOf: page, at: 0)
            endTime = Int64(page[0].time.timeIntervalSince1970 * 1000) - 1
            if page.count < batch { break }
        }
        return CSVParser.normalize(result)
    }

    func fetchPage(symbol: String, intervalName: String, limit: Int, endTime: Int64?) async throws -> [Candle] {
        var components = URLComponents(url: baseURL.appendingPathComponent("\(market.apiPrefix)/klines"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "symbol", value: symbol.uppercased()),
            URLQueryItem(name: "interval", value: intervalName),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let endTime { items.append(URLQueryItem(name: "endTime", value: String(endTime))) }
        components.queryItems = items
        let (data, response) = try await load(URLRequest(url: components.url!))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.parseKlines(data)
    }

    /// Binance klines are arrays: `[openTime, "open", "high", "low", "close", "volume", closeTime, ...]`.
    public static func parseKlines(_ data: Data) throws -> [Candle] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw ClientError.malformed
        }
        return try rows.map { row in
            guard row.count >= 6,
                  let openTime = (row[0] as? NSNumber)?.doubleValue,
                  let open = Double(row[1] as? String ?? ""),
                  let high = Double(row[2] as? String ?? ""),
                  let low = Double(row[3] as? String ?? ""),
                  let close = Double(row[4] as? String ?? ""),
                  let volume = Double(row[5] as? String ?? "")
            else { throw ClientError.malformed }
            return Candle(time: Date(timeIntervalSince1970: openTime / 1000),
                          open: open, high: high, low: low, close: close, volume: volume)
        }
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: ClientError.malformed)
                }
            }.resume()
        }
    }
}

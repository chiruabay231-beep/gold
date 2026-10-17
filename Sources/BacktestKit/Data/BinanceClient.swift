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
        case m1 = "1m", m5 = "5m", m15 = "15m", m30 = "30m"
        case h1 = "1h", h4 = "4h", d1 = "1d", w1 = "1w"

        public var seconds: TimeInterval {
            switch self {
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

    public var baseURL: URL
    public var session: URLSession

    /// Main API first, then the public market-data mirror, which is reachable
    /// from some networks where api.binance.com is blocked.
    public static let restHosts = [URL(string: "https://api.binance.com")!,
                                   URL(string: "https://data-api.binance.vision")!]
    public static let streamHosts = [URL(string: "wss://stream.binance.com:9443")!,
                                     URL(string: "wss://data-stream.binance.vision")!]

    /// Runs `operation` against each REST host in turn until one succeeds.
    public static func withFallback<T>(_ operation: (BinanceClient) async throws -> T) async throws -> T {
        var lastError: Error = ClientError.malformed
        for host in restHosts {
            do {
                return try await operation(BinanceClient(baseURL: host))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 24-hour statistics for the header of the live screen.
    public func fetchTicker(symbol: String) async throws -> Ticker24h {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v3/ticker/24hr"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased())]
        let (data, response) = try await load(URLRequest(url: components.url!))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let ticker = Ticker24h(restJSON: data) else { throw ClientError.malformed }
        return ticker
    }

    public init(baseURL: URL = URL(string: "https://api.binance.com")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Fetches the most recent `count` candles, paging backwards 1000 at a time.
    public func fetchCandles(symbol: String, interval: Interval, count: Int) async throws -> [Candle] {
        var result: [Candle] = []
        var endTime: Int64?
        while result.count < count {
            let batch = min(1000, count - result.count)
            let page = try await fetchPage(symbol: symbol, interval: interval, limit: batch, endTime: endTime)
            if page.isEmpty { break }
            result.insert(contentsOf: page, at: 0)
            endTime = Int64(page[0].time.timeIntervalSince1970 * 1000) - 1
            if page.count < batch { break }
        }
        return CSVParser.normalize(result)
    }

    func fetchPage(symbol: String, interval: Interval, limit: Int, endTime: Int64?) async throws -> [Candle] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v3/klines"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "symbol", value: symbol.uppercased()),
            URLQueryItem(name: "interval", value: interval.rawValue),
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

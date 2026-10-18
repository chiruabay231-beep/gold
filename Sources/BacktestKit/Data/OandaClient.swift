import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A candle from OANDA together with whether its bar has finished.
public struct OandaCandle: Equatable, Sendable {
    public var candle: Candle
    public var complete: Bool
}

/// Reads candles from the OANDA v20 REST API (XAU_USD, forex, indices).
/// Needs a personal access token from an fxTrade or fxTrade Practice account.
public struct OandaClient {
    public enum Environment: String, CaseIterable, Codable, Sendable {
        /// fxTrade Practice (demo) account.
        case practice
        /// fxTrade (real money) account.
        case live

        public var restURL: URL {
            switch self {
            case .practice: return URL(string: "https://api-fxpractice.oanda.com")!
            case .live: return URL(string: "https://api-fxtrade.oanda.com")!
            }
        }

        public var title: String {
            switch self {
            case .practice: return "Demo (Practice)"
            case .live: return "Live (tiền thật)"
            }
        }
    }

    public enum ClientError: LocalizedError, Equatable {
        case missingToken
        case unauthorized(String)
        case http(Int, String)
        case malformed

        public var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Chưa nhập token OANDA."
            case .unauthorized(let message):
                return "Token OANDA không hợp lệ hoặc sai môi trường Demo/Live. \(message)"
            case .http(let code, let message):
                return "OANDA trả về lỗi \(code): \(message)"
            case .malformed:
                return "Dữ liệu OANDA không đúng định dạng."
            }
        }
    }

    /// Instruments shown in the symbol menu.
    public static let instruments = ["XAU_USD", "XAG_USD", "EUR_USD", "GBP_USD", "USD_JPY",
                                     "NAS100_USD", "US30_USD", "SPX500_USD"]

    public var environment: Environment
    public var token: String
    public var session: URLSession

    public init(environment: Environment, token: String, session: URLSession = .shared) {
        self.environment = environment
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    /// Personal access tokens are two 32-character hex groups joined by "-".
    public static func looksLikeToken(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { $0.count == 32 && $0.allSatisfy(\.isHexDigit) }
    }

    /// OANDA's name for an interval: M1, M5, M15, M30, H1, H4, D, W.
    public static func granularity(_ interval: BinanceClient.Interval) -> String {
        switch interval {
        case .s5: return "S5"
        case .s10: return "S10"
        case .s15: return "S15"
        case .s30: return "S30"
        case .m1: return "M1"
        case .m5: return "M5"
        case .m15: return "M15"
        case .m30: return "M30"
        case .h1: return "H1"
        case .h4: return "H4"
        case .d1: return "D"
        case .w1: return "W"
        }
    }

    /// IDs of the accounts the token can access; used to check the token.
    public func fetchAccounts() async throws -> [String] {
        let data = try await get("v3/accounts", query: [])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = object["accounts"] as? [[String: Any]] else { throw ClientError.malformed }
        return accounts.compactMap { $0["id"] as? String }
    }

    /// The most recent `count` candles (at most 5000) built from bid prices,
    /// the same prices MT4/MT5 charts show.
    public func fetchCandles(instrument: String, interval: BinanceClient.Interval, count: Int) async throws -> [OandaCandle] {
        let data = try await get("v3/instruments/\(instrument)/candles", query: [
            URLQueryItem(name: "granularity", value: Self.granularity(interval)),
            URLQueryItem(name: "count", value: String(max(1, min(5000, count)))),
            URLQueryItem(name: "price", value: "B"),
        ])
        return try Self.parseCandles(data)
    }

    /// Parses `GET /v3/instruments/{instrument}/candles` with UNIX timestamps.
    public static func parseCandles(_ data: Data) throws -> [OandaCandle] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["candles"] as? [[String: Any]] else { throw ClientError.malformed }
        func number(_ dictionary: [String: Any], _ key: String) -> Double? {
            if let text = dictionary[key] as? String { return Double(text) }
            return (dictionary[key] as? NSNumber)?.doubleValue
        }
        return try rows.map { row in
            guard let time = number(row, "time"),
                  let prices = (row["bid"] ?? row["mid"] ?? row["ask"]) as? [String: Any],
                  let open = number(prices, "o"), let high = number(prices, "h"),
                  let low = number(prices, "l"), let close = number(prices, "c")
            else { throw ClientError.malformed }
            let candle = Candle(time: Date(timeIntervalSince1970: time), open: open, high: high, low: low,
                                close: close, volume: number(row, "volume") ?? 0)
            return OandaCandle(candle: candle, complete: (row["complete"] as? Bool) ?? true)
        }
    }

    /// Daily change for the header: last price against the previous daily close.
    public func fetchTicker(instrument: String) async throws -> Ticker24h {
        let days = try await fetchCandles(instrument: instrument, interval: .d1, count: 2)
        guard let today = days.last?.candle else { throw ClientError.malformed }
        let previousClose = days.count > 1 ? days[days.count - 2].candle.close : today.open
        let change = previousClose > 0 ? (today.close - previousClose) / previousClose * 100 : 0
        return Ticker24h(symbol: instrument, lastPrice: today.close, changePercent: change,
                         high: today.high, low: today.low, volume: today.volume, quoteVolume: 0)
    }

    private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        guard !token.isEmpty else { throw ClientError.missingToken }
        var components = URLComponents(url: environment.restURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("UNIX", forHTTPHeaderField: "Accept-Datetime-Format")
        request.timeoutInterval = 15
        let (data, response) = try await load(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = Self.errorMessage(data)
            if http.statusCode == 401 || http.statusCode == 403 { throw ClientError.unauthorized(message) }
            throw ClientError.http(http.statusCode, message)
        }
        return data
    }

    static func errorMessage(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["errorMessage"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? ""
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

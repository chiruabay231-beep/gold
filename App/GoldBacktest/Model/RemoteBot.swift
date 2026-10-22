import Foundation
import Observation
import Security
import CryptoKit
import BacktestKit

/// Address (UserDefaults) and password (Keychain, this device only) of the VPS bot server.
enum RemoteBotSettings {
    private static let urlKey = "vps.url"
    private static let service = "GoldBacktest.vps"
    private static let account = "password"

    static var url: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: urlKey) }
    }

    static var password: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    static func savePassword(_ password: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func client() -> RemoteBotClient? {
        guard let password, let url = RemoteBotClient.normalizedURL(url) else { return nil }
        return RemoteBotClient(baseURL: url, password: password)
    }
}

/// What the server reports on /status.
struct RemoteStatus: Decodable {
    struct Settings: Decodable {
        var source = "binance_futures"
        var symbol = "XAUUSDT"
        var interval = "1m"
        var broker = "paper"
        var strategyName = ""
        var lots = 0.01
        var riskPercent = 0.0
        var allowLong = true
        var allowShort = true
        var reverse = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Settings()
            source = try c.decodeIfPresent(String.self, forKey: .source) ?? d.source
            symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? d.symbol
            interval = try c.decodeIfPresent(String.self, forKey: .interval) ?? d.interval
            broker = try c.decodeIfPresent(String.self, forKey: .broker) ?? d.broker
            strategyName = try c.decodeIfPresent(String.self, forKey: .strategyName) ?? d.strategyName
            lots = try c.decodeIfPresent(Double.self, forKey: .lots) ?? d.lots
            riskPercent = try c.decodeIfPresent(Double.self, forKey: .riskPercent) ?? d.riskPercent
            allowLong = try c.decodeIfPresent(Bool.self, forKey: .allowLong) ?? d.allowLong
            allowShort = try c.decodeIfPresent(Bool.self, forKey: .allowShort) ?? d.allowShort
            reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse) ?? d.reverse
        }

        private enum CodingKeys: String, CodingKey {
            case source, symbol, interval, broker, strategyName, lots, riskPercent, allowLong, allowShort, reverse
        }
    }

    struct Account: Decodable {
        var mode: String?
        var balance: Double?
        var equity: Double?
        var openProfit: Double?
        var currency: String?
        var login: Int?
        var server: String?
        var error: String?
    }

    struct Position: Decodable, Identifiable {
        var id: String
        var symbol: String
        var side: String
        var lots: Double
        var entryPrice: Double
        var stop: Double?
        var target: Double?
        var openTime: Double?
        var profit: Double?

        var isLong: Bool { side == "long" }
    }

    struct Telegram: Decodable {
        var configured: Bool?
        var linked: Bool?
    }

    struct MT5: Decodable {
        var error: String?
        var connected: Bool?
        var tradingEnabled: Bool?
        var maxLots: Double?
    }

    var version: String?
    var running: Bool
    var settings: Settings?
    var price: Double?
    var bars: Int?
    var lastBarTime: Double?
    var error: String?
    var tunnelURL: String?
    var account: Account?
    var positions: [Position]?
    var telegram: Telegram?
    var mt5: MT5?
}

struct RemoteLogEntry: Decodable, Identifiable {
    var time: Double
    var text: String
    var id: String { "\(time)-\(text)" }
}

struct RemoteTrade: Decodable, Identifiable {
    var id: String
    var symbol: String
    var side: String
    var lots: Double?
    var exitPrice: Double?
    var exitTime: Double?
    var profit: Double?
    var reason: String?

    var uniqueID: String { "\(id)-\(exitTime ?? 0)" }
}

/// Settings sent with /start.
struct RemoteStartRequest: Encodable {
    var source: String
    var symbol: String
    var interval: String
    var broker: String
    var strategy: StrategyDefinition
    var strategyName: String
    var indicators: [CustomIndicator]
    var config: BacktestConfig
    var lots: Double
    var riskPercent: Double
    var allowLong: Bool
    var allowShort: Bool
    var reverse: Bool
    var rules: TradeManagement
}

/// HTTP client for bot-server/bot_server.py.
struct RemoteBotClient {
    var baseURL: URL
    var password: String

    struct ServerError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Accepts "abc.trycloudflare.com" or a full URL.
    static func normalizedURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        guard let url = URL(string: t), url.host != nil else { return nil }
        return url
    }

    func send(_ path: String, method: String = "GET", body: Data? = nil,
                          timeout: TimeInterval = 25) async throws -> Data {
        try await request(path, method: method, body: body, timeout: timeout)
    }

    /// The server could not be reached at this address (VPS off, or a new address).
    private struct Unreachable: Error { var code: Int }

    /// One request; when the address no longer answers, the server's new address is
    /// looked up (the VPS posts it to ntfy.sh) and the request sent again there.
    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         timeout: TimeInterval = 25) async throws -> Data {
        do {
            return try await attempt(path, method: method, body: body, timeout: timeout)
        } catch let failure as Unreachable {
            if let moved = await URLRelay.shared.newAddress(password: password, current: baseURL) {
                var retry = self
                retry.baseURL = moved
                if let data = try? await retry.attempt(path, method: method, body: body, timeout: timeout) {
                    return data
                }
            }
            throw ServerError(message: failure.code == 0
                ? "Không kết nối được máy chủ VPS. Nếu VPS vừa khởi động lại, app sẽ tự tìm địa chỉ mới sau ít phút."
                : "Bot trên VPS không chạy (lỗi \(failure.code)). Đợi 1–2 phút nếu vừa cập nhật; nếu vẫn lỗi, khởi động lại VPS (bot tự chạy lại và app tự tìm địa chỉ mới).")
        }
    }

    private func attempt(_ path: String, method: String, body: Data?, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw ServerError(message: "Địa chỉ không hợp lệ") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Unreachable(code: 0)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return data }
        struct Failure: Decodable { var error: String? }
        if let failure = try? JSONDecoder().decode(Failure.self, from: data), let message = failure.error {
            throw ServerError(message: message)
        }
        switch code {
        case 401: throw ServerError(message: "Sai mật khẩu máy chủ")
        // Cloudflare answers but nothing behind this address (bot down or tunnel gone).
        case 502, 530: throw Unreachable(code: code)
        default: throw ServerError(message: "Máy chủ trả lỗi \(code)")
        }
    }

    func status() async throws -> RemoteStatus {
        try JSONDecoder().decode(RemoteStatus.self, from: await request("/status"))
    }

    func start(_ settings: RemoteStartRequest) async throws -> RemoteStatus {
        let body = try JSONEncoder().encode(settings)
        return try JSONDecoder().decode(RemoteStatus.self, from: await request("/start", method: "POST", body: body))
    }

    /// Starts again with the settings the VPS bot last ran with.
    func resume() async throws -> RemoteStatus {
        try JSONDecoder().decode(RemoteStatus.self, from: await request("/start", method: "POST", body: Data("{}".utf8)))
    }

    func stop() async throws -> RemoteStatus {
        try JSONDecoder().decode(RemoteStatus.self, from: await request("/stop", method: "POST", body: Data("{}".utf8)))
    }

    func close(positionID: String?) async throws -> RemoteStatus {
        let object: [String: Any] = positionID.map { ["id": $0] } ?? ["all": true]
        let body = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(RemoteStatus.self, from: await request("/close", method: "POST", body: body))
    }

    func log(limit: Int = 60) async throws -> [RemoteLogEntry] {
        struct Response: Decodable { var log: [RemoteLogEntry] }
        return try JSONDecoder().decode(Response.self, from: await request("/log?limit=\(limit)")).log
    }

    func history(limit: Int = 30) async throws -> [RemoteTrade] {
        struct Response: Decodable { var history: [RemoteTrade] }
        return try JSONDecoder().decode(Response.self, from: await request("/history?limit=\(limit)")).history
    }

    func testTelegram() async throws {
        _ = try await request("/telegram-test", method: "POST", body: Data("{}".utf8))
    }

    // MARK: - MT5 account and market data (Exness or any MT5 broker on the VPS)

    /// Encodes a query value; symbols can contain "#", "&" or "+".
    static func queryValue(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
    }

    func mt5Status() async throws -> MT5AccountStatus {
        // Starting the MT5 terminal can take a while the first time.
        try JSONDecoder().decode(MT5AccountStatus.self, from: await request("/mt5/status", timeout: 60))
    }

    func mt5Login(login: String, password: String, server: String, remember: Bool) async throws -> MT5AccountStatus {
        let object: [String: Any] = ["login": login, "password": password, "server": server, "remember": remember]
        let body = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(MT5AccountStatus.self, from: await request("/mt5/login", method: "POST", body: body, timeout: 90))
    }

    func mt5Logout() async throws {
        _ = try await request("/mt5/logout", method: "POST", body: Data("{}".utf8))
    }

    func mt5Symbols(query: String) async throws -> [MT5Symbol] {
        struct Response: Decodable { var symbols: [MT5Symbol] }
        let q = Self.queryValue(query)
        return try JSONDecoder().decode(Response.self, from: await request("/mt5/symbols?q=\(q)&limit=150")).symbols
    }

    /// Bars of `symbol`; the newest is still forming unless `before` is given.
    func mt5Candles(symbol: String, interval: BinanceClient.Interval, count: Int, before: Date? = nil) async throws -> [Candle] {
        try await mt5Bars(symbol: symbol, interval: interval, count: count, before: before).candles
    }

    /// Bars plus the current bid and ask.
    func mt5Bars(symbol: String, interval: BinanceClient.Interval, count: Int,
                 before: Date? = nil) async throws -> (candles: [Candle], bid: Double?, ask: Double?) {
        struct Response: Decodable {
            var candles: [[Double]]
            var bid: Double?
            var ask: Double?
        }
        let s = Self.queryValue(symbol)
        var path = "/mt5/candles?symbol=\(s)&interval=\(interval.rawValue)&count=\(count)"
        if let before { path += "&before=\(Int(before.timeIntervalSince1970))" }
        let response = try JSONDecoder().decode(Response.self, from: await request(path, timeout: 15))
        let candles = response.candles.compactMap { r -> Candle? in
            guard r.count >= 5 else { return nil }
            return Candle(time: Date(timeIntervalSince1970: r[0]), open: r[1], high: r[2], low: r[3], close: r[4],
                          volume: r.count > 5 ? r[5] : 0)
        }
        return (candles, response.bid, response.ask)
    }
}

extension RemoteBotClient {
    // MARK: - Trading the MT5 account by hand

    private func post<T: Decodable>(_ path: String, _ object: [String: Any], as type: T.Type) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(T.self, from: await send(path, method: "POST", body: body))
    }

    func mt5Trading(symbol: String? = nil) async throws -> MT5TradingState {
        let path = symbol.map { "/mt5/trading?symbol=\(Self.queryValue($0))" } ?? "/mt5/trading"
        return try JSONDecoder().decode(MT5TradingState.self, from: await send(path, timeout: 15))
    }

    /// Market order, or a pending one at `price` (limit/stop chosen by the server from the side and price).
    func mt5Order(symbol: String, side: PaperAccount.Side, lots: Double, price: Double? = nil,
                  stop: Double?, target: Double?) async throws -> MT5TradingState {
        var object: [String: Any] = ["symbol": symbol, "side": side.rawValue, "lots": lots,
                                     "type": price == nil ? "market" : "pending"]
        if let price { object["price"] = price }
        if let stop { object["stop"] = stop }
        if let target { object["target"] = target }
        return try await post("/mt5/order", object, as: MT5TradingState.self)
    }

    /// Closes a position, or `lots` of it.
    func mt5Close(ticket: Int, lots: Double? = nil) async throws -> MT5TradingState {
        var object: [String: Any] = ["ticket": ticket]
        if let lots { object["lots"] = lots }
        return try await post("/mt5/close", object, as: MT5TradingState.self)
    }

    /// New SL/TP of a position, or new entry/SL/TP of a pending order. nil removes SL or TP.
    func mt5Modify(ticket: Int, price: Double? = nil, stop: Double?, target: Double?) async throws -> MT5TradingState {
        var object: [String: Any] = ["ticket": ticket]
        if let price { object["price"] = price }
        if let stop { object["stop"] = stop }
        if let target { object["target"] = target }
        return try await post("/mt5/modify", object, as: MT5TradingState.self)
    }

    func mt5Cancel(ticket: Int) async throws -> MT5TradingState {
        try await post("/mt5/cancel", ["ticket": ticket], as: MT5TradingState.self)
    }

    func mt5Settings(tradingEnabled: Bool, allowReal: Bool, maxLots: Double) async throws -> MT5TradingState {
        try await post("/mt5/settings", ["trading_enabled": tradingEnabled, "allow_real_account": allowReal,
                                         "max_lots": maxLots], as: MT5TradingState.self)
    }
}

/// Positions, pending orders and today's closed deals of the MT5 account.
struct MT5TradingState: Decodable {
    struct Position: Decodable, Identifiable {
        var ticket: Int
        var symbol: String
        var side: String
        var lots: Double
        var entry: Double
        var price: Double?
        var stop: Double?
        var target: Double?
        var profit: Double
        var time: Double
        var bot: Bool?
        var id: Int { ticket }
        var paperSide: PaperAccount.Side { side == "long" ? .long : .short }
    }

    struct Order: Decodable, Identifiable {
        var ticket: Int
        var symbol: String
        var side: String
        var kind: String
        var lots: Double
        var entry: Double
        var stop: Double?
        var target: Double?
        var id: Int { ticket }
        var paperSide: PaperAccount.Side { side == "long" ? .long : .short }
    }

    struct Deal: Decodable, Identifiable {
        var ticket: Int
        var position: Int
        var symbol: String
        var side: String
        var lots: Double
        var price: Double
        var profit: Double
        var time: Double
        var reason: String
        var id: Int { ticket }
    }

    var positions: [Position]
    var orders: [Order]
    var deals: [Deal]
    var balance: Double?
    var equity: Double?
    var margin: Double?
    var marginFree: Double?
    var marginLevel: Double?
    var profit: Double?
    var leverage: Int?
    var server: String?
    var currency: String?
    var login: Int?
    var mode: String?
    var tradingEnabled: Bool
    var allowReal: Bool
    var maxLots: Double
    /// The order just sent (answer to /mt5/order).
    var ticket: Int?
}

/// The MT5 account logged in on the VPS.
struct MT5AccountStatus: Decodable {
    var connected: Bool
    var error: String?
    var login: Int?
    var server: String?
    var name: String?
    var company: String?
    var currency: String?
    var balance: Double?
    var equity: Double?
    var leverage: Int?
    var mode: String?
    var tradeAllowed: Bool?
    var terminal: String?
    var remembered: Bool?
}

struct MT5Symbol: Decodable, Identifiable, Hashable {
    var name: String
    var description: String
    var path: String
    var digits: Int?
    var id: String { name }
}

/// The VPS bot as seen from the app, refreshed while its screen is open.
@MainActor
@Observable
final class RemoteBot {
    private(set) var status: RemoteStatus?
    private(set) var log: [RemoteLogEntry] = []
    private(set) var history: [RemoteTrade] = []
    private(set) var error: String?
    private(set) var isBusy = false
    private(set) var lastUpdate: Date?

    var isConfigured: Bool { RemoteBotSettings.client() != nil }

    func refresh() async {
        guard let client = RemoteBotSettings.client() else {
            status = nil
            error = nil
            return
        }
        do {
            let status = try await client.status()
            self.status = status
            log = try await client.log()
            history = try await client.history()
            error = nil
            lastUpdate = Date()
        } catch {
            status = nil
            self.error = error.localizedDescription
        }
    }

    /// Refreshes every few seconds until the calling task is cancelled.
    func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func perform(_ action: (RemoteBotClient) async throws -> RemoteStatus) async {
        guard let client = RemoteBotSettings.client() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            status = try await action(client)
            error = nil
            log = (try? await client.log()) ?? log
        } catch {
            self.error = error.localizedDescription
        }
    }

    func start(_ settings: RemoteStartRequest) async { await perform { try await $0.start(settings) } }
    func resume() async { await perform { try await $0.resume() } }
    func stop() async { await perform { try await $0.stop() } }

    /// Only the status, for the bot button on the chart.
    func refreshStatus() async {
        guard let client = RemoteBotSettings.client() else {
            status = nil
            return
        }
        do {
            status = try await client.status()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    func close(_ position: RemoteStatus.Position?) async { await perform { try await $0.close(positionID: position?.id) } }

    func testTelegram() async {
        guard let client = RemoteBotSettings.client() else { return }
        do { try await client.testTelegram() } catch { self.error = error.localizedDescription }
    }
}

/// Finds the VPS again when its trycloudflare address changes: the server posts
/// the address to an ntfy.sh topic only the owner's password (or a member's code)
/// can work out, and the app reads it there and saves it.
actor URLRelay {
    static let shared = URLRelay()
    static let base = "https://ntfy.sh"

    private var lastLookup: [String: Date] = [:]

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Same as the server's relay_topic().
    static func topic(password: String) -> (topic: String, member: Bool) {
        if let code = MemberSettings.code, code == password {
            let codeHash = sha256(code.trimmingCharacters(in: .whitespaces).uppercased())
            return ("aurum-" + String(sha256("murl:" + codeHash).prefix(24)), true)
        }
        return ("aurum-" + String(sha256("url:" + password).prefix(24)), false)
    }

    /// The newest address posted for this server, if it differs from `current`
    /// (also saved, so later requests go there). At most one lookup every 20 s.
    func newAddress(password: String, current: URL) async -> URL? {
        let (topic, member) = Self.topic(password: password)
        if let last = lastLookup[topic], Date().timeIntervalSince(last) < 20 { return nil }
        lastLookup[topic] = Date()
        guard let url = URL(string: "\(Self.base)/\(topic)/json?poll=1&since=all"),
              let fetched = try? await URLSession.shared.data(from: url) else { return nil }
        let data = fetched.0
        struct Message: Decodable { var event: String?; var message: String? }
        let posted = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { try? JSONDecoder().decode(Message.self, from: Data($0.utf8)) }
            .filter { $0.event == "message" }
            .compactMap { $0.message?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last
        guard let posted, posted.hasPrefix("https://"), let address = RemoteBotClient.normalizedURL(posted),
              address.absoluteString != current.absoluteString else { return nil }
        await MainActor.run {
            if member { MemberSettings.url = address.absoluteString } else { RemoteBotSettings.url = address.absoluteString }
        }
        return address
    }
}

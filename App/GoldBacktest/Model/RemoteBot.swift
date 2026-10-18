import Foundation
import Observation
import Security
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

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw ServerError(message: "Địa chỉ không hợp lệ") }
        var request = URLRequest(url: url, timeoutInterval: 25)
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
            throw ServerError(message: "Không kết nối được máy chủ (VPS tắt hoặc địa chỉ đã đổi — gõ /url cho bot Telegram).")
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return data }
        struct Failure: Decodable { var error: String? }
        if let failure = try? JSONDecoder().decode(Failure.self, from: data), let message = failure.error {
            throw ServerError(message: message)
        }
        throw ServerError(message: code == 401 ? "Sai mật khẩu máy chủ" : "Máy chủ trả lỗi \(code)")
    }

    func status() async throws -> RemoteStatus {
        try JSONDecoder().decode(RemoteStatus.self, from: await request("/status"))
    }

    func start(_ settings: RemoteStartRequest) async throws -> RemoteStatus {
        let body = try JSONEncoder().encode(settings)
        return try JSONDecoder().decode(RemoteStatus.self, from: await request("/start", method: "POST", body: body))
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
    func stop() async { await perform { try await $0.stop() } }
    func close(_ position: RemoteStatus.Position?) async { await perform { try await $0.close(positionID: position?.id) } }

    func testTelegram() async {
        guard let client = RemoteBotSettings.client() else { return }
        do { try await client.testTelegram() } catch { self.error = error.localizedDescription }
    }
}

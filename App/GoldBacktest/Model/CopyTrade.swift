import Foundation

/// Copy trade on the VPS: positions of the main MT5 account copied to follower accounts.
struct CopyTradeStatus: Decodable {
    struct Master: Decodable {
        var connected: Bool?
        var login: Int?
        var server: String?
        var positions: Int?
        var balance: Double?
        var currency: String?
        var error: String?
    }

    struct FollowerState: Decodable {
        var connected: Bool?
        var login: Int?
        var balance: Double?
        var equity: Double?
        var currency: String?
        var mode: String?
        var positions: Int?
        var profit: Double?
        var error: String?
        var lastSync: Double?
    }

    struct Follower: Decodable, Identifiable {
        var id: String
        var name: String
        var login: Int
        var server: String
        var path: String
        var multiplier: Double
        var fixedLots: Double
        var maxLots: Double
        var allowReal: Bool
        var enabled: Bool
        var symbolMap: [String: String]
        var hasPassword: Bool?
        var status: FollowerState?

        var title: String { name.isEmpty ? "#\(login)" : name }
    }

    struct Event: Decodable, Identifiable {
        var time: Double
        var text: String
        var id: String { "\(time)-\(text)" }
    }

    var enabled: Bool
    var master: Master
    var followers: [Follower]
    var events: [Event]
}

/// A follower being added or edited in the app.
struct CopyFollowerDraft {
    var id: String?
    var name = ""
    var login = ""
    var server = ""
    var password = ""
    var path = ""
    var multiplier = 1.0
    var fixedLots = 0.0
    var maxLots = 0.1
    var allowReal = false
    var enabled = true
    /// "XAUUSDm=XAUUSD" per line.
    var symbolMap = ""

    init() {}

    init(_ f: CopyTradeStatus.Follower) {
        id = f.id
        name = f.name
        login = String(f.login)
        server = f.server
        path = f.path
        multiplier = f.multiplier
        fixedLots = f.fixedLots
        maxLots = f.maxLots
        allowReal = f.allowReal
        enabled = f.enabled
        symbolMap = f.symbolMap.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    var body: [String: Any] {
        var map: [String: String] = [:]
        for line in symbolMap.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { map[parts[0]] = parts[1] }
        }
        var b: [String: Any] = ["name": name, "login": login.filter(\.isNumber),
                                "server": server.trimmingCharacters(in: .whitespaces),
                                "path": path.trimmingCharacters(in: .whitespaces), "multiplier": multiplier,
                                "fixedLots": fixedLots, "maxLots": maxLots, "allowReal": allowReal,
                                "enabled": enabled, "symbolMap": map]
        if let id { b["id"] = id }
        // Empty = keep the password saved on the VPS.
        if !password.isEmpty { b["password"] = password }
        return b
    }
}

extension RemoteBotClient {
    func copyStatus() async throws -> CopyTradeStatus {
        try JSONDecoder().decode(CopyTradeStatus.self, from: await send("/copy/status", timeout: 15))
    }

    func copySettings(enabled: Bool) async throws -> CopyTradeStatus {
        try await copyPost("/copy/settings", ["enabled": enabled])
    }

    func copySave(_ draft: CopyFollowerDraft) async throws -> CopyTradeStatus {
        try await copyPost("/copy/follower", draft.body)
    }

    func copyRemove(id: String, closePositions: Bool) async throws -> CopyTradeStatus {
        try await copyPost("/copy/remove", ["id": id, "closePositions": closePositions])
    }

    func copyCloseAll(id: String) async throws -> CopyTradeStatus {
        try await copyPost("/copy/close", ["id": id])
    }

    private func copyPost(_ path: String, _ object: [String: Any]) async throws -> CopyTradeStatus {
        let body = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(CopyTradeStatus.self, from: await send(path, method: "POST", body: body, timeout: 90))
    }
}

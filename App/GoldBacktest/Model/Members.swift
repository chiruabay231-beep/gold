import Foundation
import Observation
import Security

/// Sharing signals with other people: the owner's VPS gives each member an invite
/// code; with the server address and that code a member sees the owner's trades as
/// signals (and, with the "copy" role, has them copied into their own MT5 account).
/// The strategy, lot sizes and the owner's account stay on the VPS.

/// The member connection of this phone (separate from the owner's VPS password,
/// so the owner can try the member side on the same phone).
enum MemberSettings {
    private static let urlKey = "member.url"
    private static let service = "GoldBacktest.member"
    private static let account = "code"

    static var url: String {
        get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: urlKey) }
    }

    static var code: String? {
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

    static func saveCode(_ code: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func client() -> RemoteBotClient? {
        guard let code, let url = RemoteBotClient.normalizedURL(url) else { return nil }
        return RemoteBotClient(baseURL: url, password: code)
    }

    /// The owner trying the member side on their own phone ("Xem thử như thành viên").
    static var preview: Bool {
        get { UserDefaults.standard.bool(forKey: "member.preview") }
        set { UserDefaults.standard.set(newValue, forKey: "member.preview") }
    }

    static func disconnect() {
        saveCode("")
        url = ""
        preview = false
    }
}

/// Parts of the app a member's app shows besides the chart and the signals; the
/// owner switches them on the VPS (Thành viên & mã mời).
enum MemberFeature: String, CaseIterable, Identifiable {
    case news, killzones, sharkflow, demo, indicators, backtest, copyReal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .news: return "Tin tức"
        case .killzones: return "Chỉ báo ICT Killzones (FVG, đỉnh đáy…)"
        case .sharkflow: return "Dòng tiền cá mập"
        case .demo: return "Nút BUY/SELL (giao dịch demo)"
        case .indicators: return "Tab Chỉ báo (tự viết chỉ báo)"
        case .backtest: return "Tab Backtest"
        case .copyReal: return "Cho copy vào tài khoản THẬT của thành viên"
        }
    }

    /// Same defaults as the server.
    var defaultOn: Bool {
        switch self {
        case .news, .killzones, .sharkflow, .demo: return true
        case .indicators, .backtest, .copyReal: return false
        }
    }
}

/// What a member sees about themself.
struct MemberInfo: Decodable {
    var name: String
    /// "signals" or "copy".
    var role: String
    var expires: Double?
    var version: String?
    /// Copying runs only while the owner has copy trade on.
    var ownerCopyOn: Bool?
    /// What the owner lets members see (MemberFeature raw values).
    var features: [String: Bool]?

    var canCopy: Bool { role == "copy" }
}

/// One of the owner's trades, as a signal.
struct TradeSignal: Decodable, Identifiable {
    var id: String
    var symbol: String
    /// "long" or "short".
    var side: String
    var entry: Double
    var stop: Double?
    var target: Double?
    var price: Double?
    var openTime: Double
    /// "open" or "closed".
    var status: String
    var exit: Double?
    var closeTime: Double?
    /// Price distance won (+) or lost (−).
    var result: Double?

    var isOpen: Bool { status == "open" }
    var isBuy: Bool { side == "long" }

    /// Running (open) or final (closed) distance in price.
    var move: Double? {
        if let result { return result }
        guard let price else { return nil }
        return (price - entry) * (isBuy ? 1 : -1)
    }
}

/// A member's copy account, as the owner's server reports it.
struct MemberCopyStatus: Decodable {
    var follower: CopyTradeStatus.Follower?
    var ownerCopyOn: Bool
    var allowed: Bool
}

/// A member in the owner's list.
struct MemberRow: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var role: String
    var enabled: Bool
    var expires: Double?
    var created: Double?
    var lastSeen: Double?
    var hasCopy: Bool

    var expired: Bool { expires.map { $0 <= Date().timeIntervalSince1970 } ?? false }
}

struct MembersList: Decodable {
    var members: [MemberRow]
    var openSignals: Int?
    var signals: Int?
    /// The server's current address, to send with the code.
    var url: String?
    /// The new invite code, only right after adding a member or changing its code.
    var code: String?
    var member: MemberRow?
    var features: [String: Bool]?
}

extension RemoteBotClient {
    private func json<T: Decodable>(_ path: String, _ object: [String: Any]? = nil, as type: T.Type) async throws -> T {
        if let object {
            let body = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(T.self, from: await send(path, method: "POST", body: body))
        }
        return try JSONDecoder().decode(T.self, from: await send(path))
    }

    // Member side (the client carries the invite code).
    func memberMe() async throws -> MemberInfo { try await json("/member/me", as: MemberInfo.self) }

    func memberSignals() async throws -> [TradeSignal] {
        struct Response: Decodable { var signals: [TradeSignal] }
        return try await json("/member/signals?limit=60", as: Response.self).signals
    }

    func memberCopy() async throws -> MemberCopyStatus { try await json("/member/copy", as: MemberCopyStatus.self) }

    func memberCopySave(_ draft: CopyFollowerDraft) async throws -> MemberCopyStatus {
        try await json("/member/copy", draft.body, as: MemberCopyStatus.self)
    }

    func memberCopyRemove() async throws -> MemberCopyStatus {
        try await json("/member/copy/remove", [:], as: MemberCopyStatus.self)
    }

    // Owner side (the client carries the owner's password).
    func members() async throws -> MembersList { try await json("/members", as: MembersList.self) }

    /// Adds (no id) or changes a member. `days` 0 = no expiry; nil keeps it.
    func memberSave(id: String?, name: String, role: String, enabled: Bool, days: Double?) async throws -> MembersList {
        var object: [String: Any] = ["name": name, "role": role, "enabled": enabled]
        if let id { object["id"] = id }
        if let days { object["days"] = days }
        return try await json("/members/save", object, as: MembersList.self)
    }

    func memberNewCode(id: String) async throws -> MembersList {
        try await json("/members/code", ["id": id], as: MembersList.self)
    }

    func memberFeatures(_ features: [String: Bool]) async throws -> MembersList {
        try await json("/members/features", features, as: MembersList.self)
    }

    func memberRemove(id: String) async throws -> MembersList {
        try await json("/members/remove", ["id": id], as: MembersList.self)
    }
}

/// The member's signals, refreshed every few seconds while the app is open; the
/// Live chart draws the open ones of its market.
@MainActor
@Observable
final class MemberFeed {
    var info: MemberInfo?
    var signals: [TradeSignal] = []
    var error: String?
    /// Changes when the member connects or disconnects.
    var connectionID = UUID()

    var isConnected: Bool { MemberSettings.client() != nil }
    var openSignals: [TradeSignal] { signals.filter(\.isOpen) }

    /// The app shows only what members get: a member's phone (no owner password),
    /// or the owner's phone while trying it out.
    private(set) var memberMode = MemberFeed.computeMode()

    private static func computeMode() -> Bool {
        MemberSettings.client() != nil && (RemoteBotSettings.client() == nil || MemberSettings.preview)
    }

    /// Owner's phone, trying the member side.
    var isPreview: Bool { memberMode && MemberSettings.preview }

    /// The owner's server refused the code (locked or expired): back to the code screen.
    private(set) var revoked = false

    /// Whether the app opens: the owner (VPS password saved) always; anyone else
    /// only with a working invite code.
    private(set) var hasAccess = MemberFeed.computeAccess()

    private static func computeAccess() -> Bool {
        RemoteBotSettings.client() != nil || MemberSettings.client() != nil
    }

    /// After the owner saves (or clears) the VPS connection.
    func ownerChanged() {
        memberMode = Self.computeMode()
        hasAccess = Self.computeAccess() && !revoked
    }

    /// Whether a part of the app shows (always, outside member mode).
    func allows(_ feature: MemberFeature) -> Bool {
        guard memberMode else { return true }
        return info?.features?[feature.rawValue] ?? feature.defaultOn
    }

    func refresh() async {
        guard let client = MemberSettings.client() else {
            info = nil
            signals = []
            return
        }
        do {
            info = try await client.memberMe()
            signals = try await client.memberSignals()
            error = nil
        } catch {
            self.error = error.localizedDescription
            // Locked or expired: the app closes until a new code is entered
            // (the owner's own phone stays open).
            if (error as? RemoteBotClient.ServerError)?.code == 403, RemoteBotSettings.client() == nil {
                revoked = true
                hasAccess = false
            }
        }
    }

    func watch() async {
        while !Task.isCancelled {
            if isConnected { await refresh() }
            try? await Task.sleep(nanoseconds: isConnected ? 5_000_000_000 : 20_000_000_000)
        }
    }

    /// Signs in with an invite code. A member only has the code: the address is
    /// looked up where the server posts it (the owner's preview passes it).
    func connect(url: String? = nil, code: String, preview: Bool = false) async -> Bool {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var address = url
        if address == nil {
            address = await URLRelay.shared.address(forMemberCode: code)?.absoluteString
        }
        guard let address else {
            error = "Mã mời không đúng (hoặc người cung cấp chưa bật). Kiểm tra lại mã."
            return false
        }
        MemberSettings.url = address
        MemberSettings.saveCode(code)
        MemberSettings.preview = preview
        connectionID = UUID()
        await refresh()
        if info == nil {
            MemberSettings.disconnect()
            memberMode = Self.computeMode()
            hasAccess = Self.computeAccess() && !revoked
            return false
        }
        revoked = false
        memberMode = Self.computeMode()
        hasAccess = true
        return true
    }

    func disconnect() {
        MemberSettings.disconnect()
        info = nil
        signals = []
        error = nil
        connectionID = UUID()
        memberMode = Self.computeMode()
        hasAccess = Self.computeAccess()
    }

    /// Open signals of a chart's market: XAUUSD, XAUUSDm, XAUUSDT and XAU_USD all match.
    func openSignals(matching symbol: String) -> [TradeSignal] {
        let key = Self.baseSymbol(symbol)
        return openSignals.filter { Self.baseSymbol($0.symbol) == key }
    }

    static func baseSymbol(_ symbol: String) -> String {
        String(symbol.uppercased().filter(\.isLetter).prefix(6))
    }
}

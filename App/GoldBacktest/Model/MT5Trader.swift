import Foundation
import Observation
import UIKit
import UserNotifications
import BacktestKit

/// Trading the MT5 (Exness…) account on the VPS from the app: keeps its
/// positions, pending orders and closed deals fresh while an MT5 chart is
/// open, sends orders, and speaks fills like the demo account.
@MainActor
@Observable
final class MT5Trader {
    private(set) var state: MT5TradingState?
    /// Last refusal or connection problem, shown to the user once.
    var lastError: String?
    private(set) var busy = false

    @ObservationIgnored private var knownDeals: Set<Int>?
    @ObservationIgnored private var knownPositions: Set<Int>?
    /// Login@server the known tickets belong to.
    @ObservationIgnored private var accountKey: String?
    /// After a (new) account appears, its orders are taken in silently until
    /// then: MT5 loads an account's history over a few seconds after login.
    @ObservationIgnored private var quietUntil = Date.distantPast
    @ObservationIgnored private var baselineTime = Date()

    var isReal: Bool { state?.mode == "real" }

    func positions(_ symbol: String) -> [MT5TradingState.Position] {
        state?.positions.filter { $0.symbol == symbol } ?? []
    }

    func orders(_ symbol: String) -> [MT5TradingState.Order] {
        state?.orders.filter { $0.symbol == symbol } ?? []
    }

    /// Refreshes every 2 seconds until the calling task is cancelled.
    func watch() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func refresh() async {
        guard let client = RemoteBotSettings.client() else { return }
        do {
            apply(try await client.mt5Trading())
        } catch {
            // Polling errors are shown on the chart status; no alert every 2 seconds.
        }
    }

    // MARK: - Orders

    func market(symbol: String, side: PaperAccount.Side, lots: Double, stop: Double?, target: Double?) async {
        await perform { try await $0.mt5Order(symbol: symbol, side: side, lots: lots, stop: stop, target: target) }
    }

    func pending(symbol: String, side: PaperAccount.Side, lots: Double, entry: Double, stop: Double?, target: Double?) async {
        await perform { try await $0.mt5Order(symbol: symbol, side: side, lots: lots, price: entry, stop: stop, target: target) }
    }

    /// Closes the position, or only `lots` of it (partial close).
    func close(_ ticket: Int, lots: Double? = nil) async {
        await perform { try await $0.mt5Close(ticket: ticket, lots: lots) }
    }

    func modify(_ ticket: Int, entry: Double? = nil, stop: Double?, target: Double?) async {
        await perform { try await $0.mt5Modify(ticket: ticket, price: entry, stop: stop, target: target) }
    }

    func cancel(_ ticket: Int, quiet: Bool = false) async {
        await perform(quiet: quiet) { try await $0.mt5Cancel(ticket: ticket) }
    }

    /// A pending order for a bot: no haptics; returns its ticket, or nil with `lastError` set.
    func botPending(symbol: String, side: PaperAccount.Side, lots: Double, entry: Double, stop: Double?,
                    target: Double?) async -> Int? {
        var ticket: Int?
        await perform(quiet: true) { client in
            let state = try await client.mt5Order(symbol: symbol, side: side, lots: lots, price: entry, stop: stop, target: target)
            ticket = state.ticket
            return state
        }
        return ticket
    }

    func settings(tradingEnabled: Bool, allowReal: Bool, maxLots: Double) async {
        await perform { try await $0.mt5Settings(tradingEnabled: tradingEnabled, allowReal: allowReal, maxLots: maxLots) }
    }

    private func perform(quiet: Bool = false, _ action: (RemoteBotClient) async throws -> MT5TradingState) async {
        guard let client = RemoteBotSettings.client() else {
            lastError = "Chưa kết nối máy chủ VPS (Giao dịch → Đăng nhập)"
            return
        }
        busy = true
        defer { busy = false }
        do {
            apply(try await action(client))
            if !quiet { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        } catch {
            lastError = error.localizedDescription
            if !quiet { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        }
    }

    // MARK: - Fills

    private func apply(_ new: MT5TradingState) {
        let key = "\(new.login.map { String($0) } ?? "")@\(new.server ?? "")"
        if key != accountKey {
            // Another account (or the first look): its orders so far are history.
            accountKey = key
            knownDeals = nil
            knownPositions = nil
            quietUntil = Date().addingTimeInterval(10)
            baselineTime = Date()
        }
        var deals = knownDeals ?? []
        var positions = knownPositions ?? []
        let announce = knownDeals != nil && Date() > quietUntil
        // Only orders filled since this account was first seen; older ones
        // can still show up late while MT5 loads its history.
        let since = baselineTime.timeIntervalSince1970 - 600
        for deal in new.deals where !deals.contains(deal.ticket) {
            if announce, deal.time >= since { announceClose(deal) }
            deals.insert(deal.ticket)
        }
        for p in new.positions where !positions.contains(p.ticket) {
            if announce, p.time >= since { announceOpen(p) }
            positions.insert(p.ticket)
        }
        knownDeals = deals
        knownPositions = positions
        state = new
    }

    private func announceOpen(_ p: MT5TradingState.Position) {
        var text = VoiceSettings.phrase(VoiceSettings.entryKey, default: VoiceSettings.defaultEntry)
        if VoiceSettings.speakDetails { text += ", \(PaperTrader.spokenSymbol(p.symbol)) \(PaperTrader.spoken(p.entry))" }
        VoiceAnnouncer.shared.speak(text)
        notify(title: "Exness: lệnh đã khớp",
               body: "\(p.side == "long" ? "MUA" : "BÁN") \(PaperTrader.lots(p.lots)) lot \(p.symbol) @ \(PaperTrader.spoken(p.entry))")
    }

    private func announceClose(_ d: MT5TradingState.Deal) {
        let isTarget = d.reason == "target"
        var text = d.reason == "manual" ? (VoiceSettings.language.hasPrefix("vi") ? "Đã đóng lệnh" : "Position closed")
            : (isTarget ? VoiceSettings.phrase(VoiceSettings.targetKey, default: VoiceSettings.defaultTarget)
                : VoiceSettings.phrase(VoiceSettings.stopKey, default: VoiceSettings.defaultStop))
        if VoiceSettings.speakDetails { text += ", \(d.profit >= 0 ? "plus" : "minus") \(Int(abs(d.profit).rounded())) dollars" }
        VoiceAnnouncer.shared.speak(text)
        let title = d.reason == "manual" ? "Exness: đã đóng lệnh" : (isTarget ? "Exness: chạm TP (Target fill)" : "Exness: chạm SL (Stop loss fill)")
        notify(title: title, body: "\(d.symbol) \(String(format: "%+.2f", d.profit)) \(state?.currency ?? "USD")")
        UINotificationFeedbackGenerator().notificationOccurred(d.profit >= 0 ? .success : .error)
    }

    private func notify(title: String, body: String) {
        AlertSettings.post(title: title, body: body)
    }
}

extension MT5TradingState.Position {
    /// The profit carried on with the live price: the VPS reports it every 2 s while
    /// the chart ticks several times a second. Only for symbols quoted in USD (the
    /// money is then price × lots × contract size); others keep the VPS figure.
    func liveProfit(bid: Double, ask: Double) -> Double {
        guard let price, bid > 0, ask >= bid else { return profit }
        let pair = String(symbol.uppercased().filter(\.isLetter).prefix(6))
        guard pair.hasSuffix("USD") else { return profit }
        let buy = side == "long"
        let close = buy ? bid : ask
        return profit + (close - price) * (buy ? 1 : -1) * lots * PaperAccount.contractSize(for: symbol)
    }
}

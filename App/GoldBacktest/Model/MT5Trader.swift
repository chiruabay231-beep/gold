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

    func close(_ ticket: Int) async {
        await perform { try await $0.mt5Close(ticket: ticket) }
    }

    func modify(_ ticket: Int, entry: Double? = nil, stop: Double?, target: Double?) async {
        await perform { try await $0.mt5Modify(ticket: ticket, price: entry, stop: stop, target: target) }
    }

    func cancel(_ ticket: Int) async {
        await perform { try await $0.mt5Cancel(ticket: ticket) }
    }

    func settings(tradingEnabled: Bool, allowReal: Bool, maxLots: Double) async {
        await perform { try await $0.mt5Settings(tradingEnabled: tradingEnabled, allowReal: allowReal, maxLots: maxLots) }
    }

    private func perform(_ action: (RemoteBotClient) async throws -> MT5TradingState) async {
        guard let client = RemoteBotSettings.client() else {
            lastError = "Chưa kết nối máy chủ VPS (Giao dịch → Đăng nhập)"
            return
        }
        busy = true
        defer { busy = false }
        do {
            apply(try await action(client))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            lastError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Fills

    private func apply(_ new: MT5TradingState) {
        let deals = Set(new.deals.map(\.ticket))
        let positions = Set(new.positions.map(\.ticket))
        // Announce only changes after the first look, not the history.
        if let knownDeals {
            for deal in new.deals where !knownDeals.contains(deal.ticket) { announceClose(deal) }
        }
        if let knownPositions {
            for p in new.positions where !knownPositions.contains(p.ticket) { announceOpen(p) }
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
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

import Foundation
import Observation
import UIKit
import UserNotifications
import BacktestKit

/// The in-app demo account: orders fill against live prices, stops and
/// targets close positions, and every fill is spoken and notified.
@MainActor
@Observable
final class PaperTrader {
    private(set) var account: PaperAccount
    /// Latest price per symbol key, for profit and equity.
    private(set) var prices: [String: Double] = [:]
    /// Newest fill, shown briefly on the chart.
    private(set) var lastEvent: PaperAccount.Event?

    @ObservationIgnored private var lastSave = Date.distantPast

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("paper-account.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(PaperAccount.self, from: data) {
            account = saved
        } else {
            account = PaperAccount()
        }
    }

    // MARK: - Prices

    /// Called by the live feed on every price update of `symbol`.
    func update(symbol: String, price: Double, time: Date) {
        // Only touch observed state when something can change, to keep redraws cheap.
        let involved = account.positions.contains { $0.symbol == symbol } || account.pending.contains { $0.symbol == symbol }
        if involved || prices[symbol] == nil { prices[symbol] = price }
        guard involved else { return }
        let events = account.process(symbol: symbol, price: price, time: time)
        guard !events.isEmpty else { return }
        for event in events { announce(event) }
        lastEvent = events.last
        save()
    }

    func price(_ symbol: String) -> Double? { prices[symbol] }

    var equity: Double { account.equity { self.prices[$0] } }

    var openProfit: Double {
        account.positions.reduce(0) { sum, p in sum + (prices[p.symbol].map { p.profit(at: $0) } ?? 0) }
    }

    // MARK: - Orders

    func buy(symbol: String, lots: Double, price: Double, stop: Double?, target: Double?) {
        account.openMarket(symbol: symbol, side: .long, lots: lots, price: price, stop: stop, target: target, time: Date())
        prices[symbol] = price
        speakEntry(side: .long, symbol: symbol, price: price)
        save()
    }

    func sell(symbol: String, lots: Double, price: Double, stop: Double?, target: Double?) {
        account.openMarket(symbol: symbol, side: .short, lots: lots, price: price, stop: stop, target: target, time: Date())
        prices[symbol] = price
        speakEntry(side: .short, symbol: symbol, price: price)
        save()
    }

    func placePending(symbol: String, side: PaperAccount.Side, lots: Double, entry: Double, stop: Double?, target: Double?,
                      currentPrice: Double) {
        account.placePending(symbol: symbol, side: side, lots: lots, entry: entry, stop: stop, target: target,
                             currentPrice: currentPrice, time: Date())
        prices[symbol] = currentPrice
        VoiceAnnouncer.shared.speak(VoiceSettings.language.hasPrefix("vi") ? "Đã đặt lệnh chờ" : "Order placed")
        save()
    }

    func close(_ position: PaperAccount.Position) {
        guard let price = prices[position.symbol] else { return }
        if let trade = account.close(positionID: position.id, price: price, time: Date()) {
            lastEvent = .closed(trade)
        }
        save()
    }

    func cancel(_ order: PaperAccount.PendingOrder) {
        account.cancel(orderID: order.id)
        save()
    }

    func modify(_ position: PaperAccount.Position, stop: Double?, target: Double?) {
        account.modify(positionID: position.id, stop: stop, target: target)
        save()
    }

    func modifyPending(_ order: PaperAccount.PendingOrder, entry: Double, stop: Double?, target: Double?, currentPrice: Double) {
        account.modifyPending(orderID: order.id, entry: entry, stop: stop, target: target, currentPrice: currentPrice)
        save()
    }

    func reset(balance: Double) {
        account = PaperAccount(startingBalance: balance)
        lastEvent = nil
        save()
    }

    // MARK: - Alerts

    private func announce(_ event: PaperAccount.Event) {
        let details = VoiceSettings.speakDetails
        switch event {
        case .opened(let position):
            var text = VoiceSettings.phrase(VoiceSettings.entryKey, default: VoiceSettings.defaultEntry)
            if details { text += ", \(Self.spokenSymbol(position.symbol)) \(Self.spoken(position.entryPrice))" }
            VoiceAnnouncer.shared.speak(text)
            notify(title: "Lệnh demo đã khớp", body: "\(position.side == .long ? "MUA" : "BÁN") \(Self.lots(position.lots)) lot \(LiveView.displayName(Self.bareSymbol(position.symbol))) @ \(Self.spoken(position.entryPrice))")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .closed(let trade):
            let isTarget = trade.reason == .target
            var text = isTarget
                ? VoiceSettings.phrase(VoiceSettings.targetKey, default: VoiceSettings.defaultTarget)
                : VoiceSettings.phrase(VoiceSettings.stopKey, default: VoiceSettings.defaultStop)
            if details { text += ", \(trade.profit >= 0 ? "plus" : "minus") \(Int(abs(trade.profit).rounded())) dollars" }
            VoiceAnnouncer.shared.speak(text)
            notify(title: isTarget ? "Chạm TP (Target fill)" : "Chạm SL (Stop loss fill)",
                   body: "\(LiveView.displayName(Self.bareSymbol(trade.symbol))) \(String(format: "%+.2f", trade.profit)) $")
            UINotificationFeedbackGenerator().notificationOccurred(isTarget ? .success : .error)
        }
    }

    private func speakEntry(side: PaperAccount.Side, symbol: String, price: Double) {
        var text = side == .long ? "Buy" : "Sell"
        if VoiceSettings.language.hasPrefix("vi") { text = side == .long ? "Đã mua" : "Đã bán" }
        VoiceAnnouncer.shared.speak(text)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(account) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        lastSave = Date()
    }

    // MARK: - Formatting

    /// Symbol keys are "SOURCE:SYMBOL"; this drops the source.
    static func bareSymbol(_ key: String) -> String {
        key.split(separator: ":").last.map(String.init) ?? key
    }

    static func spokenSymbol(_ key: String) -> String {
        let bare = bareSymbol(key).replacingOccurrences(of: "_", with: "")
        return bare.hasPrefix("XAU") ? "gold" : bare
    }

    static func spoken(_ price: Double) -> String {
        CandleChart.format(price, CandleChart.decimals(for: price))
    }

    static func lots(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

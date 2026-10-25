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
    /// The saved account that trades live prices.
    private(set) var liveAccount: PaperAccount
    /// A separate account while bar replay runs; nil otherwise.
    private(set) var replayAccount: PaperAccount?
    /// Time of the replayed bar, used as "now" for orders during replay.
    private(set) var replayTime: Date?

    var isReplaying: Bool { replayAccount != nil }

    /// The account orders go to: the replay account during replay, else the live one.
    private(set) var account: PaperAccount {
        get { replayAccount ?? liveAccount }
        set { if replayAccount != nil { replayAccount = newValue } else { liveAccount = newValue } }
    }

    private var now: Date { replayTime ?? Date() }
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
            liveAccount = saved
        } else {
            liveAccount = PaperAccount()
        }
    }

    // MARK: - Prices

    /// Latest ask per symbol key; `prices` holds the bid.
    @ObservationIgnored private var asks: [String: Double] = [:]

    /// Called by the live feed on every quote of `symbol`. Buys fill at the ask
    /// and close at the bid, sells the other way round.
    func update(symbol: String, bid: Double, ask: Double, time: Date) {
        // Live prices must not touch the replay account.
        guard !isReplaying else { return }
        asks[symbol] = ask
        // Only touch observed state when something can change, to keep redraws cheap.
        let involved = account.positions.contains { $0.symbol == symbol } || account.pending.contains { $0.symbol == symbol }
        if involved || prices[symbol] == nil { prices[symbol] = bid }
        guard involved else { return }
        var events = account.process(symbol: symbol, bid: bid, ask: ask, time: time)
        events += account.manage(symbol: symbol, price: bid, time: time, rules: Self.rules)
        guard !events.isEmpty else { return }
        for event in events { announce(event) }
        lastEvent = events.last
        save()
    }

    /// A live bar closed: check open positions for reversal signs.
    func barClosed(symbol: String, candles: [Candle]) {
        guard !isReplaying, Self.rules.closeOnReversal, let price = candles.last?.close,
              account.positions.contains(where: { $0.symbol == symbol }) else { return }
        let events = account.manage(symbol: symbol, price: prices[symbol] ?? price, time: now, rules: Self.rules, closed: candles)
        guard !events.isEmpty else { return }
        for event in events { announce(event) }
        lastEvent = events.last
        save()
    }

    /// Trade management settings (automatic stop moves and reversal exits).
    static var rules: TradeManagement {
        guard let data = UserDefaults.standard.data(forKey: rulesKey),
              let rules = try? JSONDecoder().decode(TradeManagement.self, from: data) else { return TradeManagement() }
        return rules
    }

    static let rulesKey = "trade.management"

    static func saveRules(_ rules: TradeManagement) {
        UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: rulesKey)
    }

    /// The bid (chart price) of `symbol`.
    func price(_ symbol: String) -> Double? { prices[symbol] }

    /// The ask of `symbol`; the bid when no spread is known.
    func ask(_ symbol: String) -> Double? { asks[symbol] ?? prices[symbol] }

    /// Price a position would close at now: the bid for buys, the ask for sells.
    func closePrice(_ position: PaperAccount.Position) -> Double? {
        position.side == .long ? price(position.symbol) : ask(position.symbol)
    }

    func profit(_ position: PaperAccount.Position) -> Double? {
        closePrice(position).map { position.profit(at: $0) }
    }

    var openProfit: Double {
        account.positions.reduce(0) { sum, p in sum + (profit(p) ?? 0) }
    }

    var equity: Double { account.balance + openProfit }

    // MARK: - Orders

    func buy(symbol: String, lots: Double, price: Double, stop: Double?, target: Double?) {
        account.openMarket(symbol: symbol, side: .long, lots: lots, price: price, stop: stop, target: target, time: now)
        prices[symbol] = price
        speakEntry(side: .long, symbol: symbol, price: price)
        save()
    }

    func sell(symbol: String, lots: Double, price: Double, stop: Double?, target: Double?) {
        account.openMarket(symbol: symbol, side: .short, lots: lots, price: price, stop: stop, target: target, time: now)
        prices[symbol] = price
        speakEntry(side: .short, symbol: symbol, price: price)
        save()
    }

    /// `quiet`: no voice (bots placing orders on every candle).
    @discardableResult
    func placePending(symbol: String, side: PaperAccount.Side, lots: Double, entry: Double, stop: Double?, target: Double?,
                      currentPrice: Double, quiet: Bool = false) -> PaperAccount.PendingOrder {
        let order = account.placePending(symbol: symbol, side: side, lots: lots, entry: entry, stop: stop, target: target,
                                         currentPrice: currentPrice, time: now)
        prices[symbol] = currentPrice
        if !quiet { VoiceAnnouncer.shared.speak(VoiceSettings.language.hasPrefix("vi") ? "Đã đặt lệnh chờ" : "Order placed") }
        save()
        return order
    }

    func close(_ position: PaperAccount.Position) {
        guard let price = closePrice(position) else { return }
        if let trade = account.close(positionID: position.id, price: price, time: now) {
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

    // MARK: - Bar replay

    /// Starts a fresh replay account; live positions are untouched.
    func beginReplay(balance: Double = 10_000) {
        if replayAccount == nil { livePrices = (prices, asks) }
        replayAccount = PaperAccount(startingBalance: balance)
        replayTime = nil
        lastEvent = nil
    }

    /// The live bids and asks from before the replay, put back when it ends.
    @ObservationIgnored private var livePrices: (bids: [String: Double], asks: [String: Double])?

    /// Applies a replayed bar: fills orders and stops/targets inside it.
    func replay(bar: Candle, symbol: String, closed: [Candle]) {
        guard isReplaying else { return }
        replayTime = bar.time
        prices[symbol] = bar.close
        // Replayed bars have no spread: sells close at the bar's price too, not at today's live ask.
        asks[symbol] = bar.close
        let rules = Self.rules
        var events = account.process(symbol: symbol, candle: bar)
        // Stops follow the bar's best price; reversals are judged at its close.
        events += account.manage(symbol: symbol, price: bar.close, time: bar.time, rules: rules, closed: closed)
        for event in events { announce(event, notify: false) }
        if let last = events.last { lastEvent = last }
    }

    /// Ends replay and returns its account for a summary.
    @discardableResult
    func endReplay() -> PaperAccount? {
        let finished = replayAccount
        replayAccount = nil
        replayTime = nil
        lastEvent = nil
        if let live = livePrices {
            prices = live.bids
            asks = live.asks
            livePrices = nil
        }
        return finished
    }

    func reset(balance: Double) {
        account = PaperAccount(startingBalance: balance)
        lastEvent = nil
        save()
    }

    // MARK: - Alerts

    private func announce(_ event: PaperAccount.Event, notify notifyUser: Bool = true) {
        let details = VoiceSettings.speakDetails
        switch event {
        case .stopMoved(let position):
            VoiceAnnouncer.shared.speak(VoiceSettings.language.hasPrefix("vi") ? "Đã dời cắt lỗ" : "Stop moved")
            if notifyUser {
                notify(title: "Đã dời SL", body: "\(LiveView.displayName(Self.bareSymbol(position.symbol))) SL → \(Self.spoken(position.stop ?? 0))")
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        case .opened(let position):
            var text = VoiceSettings.phrase(VoiceSettings.entryKey, default: VoiceSettings.defaultEntry)
            if details { text += ", \(Self.spokenSymbol(position.symbol)) \(Self.spoken(position.entryPrice))" }
            VoiceAnnouncer.shared.speak(text)
            if notifyUser { notify(title: "Lệnh demo đã khớp", body: "\(position.side == .long ? "MUA" : "BÁN") \(Self.lots(position.lots)) lot \(LiveView.displayName(Self.bareSymbol(position.symbol))) @ \(Self.spoken(position.entryPrice))") }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .closed(let trade):
            let isTarget = trade.reason == .target
            let vietnamese = VoiceSettings.language.hasPrefix("vi")
            var text = isTarget
                ? VoiceSettings.phrase(VoiceSettings.targetKey, default: VoiceSettings.defaultTarget)
                : VoiceSettings.phrase(VoiceSettings.stopKey, default: VoiceSettings.defaultStop)
            if trade.reason == .reversal { text = vietnamese ? "Đã chốt do đảo chiều" : "Closed on reversal" }
            if details { text += ", \(trade.profit >= 0 ? "plus" : "minus") \(Int(abs(trade.profit).rounded())) dollars" }
            VoiceAnnouncer.shared.speak(text)
            if notifyUser { notify(title: trade.reason == .reversal ? "Tự chốt lệnh (đảo chiều)" : (isTarget ? "Chạm TP (Target fill)" : "Chạm SL (Stop loss fill)"),
                   body: "\(LiveView.displayName(Self.bareSymbol(trade.symbol))) \(String(format: "%+.2f", trade.profit)) $") }
            UINotificationFeedbackGenerator().notificationOccurred(isTarget ? .success : .error)
        }
    }

    private func speakEntry(side: PaperAccount.Side, symbol: String, price: Double) {
        var text = side == .long ? "Buy" : "Sell"
        if VoiceSettings.language.hasPrefix("vi") { text = side == .long ? "Đã mua" : "Đã bán" }
        VoiceAnnouncer.shared.speak(text)
    }

    private func notify(title: String, body: String) {
        AlertSettings.post(title: title, body: body)
    }

    private func save() {
        // Replay trades are practice only and are not saved.
        guard !isReplaying, let data = try? JSONEncoder().encode(liveAccount) else { return }
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

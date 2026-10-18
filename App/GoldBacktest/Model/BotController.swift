import Foundation
import Observation
import UserNotifications
import BacktestKit

/// Runs a strategy script as a bot on the live chart: on every closed bar its
/// fresh entry/exit signals become demo orders (stop/target from the script).
@MainActor
@Observable
final class BotController {
    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    private(set) var isRunning = false
    var strategyID: UUID? {
        didSet { UserDefaults.standard.set(strategyID?.uuidString, forKey: "bot.strategy") }
    }
    var lots: Double {
        didSet { UserDefaults.standard.set(lots, forKey: "bot.lots") }
    }
    /// Size from account risk (Chart settings → position sizing) when the signal has a stop.
    var useRiskSizing: Bool {
        didSet { UserDefaults.standard.set(useRiskSizing, forKey: "bot.riskSizing") }
    }
    var allowLong = true
    var allowShort = true
    /// An opposite entry closes the open position and opens the new one.
    var reverse = true
    private(set) var log: [LogEntry] = []

    @ObservationIgnored private weak var market: LiveMarket?
    @ObservationIgnored private weak var trader: PaperTrader?

    init() {
        let defaults = UserDefaults.standard
        strategyID = defaults.string(forKey: "bot.strategy").flatMap(UUID.init)
        lots = defaults.object(forKey: "bot.lots") as? Double ?? 0.01
        useRiskSizing = defaults.bool(forKey: "bot.riskSizing")
    }

    func attach(market: LiveMarket, trader: PaperTrader) {
        self.market = market
        self.trader = trader
    }

    func start(strategyName: String) {
        guard let strategyID, let market else { return }
        isRunning = true
        market.track(strategy: strategyID)
        add("▶︎ Bắt đầu \(strategyName) trên \(LiveView.displayName(market.symbol)) \(LiveView.label(market.interval))")
        if let error = market.strategyError { add("⚠︎ Lỗi chiến lược: \(error)") }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        market?.track(strategy: nil)
        add("■ Dừng bot")
    }

    /// Fresh signals on the bar that just closed. Every signal ends in a
    /// notification saying what the bot did, so an alert never appears
    /// without either an order or the reason there is none.
    func handle(signals: [LiveSignal], symbol: String) {
        guard isRunning, let trader else { return }
        for signal in signals {
            let outcome = act(on: signal, symbol: symbol, trader: trader)
            add(outcome.text)
            notify(title: "🤖 \(LiveView.displayName(PaperTrader.bareSymbol(symbol))) · \(outcome.title)", body: outcome.text)
        }
    }

    private func act(on signal: LiveSignal, symbol: String, trader: PaperTrader) -> (title: String, text: String) {
        let label = signal.kind.label
        if trader.isReplaying {
            return ("Bỏ qua \(label)", "Tín hiệu \(label) bị bỏ qua: đang Replay (lệnh replay không dùng tài khoản demo)")
        }
        let price = trader.price(symbol) ?? signal.price
        let positions = trader.account.positions.filter { $0.symbol == symbol }
        switch signal.kind {
        case .longExit, .shortExit:
            let side: PaperAccount.Side = signal.kind == .longExit ? .long : .short
            let matching = positions.filter { $0.side == side }
            guard !matching.isEmpty else { return (label, "Tín hiệu \(label): không có lệnh để đóng") }
            for p in matching { trader.close(p) }
            return (label, "Đóng \(matching.count) lệnh \(side == .long ? "MUA" : "BÁN") theo tín hiệu thoát @ \(Self.format(price))")
        case .longEntry, .shortEntry:
            let side: PaperAccount.Side = signal.kind == .longEntry ? .long : .short
            let name = side == .long ? "MUA" : "BÁN"
            guard side == .long ? allowLong : allowShort else {
                return ("Bỏ qua \(label)", "Tín hiệu \(name) bị bỏ qua: đang tắt \"Cho phép \(name)\"")
            }
            // One position per direction.
            if positions.contains(where: { $0.side == side }) {
                return ("Bỏ qua \(label)", "Tín hiệu \(name) bị bỏ qua: đã có lệnh \(name) đang mở")
            }
            // The script sets SL/TP at the signal bar; price may already be past them.
            if let stop = signal.stop, (stop - price) * side.sign >= 0 {
                return ("Bỏ qua \(label)", "Tín hiệu \(name) bị bỏ qua: giá \(Self.format(price)) đã vượt SL \(Self.format(stop))")
            }
            if let target = signal.target, (target - price) * side.sign <= 0 {
                return ("Bỏ qua \(label)", "Tín hiệu \(name) bị bỏ qua: giá \(Self.format(price)) đã qua TP \(Self.format(target))")
            }
            let opposite = positions.filter { $0.side != side }
            var text = ""
            if !opposite.isEmpty {
                guard reverse else {
                    return ("Bỏ qua \(label)", "Tín hiệu \(name) bị bỏ qua: đang có lệnh ngược chiều và tắt \"Đảo lệnh\"")
                }
                for p in opposite { trader.close(p) }
                text = "Đảo lệnh: đóng \(side == .long ? "BÁN" : "MUA"). "
            }
            let size = orderLots(entry: price, stop: signal.stop)
            if side == .long {
                trader.buy(symbol: symbol, lots: size, price: price, stop: signal.stop, target: signal.target)
            } else {
                trader.sell(symbol: symbol, lots: size, price: price, stop: signal.stop, target: signal.target)
            }
            text += "Đã vào lệnh demo \(name) \(String(format: "%.2f", size)) lot @ \(Self.format(price))"
            if let stop = signal.stop { text += " · SL \(Self.format(stop))" }
            if let target = signal.target { text += " · TP \(Self.format(target))" }
            return ("Đã \(side == .long ? "mua" : "bán")", text)
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func orderLots(entry: Double, stop: Double?) -> Double {
        let defaults = UserDefaults.standard
        let balance = defaults.double(forKey: "position.balance")
        let risk = defaults.object(forKey: "position.riskPercent") as? Double ?? 1
        let contract = defaults.object(forKey: "position.contractSize") as? Double ?? 100
        if useRiskSizing, let stop, balance > 0,
           let sized = PositionSizing(balance: balance, riskPercent: risk, contractSize: contract).lots(entry: entry, stop: stop) {
            return max(0.01, (sized * 100).rounded(.down) / 100)
        }
        return max(0.01, lots)
    }

    private func add(_ text: String) {
        log.insert(LogEntry(time: Date(), text: text), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    static func format(_ price: Double) -> String {
        CandleChart.format(price, CandleChart.decimals(for: price))
    }
}

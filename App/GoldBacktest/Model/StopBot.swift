import Foundation
import Observation
import BacktestKit

/// Runs the "Stop theo nến" bot (CandleStopBot) on the Live chart with the
/// demo account: after each closed candle it replaces its buy stop / sell stop,
/// and cancels the other side when one fills.
@MainActor
@Observable
final class StopBotController {
    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    var config: CandleStopBot.Config {
        didSet { save() }
    }
    private(set) var isRunning = false
    /// Started at least once since the app opened (paused when not running).
    private(set) var hasSession = false
    /// Chart the bot trades: LiveMarket.symbolKey and timeframe.
    private(set) var symbolKey: String?
    private(set) var interval: BinanceClient.Interval?
    private(set) var log: [LogEntry] = []

    @ObservationIgnored private var orderIDs: Set<UUID> = []
    @ObservationIgnored private var positionIDs: Set<UUID> = []
    @ObservationIgnored private weak var market: LiveMarket?
    @ObservationIgnored private weak var trader: PaperTrader?

    private static let configKey = "stopbot.config"

    init() {
        config = UserDefaults.standard.data(forKey: Self.configKey)
            .flatMap { try? JSONDecoder().decode(CandleStopBot.Config.self, from: $0) } ?? CandleStopBot.Config()
    }

    func attach(market: LiveMarket, trader: PaperTrader) {
        self.market = market
        self.trader = trader
    }

    /// The Live chart is on another symbol or timeframe than the bot's.
    var chartMoved: Bool {
        guard isRunning, let market else { return false }
        return market.symbolKey != symbolKey || market.interval != interval
    }

    /// Open positions of the bot.
    var positions: [PaperAccount.Position] {
        trader?.account.positions.filter { positionIDs.contains($0.id) } ?? []
    }

    func start() {
        guard let market, let trader, !trader.isReplaying else { return }
        symbolKey = market.symbolKey
        interval = market.interval
        isRunning = true
        hasSession = true
        add("▶︎ Chạy trên \(LiveView.displayName(market.symbol)) \(LiveView.label(market.interval))")
        // Orders from the last closed candle right away.
        if let last = market.closedCandles.last { place(after: last) }
    }

    func stop() {
        guard isRunning else { return }
        cancelOrders()
        isRunning = false
        add("■ Dừng bot, đã huỷ lệnh chờ (lệnh đang mở giữ SL/TP)")
    }

    /// Each closed candle of the chart.
    func barClosed(symbol: String, candles: [Candle]) {
        guard isRunning, symbol == symbolKey, market?.interval == interval, let last = candles.last else { return }
        checkFills()
        cancelOrders()
        if config.onePosition, !positions.isEmpty { return }
        place(after: last)
    }

    /// Each price: a bot order that filled becomes a position (same id); OCO cancels the other side.
    func priceUpdated(symbol: String) {
        guard isRunning, symbol == symbolKey else { return }
        checkFills()
    }

    // MARK: - Orders

    private func checkFills() {
        guard let trader, !orderIDs.isEmpty else { return }
        let filled = trader.account.positions.filter { orderIDs.contains($0.id) }
        guard !filled.isEmpty else { return }
        for p in filled {
            orderIDs.remove(p.id)
            positionIDs.insert(p.id)
            add("✅ Khớp \(p.side == .long ? "BUY STOP" : "SELL STOP") \(PaperTrader.lots(p.lots)) lot @ \(Self.format(p.entryPrice))")
        }
        if config.oco { cancelOrders() }
        positionIDs.formIntersection(Set(trader.account.positions.map(\.id)))
    }

    private func cancelOrders() {
        guard let trader else { return }
        for order in trader.account.pending where orderIDs.contains(order.id) { trader.cancel(order) }
        orderIDs = []
    }

    private func place(after candle: Candle) {
        guard let trader, let symbolKey, !trader.isReplaying else { return }
        let bid = trader.price(symbolKey) ?? candle.close
        let ask = trader.ask(symbolKey) ?? bid
        var placed: [String] = []
        for order in CandleStopBot.orders(after: candle, config: config) {
            // A stop must be beyond the current price, or it would fill at once.
            if order.side == .long ? ask >= order.entry : bid <= order.entry {
                add("⚠︎ Giá đã vượt \(Self.format(order.entry)): bỏ \(order.side == .long ? "Buy" : "Sell") Stop nến này")
                continue
            }
            let pending = trader.placePending(symbol: symbolKey, side: order.side, lots: config.lots, entry: order.entry,
                                              stop: order.stop, target: order.target,
                                              currentPrice: order.side == .long ? ask : bid, quiet: true)
            orderIDs.insert(pending.id)
            placed.append("\(order.side == .long ? "Buy" : "Sell") Stop \(Self.format(order.entry)) SL \(Self.format(order.stop))"
                          + (order.target.map { " TP \(Self.format($0))" } ?? ""))
        }
        if placed.isEmpty, CandleStopBot.orders(after: candle, config: config).isEmpty {
            add("· Nến \(Self.format(candle.high - candle.low)) điểm ngoài khoảng lọc: không đặt lệnh")
        } else if !placed.isEmpty {
            add("⏳ " + placed.joined(separator: " · "))
        }
    }

    private func add(_ text: String) {
        log.insert(LogEntry(time: Date(), text: text), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.configKey) }
    }

    static func format(_ price: Double) -> String { CandleChart.format(price, CandleChart.decimals(for: price)) }
}

import Foundation
import Observation
import BacktestKit

/// Runs the "Stop theo nến" bot (CandleStopBot) on the Live chart: after each
/// closed candle it replaces its buy stop / sell stop and cancels the other
/// side when one fills. Orders go to the demo account (any market) or, on an
/// MT5 chart, to the MT5 account on the VPS (Exness or another broker).
@MainActor
@Observable
final class StopBotController {
    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    enum Destination: String, CaseIterable {
        case demo, mt5
    }

    var config: CandleStopBot.Config {
        didSet { save() }
    }
    /// Where orders go on an MT5 chart (other charts always use the demo account).
    var preferMT5: Bool {
        didSet { UserDefaults.standard.set(preferMT5, forKey: Self.mt5Key) }
    }
    private(set) var isRunning = false
    /// Started at least once since the app opened (paused when not running).
    private(set) var hasSession = false
    /// Chart the bot trades: LiveMarket.symbolKey, symbol and timeframe.
    private(set) var symbolKey: String?
    private(set) var symbol = ""
    private(set) var interval: BinanceClient.Interval?
    private(set) var destination = Destination.demo
    private(set) var log: [LogEntry] = []

    // Demo orders/positions (PaperAccount ids) and MT5 ones (tickets).
    @ObservationIgnored private var orderIDs: Set<UUID> = []
    @ObservationIgnored private var positionIDs: Set<UUID> = []
    @ObservationIgnored private var orderTickets: Set<Int> = []
    @ObservationIgnored private var positionTickets: Set<Int> = []
    /// MT5 requests run one after another.
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private weak var market: LiveMarket?
    @ObservationIgnored private weak var trader: PaperTrader?
    @ObservationIgnored private weak var mt5: MT5Trader?

    private static let configKey = "stopbot.config"
    private static let mt5Key = "stopbot.mt5"

    init() {
        config = UserDefaults.standard.data(forKey: Self.configKey)
            .flatMap { try? JSONDecoder().decode(CandleStopBot.Config.self, from: $0) } ?? CandleStopBot.Config()
        preferMT5 = UserDefaults.standard.object(forKey: Self.mt5Key) as? Bool ?? true
    }

    func attach(market: LiveMarket, trader: PaperTrader, mt5: MT5Trader) {
        self.market = market
        self.trader = trader
        self.mt5 = mt5
    }

    /// Where orders would go if the bot started on the current chart.
    var plannedDestination: Destination {
        market?.source == .mt5 && preferMT5 ? .mt5 : .demo
    }

    /// The Live chart is on another symbol or timeframe than the bot's.
    var chartMoved: Bool {
        guard isRunning, let market else { return false }
        return market.symbolKey != symbolKey || market.interval != interval
    }

    /// Number of open positions of the bot.
    var openPositions: Int {
        switch destination {
        case .demo: return trader?.account.positions.filter { positionIDs.contains($0.id) }.count ?? 0
        case .mt5: return mt5?.state?.positions.filter { positionTickets.contains($0.ticket) }.count ?? 0
        }
    }

    func start() {
        guard let market, let trader, !trader.isReplaying else { return }
        symbolKey = market.symbolKey
        symbol = market.symbol
        interval = market.interval
        destination = plannedDestination
        isRunning = true
        hasSession = true
        let account = destination == .mt5
            ? "MT5 #\(mt5?.state?.login.map { String($0) } ?? "")\(mt5?.isReal == true ? " · TIỀN THẬT" : "")" : "demo"
        add("▶︎ Chạy trên \(LiveView.displayName(market.symbol)) \(LiveView.label(market.interval)) · lệnh vào \(account)")
        // Orders from the last closed candle right away.
        if let last = market.closedCandles.last { placeAfter(last) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        switch destination {
        case .demo: cancelDemoOrders()
        case .mt5: enqueue { await self.cancelMT5Orders() }
        }
        add("■ Dừng bot, huỷ lệnh chờ (lệnh đang mở giữ SL/TP)")
    }

    /// Each closed candle of the chart.
    func barClosed(symbol: String, candles: [Candle]) {
        guard isRunning, symbol == symbolKey, market?.interval == interval, let last = candles.last else { return }
        switch destination {
        case .demo:
            checkDemoFills()
            cancelDemoOrders()
            if config.onePosition, openPositions > 0 { return }
            placeDemo(after: last)
        case .mt5:
            enqueue {
                await self.mt5?.refresh()
                self.checkMT5Fills()
                await self.cancelMT5Orders()
                if self.config.onePosition, self.openPositions > 0 { return }
                await self.placeMT5(after: last)
            }
        }
    }

    /// Each price: a bot order that filled becomes a position; OCO cancels the other side.
    func priceUpdated(symbol: String) {
        guard isRunning, symbol == symbolKey else { return }
        switch destination {
        case .demo: checkDemoFills()
        case .mt5:
            // MT5 positions refresh every 2 s (MT5Trader.watch on MT5 charts).
            if checkMT5Fills(), config.oco { enqueue { await self.cancelMT5Orders() } }
        }
    }

    private func placeAfter(_ candle: Candle) {
        switch destination {
        case .demo: placeDemo(after: candle)
        case .mt5: enqueue { await self.placeMT5(after: candle) }
        }
    }

    private func enqueue(_ job: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task { @MainActor in
            await previous?.value
            await job()
        }
    }

    /// Orders of `candle` that are still beyond the current price (a stop at or
    /// behind it would fill at once).
    private func validOrders(after candle: Candle) -> [CandleStopBot.Order] {
        guard let trader, let symbolKey else { return [] }
        let all = CandleStopBot.orders(after: candle, config: config)
        if all.isEmpty {
            add("· Nến \(Self.format(candle.high - candle.low)) ngoài khoảng lọc: không đặt lệnh")
            return []
        }
        let bid = trader.price(symbolKey) ?? candle.close
        let ask = trader.ask(symbolKey) ?? bid
        return all.filter { order in
            let passed = order.side == .long ? ask >= order.entry : bid <= order.entry
            if passed { add("⚠︎ Giá đã vượt \(Self.format(order.entry)): bỏ \(order.side == .long ? "Buy" : "Sell") Stop nến này") }
            return !passed
        }
    }

    private func describe(_ order: CandleStopBot.Order) -> String {
        "\(order.side == .long ? "Buy" : "Sell") Stop \(Self.format(order.entry)) SL \(Self.format(order.stop))"
            + (order.target.map { " TP \(Self.format($0))" } ?? "")
    }

    // MARK: - Demo account

    private func checkDemoFills() {
        guard let trader, !orderIDs.isEmpty else { return }
        let filled = trader.account.positions.filter { orderIDs.contains($0.id) }
        guard !filled.isEmpty else { return }
        for p in filled {
            orderIDs.remove(p.id)
            positionIDs.insert(p.id)
            add("✅ Khớp \(p.side == .long ? "BUY STOP" : "SELL STOP") \(PaperTrader.lots(p.lots)) lot @ \(Self.format(p.entryPrice))")
        }
        if config.oco { cancelDemoOrders() }
        positionIDs.formIntersection(Set(trader.account.positions.map(\.id)))
    }

    private func cancelDemoOrders() {
        guard let trader else { return }
        for order in trader.account.pending where orderIDs.contains(order.id) { trader.cancel(order) }
        orderIDs = []
    }

    private func placeDemo(after candle: Candle) {
        guard let trader, let symbolKey, !trader.isReplaying else { return }
        let bid = trader.price(symbolKey) ?? candle.close
        let ask = trader.ask(symbolKey) ?? bid
        var placed: [String] = []
        for order in validOrders(after: candle) {
            let pending = trader.placePending(symbol: symbolKey, side: order.side, lots: config.lots, entry: order.entry,
                                              stop: order.stop, target: order.target,
                                              currentPrice: order.side == .long ? ask : bid, quiet: true)
            orderIDs.insert(pending.id)
            placed.append(describe(order))
        }
        if !placed.isEmpty { add("⏳ " + placed.joined(separator: " · ")) }
    }

    // MARK: - MT5 account

    /// Moves filled MT5 orders to positions; true when one filled.
    @discardableResult
    private func checkMT5Fills() -> Bool {
        guard let state = mt5?.state, !orderTickets.isEmpty else { return false }
        // An MT5 position keeps the ticket of the order that opened it.
        let filled = state.positions.filter { orderTickets.contains($0.ticket) }
        for p in filled {
            orderTickets.remove(p.ticket)
            positionTickets.insert(p.ticket)
            add("✅ MT5 khớp \(p.side == "long" ? "BUY STOP" : "SELL STOP") \(PaperTrader.lots(p.lots)) lot @ \(Self.format(p.entry))")
        }
        positionTickets.formIntersection(Set(state.positions.map(\.ticket)))
        return !filled.isEmpty
    }

    private func cancelMT5Orders() async {
        guard let mt5 else { return }
        let open = Set(mt5.state?.orders.map(\.ticket) ?? [])
        for ticket in orderTickets where open.contains(ticket) {
            await mt5.cancel(ticket, quiet: true)
            takeError()
        }
        orderTickets = []
    }

    private func placeMT5(after candle: Candle) async {
        guard let mt5, isRunning else { return }
        var placed: [String] = []
        for order in validOrders(after: candle) {
            if let ticket = await mt5.botPending(symbol: symbol, side: order.side, lots: config.lots, entry: order.entry,
                                                 stop: order.stop, target: order.target) {
                orderTickets.insert(ticket)
                placed.append(describe(order) + " #\(ticket)")
            } else {
                takeError()
            }
        }
        if !placed.isEmpty { add("⏳ MT5: " + placed.joined(separator: " · ")) }
    }

    /// MT5 refusals go to the bot log instead of an alert on every candle.
    private func takeError() {
        guard let mt5, let error = mt5.lastError else { return }
        mt5.lastError = nil
        add("⚠︎ MT5: \(error)")
    }

    // MARK: -

    private func add(_ text: String) {
        log.insert(LogEntry(time: Date(), text: text), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.configKey) }
    }

    static func format(_ price: Double) -> String { CandleChart.format(price, CandleChart.decimals(for: price)) }
}

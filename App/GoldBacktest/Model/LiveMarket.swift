import Foundation
import Observation
import UIKit
import UserNotifications
import BacktestKit

/// Where live candles come from.
enum LiveSource: String, Codable {
    /// Public market data, no account needed.
    case binance = "BINANCE"
    /// Binance USDⓈ-M futures: XAUUSDT / XAGUSDT gold and silver perpetuals.
    case binanceFutures = "BINANCE_FUTURES"
    /// OANDA v20 API with the user's token; XAU_USD, forex, indices.
    case oanda = "OANDA"
    /// MetaTrader 5 on the user's VPS (Exness or any MT5 broker), read through the bot server.
    case mt5 = "MT5"

    var title: String {
        switch self {
        case .binance: return "Binance"
        case .binanceFutures: return "Binance Futures"
        case .oanda: return "OANDA"
        case .mt5: return "MT5 (VPS)"
        }
    }
}

/// Live candles from Binance (REST history + WebSocket updates) or OANDA
/// (REST polling) and the signals a chosen strategy gives on each closed bar.
@MainActor
@Observable
final class LiveMarket {
    enum Status: Equatable {
        case idle
        case loading
        case live
        case reconnecting(String)

        var label: String {
            switch self {
            case .idle: return "Tạm dừng"
            case .loading: return "Đang tải…"
            case .live: return "Live"
            case .reconnecting(let reason): return "Mất kết nối: \(reason)"
            }
        }
    }

    static let futuresSymbols = ["XAUUSDT", "XAGUSDT"]
    /// Bars kept in memory, including older history loaded while scrolling back.
    static let maxBars = 20_000
    static let popularSymbols = ["BTCUSDT", "ETHUSDT", "PAXGUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT"]
    static let intervals: [BinanceClient.Interval] = [.s5, .s10, .s15, .s30, .m1, .m5, .m15, .m30, .h1, .h4, .d1, .w1]

    private(set) var source: LiveSource = .binance
    private(set) var symbol = "PAXGUSDT"
    private(set) var interval: BinanceClient.Interval = .m15
    /// True while OANDA is selected but no token is saved.
    private(set) var needsOandaToken = false
    private(set) var buffer = LiveCandleBuffer(maxCount: LiveMarket.maxBars)
    private(set) var ticker: Ticker24h?
    private(set) var status: Status = .idle

    /// Strategy whose signals are tracked; nil = none. Change it with `track(strategy:)`.
    private(set) var strategyID: UUID?
    var notificationsEnabled = true
    private(set) var signals: [LiveSignal] = []
    private(set) var plots: [Plot] = []
    private(set) var strategyError: String?
    private(set) var latestAlert: LiveSignal?
    /// Closed bars in the last scan. Views use this instead of `candles` so
    /// they don't redraw on every price tick.
    private(set) var scannedBarCount = 0

    @ObservationIgnored private weak var store: AppStore?
    /// Receives every price update as (symbol key, price, time); drives the demo account.
    /// Receives every price update as (symbol key, bid, ask, time); drives the demo account.
    @ObservationIgnored var onPrice: (@MainActor (String, Double, Double, Date) -> Void)?

    /// Best bid/ask from the broker or exchange, refreshed a few times a second on screen.
    struct Quote: Equatable {
        var bid: Double
        var ask: Double
        var spread: Double { ask - bid }
    }
    private(set) var quote: Quote?
    @ObservationIgnored private var rawQuote: (bid: Double, ask: Double, time: Date)?
    @ObservationIgnored private var lastQuotePublish = Date.distantPast

    /// Bid and ask to trade at: the live quote when it is fresh and sane, else `last` for both.
    func tradeQuote(last: Double) -> Quote {
        if let q = rawQuote, Date().timeIntervalSince(q.time) < 15, q.ask >= q.bid, q.bid > 0,
           q.ask - q.bid < max(last, q.bid) * 0.01 {
            return Quote(bid: q.bid, ask: q.ask)
        }
        return Quote(bid: last, ask: last)
    }

    private func setQuote(bid: Double, ask: Double) {
        rawQuote = (bid, ask, Date())
        // Book updates arrive many times a second; redraw a few times a second at most.
        if Date().timeIntervalSince(lastQuotePublish) > 0.3 {
            lastQuotePublish = Date()
            quote = Quote(bid: bid, ask: ask)
        }
    }

    private func emitPrice(_ last: Double, time: Date = Date()) {
        let q = tradeQuote(last: last)
        onPrice?(symbolKey, q.bid, q.ask, time)
    }

    /// "SOURCE:SYMBOL", the key for drawings and demo orders.
    var symbolKey: String { "\(source.rawValue):\(symbol)" }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var lastBarClosed = false
    @ObservationIgnored private var alertedSignalIDs: Set<String> = []
    /// Seconds bars built from trades: changes not yet shown, so a busy
    /// market redraws the chart a few times a second instead of per trade.
    @ObservationIgnored private var pendingBuffer: LiveCandleBuffer?
    @ObservationIgnored private var lastPublish = Date.distantPast
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var loadingOlder = false
    /// No older bars exist (start of the market's history).
    @ObservationIgnored private var reachedStart = false

    var candles: [Candle] { buffer.candles }

    /// Bars of the SMT comparison market (e.g. silver for gold), same timeframe.
    private(set) var comparisonCandles: [Candle] = []
    /// Symbol the comparison bars belong to; nil = none loaded.
    private(set) var comparisonSymbol: String?
    private(set) var comparisonError: String?
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?

    /// Correlated market for SMT on this chart: silver for gold and gold for silver.
    var defaultComparisonSymbol: String? {
        switch (source, symbol) {
        case (.binanceFutures, "XAUUSDT"): return "XAGUSDT"
        case (.binanceFutures, "XAGUSDT"): return "XAUUSDT"
        case (.binanceFutures, "BTCUSDT"), (.binance, "BTCUSDT"): return "ETHUSDT"
        case (.binanceFutures, "ETHUSDT"), (.binance, "ETHUSDT"): return "BTCUSDT"
        case (.oanda, "XAU_USD"): return "XAG_USD"
        case (.oanda, "XAG_USD"): return "XAU_USD"
        case (.oanda, "EUR_USD"): return "GBP_USD"
        case (.oanda, "GBP_USD"): return "EUR_USD"
        case (.mt5, _):
            // Exness and most brokers name silver like gold: XAUUSDm ↔ XAGUSDm, XAUUSD.r ↔ XAGUSD.r.
            if symbol.hasPrefix("XAU") { return "XAG" + symbol.dropFirst(3) }
            if symbol.hasPrefix("XAG") { return "XAU" + symbol.dropFirst(3) }
            return nil
        default: return nil
        }
    }

    /// Shows `requested` as the comparison market: loads its history, then
    /// keeps its last bars fresh every 2 seconds while it stays selected.
    /// nil stops it and clears the bars.
    func setComparison(symbol requested: String?) {
        // MT5 symbols are case-sensitive (XAUUSDm).
        let trimmed = requested?.trimmingCharacters(in: .whitespaces)
        let wanted = source == .mt5 ? trimmed : trimmed?.uppercased()
        let target = (wanted?.isEmpty ?? true) ? nil : wanted
        comparisonTask?.cancel()
        comparisonCandles = []
        comparisonError = nil
        guard let target, target != symbol, !interval.isSeconds else {
            comparisonSymbol = nil
            if target != nil, interval.isSeconds { comparisonError = "So sánh không dùng cho khung giây" }
            return
        }
        comparisonSymbol = target
        let source = self.source, interval = self.interval, market = binanceMarket
        comparisonTask = Task { [weak self] in
            var count = 1000
            while !Task.isCancelled {
                do {
                    let bars: [Candle]
                    switch source {
                    case .binance, .binanceFutures:
                        bars = try await BinanceClient.withFallback(market: market) { client in
                            try await client.fetchCandles(symbol: target, interval: interval, count: count)
                        }
                    case .oanda:
                        guard let client = OandaSettings.client() else { return }
                        bars = try await client.fetchCandles(instrument: target, interval: interval, count: count).map(\.candle)
                    case .mt5:
                        guard let client = RemoteBotSettings.client() else { return }
                        bars = try await client.mt5Candles(symbol: target, interval: interval, count: count)
                    }
                    guard let self, !Task.isCancelled, self.comparisonSymbol == target else { return }
                    self.mergeComparison(bars)
                    self.comparisonError = nil
                    count = 3
                } catch {
                    if Task.isCancelled { return }
                    self?.comparisonError = count > 3 ? "Không tải được \(target)" : nil
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func mergeComparison(_ bars: [Candle]) {
        var merged = LiveCandleBuffer(candles: comparisonCandles, maxCount: LiveMarket.maxBars)
        for bar in bars { merged.apply(bar) }
        comparisonCandles = merged.candles
    }

    init() {
        let defaults = UserDefaults.standard
        if let source = defaults.string(forKey: "live.source").flatMap(LiveSource.init),
           let symbol = defaults.string(forKey: "live.symbol"), !symbol.isEmpty {
            self.source = source
            self.symbol = symbol
        }
        if let interval = defaults.string(forKey: "live.interval").flatMap(BinanceClient.Interval.init),
           Self.intervals.contains(interval) {
            self.interval = interval
        }
    }

    /// Candles whose bar has finished; strategies only ever see these.
    var closedCandles: [Candle] {
        lastBarClosed ? buffer.candles : Array(buffer.candles.dropLast())
    }

    // MARK: - Lifecycle

    func start(store: AppStore) {
        self.store = store
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        quoteTask?.cancel()
        quoteTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        status = .idle
    }

    func select(source: LiveSource? = nil, symbol: String? = nil, interval: BinanceClient.Interval? = nil) {
        let newSource = source ?? self.source
        let trimmed = symbol?.trimmingCharacters(in: .whitespaces)
        let newSymbol = (newSource == .mt5 ? trimmed : trimmed?.uppercased()) ?? self.symbol
        let newInterval = interval ?? self.interval
        guard newSource != self.source || newSymbol != self.symbol || newInterval != self.interval,
              !newSymbol.isEmpty else { return }
        self.source = newSource
        self.symbol = newSymbol
        self.interval = newInterval
        let defaults = UserDefaults.standard
        defaults.set(newSource.rawValue, forKey: "live.source")
        defaults.set(newSymbol, forKey: "live.symbol")
        defaults.set(newInterval.rawValue, forKey: "live.interval")
        restart()
    }

    /// Loads up to `count` bars before the oldest one on the chart and puts
    /// them in front of the history. Returns the bars added.
    @discardableResult
    func loadOlder(count: Int = 1000) async -> [Candle] {
        guard !loadingOlder, !reachedStart, let first = buffer.candles.first else { return [] }
        loadingOlder = true
        defer { loadingOlder = false }
        let symbol = self.symbol, interval = self.interval, source = self.source
        var older: [Candle] = []
        do {
            switch source {
            case .binance, .binanceFutures:
                let market: BinanceClient.Market = source == .binanceFutures ? .futures : .spot
                // Seconds bars are built from trades; there is no older history to fetch.
                if interval.isSeconds { return [] }
                older = try await BinanceClient.withFallback(market: market) { client in
                    try await client.fetchCandles(symbol: symbol, interval: interval, count: count, before: first.time)
                }
            case .oanda:
                guard let client = OandaSettings.client() else { return [] }
                older = try await client.fetchCandles(instrument: symbol, interval: interval, count: count, to: first.time)
                    .map(\.candle)
            case .mt5:
                guard let client = RemoteBotSettings.client() else { return [] }
                // Second bars come from Binance trades; there is no older history to fetch.
                if interval.isSeconds { return [] }
                older = try await client.mt5Candles(symbol: symbol, interval: interval, count: count, before: first.time)
            }
        } catch {
            return []
        }
        // The chart may have switched symbol or interval while loading.
        guard symbol == self.symbol, interval == self.interval, source == self.source else { return [] }
        if older.isEmpty { reachedStart = true }
        let before = buffer.candles.count
        buffer.prepend(older)
        let added = Array(buffer.candles.prefix(buffer.candles.count - before))
        if !added.isEmpty { rescan(alert: false) }
        return added
    }

    /// Reloads from scratch, e.g. after the OANDA token changed.
    func restart() {
        reachedStart = false
        buffer = LiveCandleBuffer(maxCount: LiveMarket.maxBars)
        pendingBuffer = nil
        ticker = nil
        signals = []
        plots = []
        alertedSignalIDs = []
        quote = nil
        rawQuote = nil
        let store = self.store
        stop()
        if let store { start(store: store) }
    }

    private func run() async {
        var failures = 0
        while !Task.isCancelled {
            status = .loading
            quoteTask?.cancel()
            quoteTask = nil
            feed = nil
            feedOffset = 0
            do {
                switch source {
                case .binance, .binanceFutures:
                    needsOandaToken = false
                    let symbol = self.symbol, interval = self.interval, market = binanceMarket
                    let history = try await BinanceClient.withFallback(market: market) { client -> [Candle] in
                        if interval.isSeconds {
                            return try await client.fetchSecondCandles(symbol: symbol, seconds: interval.seconds, count: 500)
                        }
                        return try await client.fetchCandles(symbol: symbol, interval: interval, count: 1000)
                    }
                    guard !Task.isCancelled else { return }
                    buffer = LiveCandleBuffer(candles: history, maxCount: LiveMarket.maxBars)
                    pendingBuffer = nil
                    lastBarClosed = false
                    ticker = try? await BinanceClient.withFallback(market: market) { try await $0.fetchTicker(symbol: symbol) }
                    rescan(alert: false)
                    failures = 0
                    try await stream()
                case .oanda:
                    guard let client = OandaSettings.client() else {
                        needsOandaToken = true
                        throw OandaClient.ClientError.missingToken
                    }
                    needsOandaToken = false
                    let history = try await client.fetchCandles(instrument: symbol, interval: interval, count: 1000)
                    guard !Task.isCancelled else { return }
                    buffer = LiveCandleBuffer(candles: history.map(\.candle), maxCount: LiveMarket.maxBars)
                    lastBarClosed = history.last?.complete ?? false
                    ticker = try? await client.fetchTicker(instrument: symbol)
                    rescan(alert: false)
                    failures = 0
                    try await poll(client)
                case .mt5:
                    needsOandaToken = false
                    guard let client = RemoteBotSettings.client() else {
                        throw RemoteBotClient.ServerError(message: "Chưa kết nối máy chủ VPS (Giao dịch → Đăng nhập)")
                    }
                    if interval.isSeconds {
                        try await loadSecondsFromBinance(client)
                        failures = 0
                        try await stream()
                        continue
                    }
                    var history = try await client.mt5Candles(symbol: symbol, interval: interval, count: 1000)
                    // A stretch missing in the middle: MT5 hands a symbol just opened its old cached bars
                    // while it fetches the rest; ask again shortly (up to 3 times).
                    var tries = 0
                    while tries < 3, Self.hole(in: history, seconds: interval.seconds) {
                        tries += 1
                        try await Task.sleep(nanoseconds: 1_200_000_000)
                        history = try await client.mt5Candles(symbol: symbol, interval: interval, count: 1000)
                    }
                    guard !Task.isCancelled else { return }
                    buffer = LiveCandleBuffer(candles: history, maxCount: LiveMarket.maxBars)
                    lastBarClosed = false
                    ticker = nil
                    rescan(alert: false)
                    failures = 0
                    try await pollMT5(client)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                failures += 1
                status = .reconnecting(error.localizedDescription)
            }
            // Back off 2, 4, 8 … up to 30 seconds before reconnecting.
            let delay = min(30, pow(2, Double(min(failures, 5))))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private var binanceMarket: BinanceClient.Market { source == .binanceFutures ? .futures : .spot }

    // MARK: - Second bars on an MT5 chart

    /// MT5 has no bars under a minute: on an MT5 chart the 5s–30s bars come from Binance (gold and
    /// silver from the futures trades, crypto from spot), moved onto the broker's price; orders and
    /// the bid/ask still come from MT5. Nil for symbols Binance does not have (forex, indices).
    static func binanceFeed(for mt5Symbol: String) -> (symbol: String, market: BinanceClient.Market)? {
        let s = mt5Symbol.uppercased()
        if s.contains("XAU") || s.contains("GOLD") { return ("XAUUSDT", .futures) }
        if s.contains("XAG") || s.contains("SILVER") { return ("XAGUSDT", .futures) }
        for coin in ["BTC", "ETH", "SOL", "BNB", "XRP", "DOGE", "ADA", "LTC", "TRX", "DOT", "LINK", "AVAX", "TON"] where s.hasPrefix(coin) {
            return (coin + "USDT", .spot)
        }
        return nil
    }

    /// The Binance market the bars come from while an MT5 chart shows second bars.
    @ObservationIgnored private var feed: (symbol: String, market: BinanceClient.Market)?
    /// Added to Binance prices so the bars sit on the broker's bid (gold on Binance ≠ Exness).
    @ObservationIgnored private var feedOffset = 0.0
    @ObservationIgnored private var quoteTask: Task<Void, Never>?
    /// The symbol and market the WebSocket reads.
    private var streamSymbol: String { feed?.symbol ?? symbol }
    private var streamMarket: BinanceClient.Market { feed?.market ?? binanceMarket }

    /// Second bars on an MT5 chart: Binance bars moved onto the broker's price for the chart, the
    /// broker's bid/ask polled alongside for the order buttons. The bars then come from `stream()`.
    private func loadSecondsFromBinance(_ client: RemoteBotClient) async throws {
        guard let source = Self.binanceFeed(for: symbol) else {
            throw RemoteBotClient.ServerError(message: "Khung giây chỉ có cho vàng, bạc và crypto (nến lấy từ Binance): chọn 1m trở lên")
        }
        let symbol = self.symbol, interval = self.interval
        var history = try await BinanceClient.withFallback(market: source.market) { binance in
            try await binance.fetchSecondCandles(symbol: source.symbol, seconds: interval.seconds, count: 500)
        }
        guard !Task.isCancelled else { throw CancellationError() }
        // The gap between Binance and the broker's bid (MT5 bars are bid prices); a gap over 1 %
        // means a different market, so the bars are left as they are.
        var offset = 0.0
        if let bars = try? await client.mt5Bars(symbol: symbol, interval: .m1, count: 1),
           let bid = bars.bid, let ask = bars.ask, bid > 0, ask >= bid, let last = history.last?.close {
            setQuote(bid: bid, ask: ask)
            if abs(bid - last) < last * 0.01 { offset = bid - last }
        }
        guard !Task.isCancelled else { throw CancellationError() }
        if offset != 0 {
            history = history.map {
                Candle(time: $0.time, open: $0.open + offset, high: $0.high + offset,
                       low: $0.low + offset, close: $0.close + offset, volume: $0.volume)
            }
        }
        feed = source
        feedOffset = offset
        buffer = LiveCandleBuffer(candles: history, maxCount: LiveMarket.maxBars)
        pendingBuffer = nil
        lastBarClosed = false
        ticker = nil
        reachedStart = true
        rescan(alert: false)
        // The broker's bid/ask every 2 s, for the order buttons, the spread and demo fills.
        quoteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let bars = try? await client.mt5Bars(symbol: symbol, interval: .m1, count: 1),
                      let bid = bars.bid, let ask = bars.ask, bid > 0, ask >= bid else { continue }
                guard !Task.isCancelled, let self, self.feed != nil, self.symbol == symbol else { return }
                self.setQuote(bid: bid, ask: ask)
            }
        }
    }

    /// Reads the WebSocket until it fails, trying each stream host in turn.
    private func stream() async throws {
        var lastError: Error = URLError(.cannotConnectToHost)
        for host in streamMarket.streamHosts {
            let url = BinanceStreamEvent.url(host: host, symbol: streamSymbol, interval: interval)
            let socket = URLSession.shared.webSocketTask(with: url)
            self.socket = socket
            socket.resume()
            // A host that accepts the connection but never sends anything is skipped.
            let watchdog = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                socket.cancel(with: .goingAway, reason: nil)
            }
            defer { watchdog.cancel() }
            var received = false
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    if !received {
                        received = true
                        watchdog.cancel()
                        status = .live
                    }
                    let data: Data
                    switch message {
                    case .data(let d): data = d
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    if let event = BinanceStreamEvent.parse(data) { handle(event) }
                }
                throw CancellationError()
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                lastError = error
                // A host that delivered data and then dropped: reload history before retrying.
                if received { throw error }
            }
        }
        throw lastError
    }

    /// OANDA has no public candle stream, so the last bars are re-read every second.
    private func poll(_ client: OandaClient) async throws {
        var catchUp = CatchUp(seconds: interval.seconds)
        var newestComplete = closedCandles.last?.time
        var errors = 0
        var polls = 0
        status = .live
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let latest: [OandaCandle]
            // Too far behind for one poll: reload (the run loop reads the history again).
            let count = try catchUp.count()
            do {
                latest = try await client.fetchCandles(instrument: symbol, interval: interval, count: count)
                catchUp.done()
                errors = 0
                status = .live
            } catch {
                if Task.isCancelled { throw CancellationError() }
                errors += 1
                // A few misses in a row are usually a weak connection; then reload.
                if errors >= 3 { throw error }
                continue
            }
            guard !Task.isCancelled else { throw CancellationError() }
            for item in latest { buffer.apply(item.candle) }
            if let close = latest.last?.candle.close { emitPrice(close) }
            if let last = latest.last, last.candle.time == buffer.candles.last?.time {
                lastBarClosed = last.complete
            }
            if let closedTime = latest.last(where: \.complete)?.candle.time, closedTime != newestComplete {
                newestComplete = closedTime
                rescan(alert: true)
            }
            polls += 1
            if polls % 60 == 0, let fresh = try? await client.fetchTicker(instrument: symbol) {
                ticker = fresh
            } else if var t = ticker, let close = buffer.candles.last?.close {
                t.lastPrice = close
                ticker = t
            }
        }
        throw CancellationError()
    }

    /// A hole in the bars while the market trades: a gap over 2 h (and 3 bars) with no weekend day in it.
    static func hole(in bars: [Candle], seconds: Double) -> Bool {
        guard bars.count > 1 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for i in max(1, bars.count - 1500)..<bars.count {
            let a = bars[i - 1].time, b = bars[i].time
            guard b.timeIntervalSince(a) > max(seconds * 3, 7200) else { continue }
            var t = a, weekend = false
            while t <= b, !weekend {
                let day = calendar.component(.weekday, from: t)   // 1 = Sunday, 7 = Saturday
                weekend = day == 1 || day == 7
                t = t.addingTimeInterval(3 * 3600)
            }
            if !weekend { return true }
        }
        return false
    }

    /// How many of the newest bars a poll reads: 3 normally, every bar since the last poll after the app
    /// slept in the background (else the chart has a hole), and a reload when that is more than a poll holds.
    private struct CatchUp {
        let seconds: Double
        var last = Date()

        struct TooFarBehind: Error {}

        func count() throws -> Int {
            let behind = Date().timeIntervalSince(last) / max(seconds, 1)
            if behind > 700 { throw TooFarBehind() }
            return max(3, Int(behind.rounded(.up)) + 3)
        }

        mutating func done() { last = Date() }
    }

    /// MT5 through the VPS: the last bars are re-read every second, like OANDA.
    private func pollMT5(_ client: RemoteBotClient) async throws {
        var catchUp = CatchUp(seconds: interval.seconds)
        var newestClosed = closedCandles.last?.time
        var errors = 0
        status = .live
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let latest: [Candle]
            // Too far behind for one poll: reload (the run loop reads the history again).
            let count = try catchUp.count()
            do {
                let bars = try await client.mt5Bars(symbol: symbol, interval: interval, count: count)
                latest = bars.candles
                catchUp.done()
                // MT5 bars are bid prices; the server also sends the live bid/ask.
                if let bid = bars.bid, let ask = bars.ask, bid > 0, ask >= bid { setQuote(bid: bid, ask: ask) }
                errors = 0
                status = .live
            } catch {
                if Task.isCancelled { throw CancellationError() }
                errors += 1
                if errors >= 5 { throw error }
                continue
            }
            guard !Task.isCancelled else { throw CancellationError() }
            var newest = latest
            // The newest bars do not follow on from the chart's last one (stale history at the start):
            // fetch every bar in between once, or reload when that is too many.
            if let tail = buffer.candles.last?.time, let first = latest.first?.time,
               first.timeIntervalSince(tail) > interval.seconds * 1.5, let end = latest.last?.time {
                let need = Int((end.timeIntervalSince(tail) / interval.seconds).rounded(.up)) + 3
                guard need <= 1000 else { throw CatchUp.TooFarBehind() }
                if let filled = try? await client.mt5Bars(symbol: symbol, interval: interval, count: need).candles { newest = filled }
                guard !Task.isCancelled else { throw CancellationError() }
            }
            for bar in newest { buffer.apply(bar) }
            lastBarClosed = false
            if let close = newest.last?.close { emitPrice(close) }
            // Every bar before the newest has closed.
            if newest.count >= 2, newest[newest.count - 2].time != newestClosed {
                newestClosed = newest[newest.count - 2].time
                rescan(alert: true)
            }
        }
        throw CancellationError()
    }

    private func handle(_ event: BinanceStreamEvent) {
        switch event {
        case .kline(let eventSymbol, let candle, let isClosed):
            guard eventSymbol.uppercased() == symbol else { return }
            let update = buffer.apply(candle)
            emitPrice(candle.close)
            if update == .appended { lastBarClosed = false }
            if update != .ignored, isClosed {
                lastBarClosed = true
                rescan(alert: true)
            }
            if var t = ticker {
                t.lastPrice = candle.close
                ticker = t
            }
        case .book(let bookSymbol, let bid, let ask):
            // On an MT5 chart the bid/ask is the broker's, not Binance's.
            guard feed == nil, bookSymbol.uppercased() == symbol else { return }
            setQuote(bid: bid, ask: ask)
            if let last = buffer.candles.last?.close { emitPrice(last) }
        case .ticker(let t):
            if feed == nil, t.symbol.uppercased() == symbol {
                var t = t
                // Seconds bars: the newest trade is fresher than the ticker.
                if interval.isSeconds, let close = (pendingBuffer ?? buffer).candles.last?.close { t.lastPrice = close }
                ticker = t
            }
        case .trade(let tradeSymbol, var trade):
            guard tradeSymbol.uppercased() == streamSymbol, interval.isSeconds else { return }
            trade.price += feedOffset
            var working = pendingBuffer ?? buffer
            let update = working.apply(trade: trade, seconds: interval.seconds)
            emitPrice(trade.price, time: trade.time)
            guard update != .ignored else { return }
            if update == .appended || Date().timeIntervalSince(lastPublish) > 0.25 {
                publish(working)
                if update == .appended {
                    // The previous bar has just closed.
                    lastBarClosed = false
                    rescan(alert: true)
                }
            } else {
                pendingBuffer = working
                scheduleFlush()
            }
        }
    }

    private func publish(_ working: LiveCandleBuffer) {
        buffer = working
        pendingBuffer = nil
        lastPublish = Date()
        if var t = ticker, let close = working.candles.last?.close {
            t.lastPrice = close
            ticker = t
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            self.flushScheduled = false
            if let pending = self.pendingBuffer { self.publish(pending) }
        }
    }

    // MARK: - Signals

    func track(strategy id: UUID?) {
        guard id != strategyID else { return }
        strategyID = id
        alertedSignalIDs = []
        rescan(alert: false)
    }

    /// Receives the closed bars each time a bar closes; drives trade management.
    @ObservationIgnored var onBarClose: (@MainActor (String, [Candle]) -> Void)?
    /// Receives the new signals of the tracked strategy on each closed bar (the bot).
    @ObservationIgnored var onSignals: (@MainActor ([LiveSignal], String) -> Void)?

    func rescan(alert: Bool) {
        if alert { onBarClose?(symbolKey, closedCandles) }
        guard let store, let id = strategyID, let strategy = store.strategies.first(where: { $0.id == id }) else {
            signals = []
            plots = []
            strategyError = nil
            return
        }
        let closed = closedCandles
        scannedBarCount = closed.count
        guard closed.count > 10 else { return }
        do {
            let scan = try LiveSignalScanner.scan(strategy: strategy, candles: closed, config: store.config,
                                                  library: store.library)
            signals = scan.signals
            // Pad plots with NaN for the bar that is still forming.
            let extra = buffer.candles.count - closed.count
            plots = scan.plots.map { plot in
                var p = plot
                p.values += Series(repeating: .nan, count: max(0, extra))
                return p
            }
            strategyError = nil
            let fresh = scan.signals.filter { $0.barIndex == closed.count - 1 && !alertedSignalIDs.contains($0.id) }
            alertedSignalIDs.formUnion(scan.signals.map(\.id))
            if alert, !fresh.isEmpty { onSignals?(fresh, symbolKey) }
            // The bot reports each signal with what it did; plain alerts only without it.
            if alert, onSignals == nil, let signal = fresh.first(where: \.kind.isEntry) ?? fresh.first {
                latestAlert = signal
                announce(signal, strategy: strategy.name)
            }
        } catch {
            strategyError = error.localizedDescription
        }
    }

    private func announce(_ signal: LiveSignal, strategy: String) {
        UINotificationFeedbackGenerator().notificationOccurred(signal.kind.isEntry ? .success : .warning)
        if VoiceSettings.speakSignals, signal.kind.isEntry {
            VoiceAnnouncer.shared.speak(signal.kind == .longEntry
                ? VoiceSettings.phrase(VoiceSettings.buyKey, default: VoiceSettings.defaultBuy)
                : VoiceSettings.phrase(VoiceSettings.sellKey, default: VoiceSettings.defaultSell))
        }
        guard notificationsEnabled else { return }
        let title = "\(LiveView.displayName(symbol)) · \(signal.kind.label)"
        var body = "\(strategy) · giá \(CandleChart.format(signal.price, CandleChart.decimals(for: signal.price)))"
        if let stop = signal.stop { body += " · SL \(CandleChart.format(stop, CandleChart.decimals(for: stop)))" }
        if let target = signal.target { body += " · TP \(CandleChart.format(target, CandleChart.decimals(for: target)))" }
        AlertSettings.post(title: title, body: body, id: signal.id, signal: true)
    }

    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

/// Shows notifications as banners while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

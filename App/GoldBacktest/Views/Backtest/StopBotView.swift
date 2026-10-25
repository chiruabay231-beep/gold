import SwiftUI
import BacktestKit

/// Settings, backtest and start/stop of the "Stop theo nến" bot: on the VPS (the same
/// bot as the website's Bot tab, 24/7) or in the app.
struct StopBotView: View {
    @Environment(LiveMarket.self) private var market
    @Environment(PaperTrader.self) private var trader
    @Environment(StopBotController.self) private var bot
    @Environment(MT5Trader.self) private var mt5
    @State private var confirmReal = false
    @State private var confirmVpsReal = false
    @State private var report: CandleStopBot.Report?
    @State private var testedBars = 0

    /// "vps" (the server's bot, shared with the website) or "app".
    @AppStorage("stopbot.runOn") private var runOn = "vps"
    @AppStorage("stopbot.vpsSymbol") private var vpsSymbol = ""
    @AppStorage("stopbot.vpsInterval") private var vpsInterval = "1m"
    @State private var remote = RemoteBot()
    /// The server's settings were copied into the form once.
    @State private var synced = false
    @State private var showSymbols = false
    /// Backtest data: 0 = the Live chart's bars, otherwise that many days of Exness bars.
    @AppStorage("stopbot.testDays") private var testDays = 7
    @State private var testing = false
    @State private var testProgress = ""
    @State private var testError: String?
    @State private var testInfo = ""

    static let vpsIntervals = ["1m", "5m", "15m", "30m", "1h", "4h"]

    private var hasVPS: Bool { RemoteBotSettings.client() != nil }
    private var onVPS: Bool { hasVPS && runOn == "vps" }
    private var vpsRunning: Bool { remote.stopBot?.isRunning == true }
    /// Symbol and timeframe of the VPS bot and of an Exness backtest.
    private var symbolChoice: String {
        if !vpsSymbol.isEmpty { return vpsSymbol }
        return market.source == .mt5 ? market.symbol : "XAUUSDm"
    }

    var body: some View {
        @Bindable var bot = bot
        List {
            if hasVPS {
                Section {
                    Picker("Chạy bot ở", selection: $runOn) {
                        Text("Máy chủ VPS").tag("vps")
                        Text("Trong app").tag("app")
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(onVPS
                         ? "Bot chạy 24/7 trên VPS, đặt lệnh vào tài khoản MT5 đăng nhập trên VPS. Đây cũng là bot ở tab Bot trên web: bật/tắt hay đổi cài đặt ở web hoặc ở đây thì chỗ kia đều thấy."
                         : "Bot chạy trên điện thoại khi app đang mở, theo mã và khung của tab Live.")
                }
            }

            Section {
                Picker("Hướng", selection: $bot.config.direction) {
                    Text("Buy Stop + Sell Stop").tag(CandleStopBot.Direction.both)
                    Text("Chỉ Buy Stop").tag(CandleStopBot.Direction.long)
                    Text("Chỉ Sell Stop").tag(CandleStopBot.Direction.short)
                }
                numberRow("Khối lượng (lot)", value: $bot.config.lots, minimum: 0.01)
                numberRow("Cách đỉnh/đáy nến (giá)", value: $bot.config.offset)
                Picker("Stop loss", selection: $bot.config.stopMode) {
                    Text("Đầu kia của nến").tag(CandleStopBot.StopMode.candle)
                    Text("Cố định").tag(CandleStopBot.StopMode.fixed)
                }
                if bot.config.stopMode == .fixed {
                    numberRow("SL cách giá vào", value: $bot.config.stopDistance)
                }
                numberRow("TP = R × rủi ro (0 = không TP)", value: $bot.config.rr)
            } header: {
                Text("Lệnh")
            } footer: {
                Text("Mỗi nến đóng: Buy Stop trên đỉnh nến, Sell Stop dưới đáy nến. SL ở đầu kia của nến (hoặc cố định), TP = R × khoảng SL. Lệnh chưa khớp được thay bằng lệnh của nến mới.")
            }

            Section {
                Toggle("Khớp một bên thì huỷ bên kia (OCO)", isOn: $bot.config.oco)
                Toggle("Chỉ một lệnh mở mỗi lúc", isOn: $bot.config.onePosition)
                numberRow("Bỏ nến nhỏ hơn (giá, 0 = không lọc)", value: $bot.config.minRange)
                numberRow("Bỏ nến lớn hơn (giá, 0 = không lọc)", value: $bot.config.maxRange)
            } header: {
                Text("Lọc")
            }

            if onVPS { vpsSection } else { appSection }

            testSection

            if onVPS {
                Section("Nhật ký bot trên VPS") {
                    let events = remote.stopBot?.events ?? []
                    if events.isEmpty { Text("Chưa có hoạt động").foregroundColor(.secondary) }
                    ForEach(events.prefix(30)) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.text).font(.subheadline.monospacedDigit())
                            Text(Date(timeIntervalSince1970: e.time).formatted(date: .abbreviated, time: .standard))
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            } else {
            Section("Nhật ký") {
                if bot.log.isEmpty {
                    Text("Chưa có hoạt động").foregroundColor(.secondary)
                }
                ForEach(bot.log) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text).font(.subheadline.monospacedDigit())
                        Text(entry.time.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            }
        }
        .sheet(isPresented: $showSymbols) {
            MT5SymbolSearchView { symbol in vpsSymbol = symbol }
        }
        .task {
            // The same bot as the website's: its state (and changes made there) every 5 s.
            guard hasVPS else { return }
            while !Task.isCancelled {
                await remote.refreshStatus()
                if !synced, let st = remote.stopBot {
                    synced = true
                    if st.isConfigured, let c = st.config { useServerSettings(c) }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .confirmationDialog("Bot trên VPS đặt lệnh TIỀN THẬT?", isPresented: $confirmVpsReal, titleVisibility: .visible) {
            Button("Chạy bot trên tài khoản thật", role: .destructive) { sendToVPS(running: true) }
        } message: {
            Text("Mỗi nến đóng bot đặt Buy Stop / Sell Stop \(PaperTrader.lots(bot.config.lots)) lot \(symbolChoice) vào tài khoản MT5 \(mt5Account).")
        }
        .confirmationDialog("Bot đặt lệnh TIỀN THẬT?", isPresented: $confirmReal, titleVisibility: .visible) {
            Button("Chạy bot trên tài khoản thật", role: .destructive) { bot.start() }
        } message: {
            Text("Mỗi nến đóng bot đặt Buy Stop / Sell Stop \(PaperTrader.lots(bot.config.lots)) lot vào tài khoản MT5 \(mt5Account).")
        }
        .navigationTitle("Bot Stop theo nến")
        .task(id: market.source == .mt5) {
            if market.source == .mt5 { await mt5.refresh() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: bot.config) { _, _ in report = nil }
    }

    private var mt5Account: String {
        guard let state = mt5.state, let login = state.login else { return "" }
        return "#\(login)" + (state.mode == "real" ? " · THẬT" : " · demo")
    }

    @ViewBuilder
    private func results(_ r: CandleStopBot.Report) -> some View {
        let trades = r.account.history.count
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                stat("Lệnh", "\(trades)")
                stat("Thắng", String(format: "%.0f%%", r.winRate * 100))
                stat("Lãi/lỗ", String(format: "%+.2f", r.netProfit), color: r.netProfit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
            }
            GridRow {
                stat("Sụt giảm max", String(format: "%.2f", r.maxDrawdown))
                stat("Lệnh chờ đặt", "\(r.ordersPlaced)")
                stat("Nến", "\(testedBars)")
            }
        }
        .padding(.vertical, 4)
        ForEach(Array(r.trades.suffix(15).reversed())) { t in
            HStack {
                Text(t.side == .long ? "BUY" : "SELL")
                    .font(.caption.bold())
                    .foregroundColor(t.side == .long ? OrderRow.profitColor : OrderRow.lossColor)
                    .frame(width: 38, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(StopBotController.format(t.entryPrice)) → \(StopBotController.format(t.exitPrice))")
                        .font(.caption.monospacedDigit())
                    Text("\(t.openTime.formatted(date: .abbreviated, time: .shortened)) · \(reason(t.reason))")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%+.2f", t.profit))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(t.profit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
            }
        }
    }

    private func stat(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline.monospacedDigit().bold()).foregroundColor(color)
        }
    }

    private func reason(_ r: PaperAccount.ExitReason) -> String {
        switch r {
        case .target: return "TP"
        case .stop: return "SL"
        case .manual: return "đóng cuối test"
        case .reversal: return "đảo chiều"
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, minimum: Double = 0) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = max(minimum, $0) }),
                      format: .number.precision(.fractionLength(0...4)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
    }

    // MARK: - On the VPS (shared with the website)

    private var vpsSection: some View {
        Section {
            Button { showSymbols = true } label: {
                LabeledContent("Mã MT5", value: symbolChoice)
            }
            Picker("Khung nến", selection: $vpsInterval) {
                ForEach(Self.vpsIntervals, id: \.self) { Text($0).tag($0) }
            }
            if let st = remote.stopBot {
                LabeledContent("Trạng thái") {
                    Text(st.isRunning ? "● Đang chạy · \(st.config?.symbol ?? "") \(st.config?.interval ?? "")" : "Đang tắt")
                        .foregroundColor(st.isRunning ? OrderRow.profitColor : .secondary)
                }
                if let s = st.stats, (s.trades ?? 0) > 0 || st.isRunning {
                    LabeledContent("Kết quả từ lúc bật", value: "\(s.trades ?? 0) lệnh · thắng \(s.wins ?? 0) · \(String(format: "%+.2f", s.profit ?? 0))")
                }
                LabeledContent("Lệnh chờ / đang mở", value: "\(st.orders?.count ?? 0) / \(st.positions?.count ?? 0)")
                if let e = st.error, !e.isEmpty {
                    Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundColor(.orange)
                }
            } else if let e = remote.error {
                Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundColor(.orange)
            } else {
                HStack { ProgressView(); Text("Đang đọc bot trên VPS…").foregroundColor(.secondary) }
            }
            if vpsRunning {
                Button { sendToVPS(running: nil) } label: {
                    Label("Lưu cài đặt lên VPS", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                Button(role: .destructive) { sendToVPS(running: false) } label: {
                    Label("Dừng bot trên VPS (huỷ lệnh chờ)", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    if mt5.isReal { confirmVpsReal = true } else { sendToVPS(running: true) }
                } label: {
                    Label("Chạy bot trên VPS", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }
                .disabled(remote.stopBot == nil)
            }
            if remote.isBusy { ProgressView() }
            if remote.stopBot?.isConfigured == true {
                Button("↻ Lấy lại cài đặt đang lưu trên VPS") {
                    if let c = remote.stopBot?.config { useServerSettings(c) }
                }
                .font(.footnote)
            }
        } header: {
            Text("Bot trên máy chủ VPS")
        } footer: {
            Text("Cần máy chủ bản 2.8 trở lên. Cài đặt ở trên được gửi lên VPS khi bấm Chạy hoặc Lưu. Nút ▶︎/⏸ cạnh BUY/SELL ở tab Live cũng bật/tắt bot này.")
        }
    }

    private func useServerSettings(_ c: RemoteStopBot.Config) {
        bot.config = c.botConfig
        if let symbol = c.symbol, !symbol.isEmpty { vpsSymbol = symbol }
        if let interval = c.interval, Self.vpsIntervals.contains(interval) { vpsInterval = interval }
    }

    private func sendToVPS(running: Bool?) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let body = RemoteStopBot.body(bot.config, symbol: symbolChoice, interval: vpsInterval, running: running)
        Task { await remote.saveStopBot(body) }
    }

    // MARK: - In the app

    private var appSection: some View {
        Section {
            LabeledContent("Mã", value: LiveView.displayName(market.symbol))
            LabeledContent("Khung", value: LiveView.label(market.interval))
            if market.source == .mt5 {
                Picker("Đặt lệnh vào", selection: Binding(get: { bot.preferMT5 }, set: { bot.preferMT5 = $0 })) {
                    Text("Tài khoản MT5 \(mt5Account)").tag(true)
                    Text("Demo trong app").tag(false)
                }
                .disabled(bot.isRunning)
            } else {
                LabeledContent("Đặt lệnh vào", value: "Demo trong app")
            }
            if bot.isRunning {
                LabeledContent("Đang chạy", value: "\(LiveView.displayName(bot.symbol)) \(bot.interval.map(LiveView.label) ?? "") · \(bot.destination == .mt5 ? "MT5" : "demo")")
                if bot.chartMoved {
                    Label("Tab Live đang mở mã/khung khác: bot chờ cho tới khi quay lại \(bot.symbolKey.map { LiveView.displayName(PaperTrader.bareSymbol($0)) } ?? "") \(bot.interval.map(LiveView.label) ?? "").",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundColor(.orange)
                }
                Button(role: .destructive) { bot.stop() } label: {
                    Label("Dừng bot (huỷ lệnh chờ)", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    if bot.plannedDestination == .mt5, mt5.isReal { confirmReal = true } else { bot.start() }
                } label: {
                    Label(bot.plannedDestination == .mt5 ? "Chạy bot trên tài khoản MT5" : "Chạy bot trên tài khoản demo",
                          systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }
                .disabled(market.closedCandles.isEmpty || trader.isReplaying)
            }
        } header: {
            Text("Bot trong app")
        } footer: {
            Text("Chạy được trên mọi mã của mọi nguồn giá ở tab Live (Binance, OANDA, MT5…). Đổi mã/khung ở tab Live. Biểu đồ nguồn MT5 đặt lệnh thẳng vào tài khoản MT5 (tài khoản thật luôn hỏi lại); nguồn khác đặt lệnh demo. Chỉ chạy khi app đang mở (hoặc bật Chạy nền).")
        }
    }

    // MARK: - Backtest

    private var testSection: some View {
        Section {
            Picker("Dữ liệu", selection: $testDays) {
                Text("Nến biểu đồ Live (\(market.closedCandles.count))").tag(0)
                if hasVPS {
                    ForEach([1, 3, 7, 14, 30, 60], id: \.self) { Text("Exness \($0) ngày").tag($0) }
                }
            }
            if testDays > 0 {
                Button { showSymbols = true } label: { LabeledContent("Mã MT5", value: symbolChoice) }
                Picker("Khung nến", selection: $vpsInterval) {
                    ForEach(Self.vpsIntervals, id: \.self) { Text($0).tag($0) }
                }
            } else {
                LabeledContent("Mã · khung", value: "\(LiveView.displayName(market.symbol)) \(LiveView.label(market.interval))")
            }
            Button {
                Task { await runTest() }
            } label: {
                if testing {
                    HStack(spacing: 8) { ProgressView(); Text(testProgress).foregroundColor(.secondary) }
                } else {
                    Label("Chạy backtest bot", systemImage: "flask")
                }
            }
            .disabled(testing || (testDays == 0 && market.closedCandles.count < 3))
            if let testError {
                Label(testError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundColor(.orange)
            }
            if let report {
                if !testInfo.isEmpty { Text(testInfo).font(.caption).foregroundColor(.secondary) }
                results(report)
            }
        } header: {
            Text("Backtest bot")
        } footer: {
            Text("Chạy bot với đúng cài đặt ở trên trên nến đã qua: mỗi nến đóng đặt Buy Stop / Sell Stop, xem bot vào lệnh ở đâu, chạm TP hay SL, lời lỗ bao nhiêu. Không tính spread và trượt giá; lệnh khớp đúng giá stop. Trên web (tab Bot) còn xem được từng lệnh trên biểu đồ.")
        }
    }

    @MainActor
    private func runTest() async {
        testError = nil
        guard testDays > 0 else {
            let candles = market.closedCandles
            testedBars = candles.count
            testInfo = "\(LiveView.displayName(market.symbol)) \(LiveView.label(market.interval)) · \(candles.count) nến biểu đồ Live"
            report = CandleStopBot.backtest(candles: candles, symbol: market.symbolKey, config: bot.config,
                                            startingBalance: startingBalance)
            return
        }
        guard let client = RemoteBotSettings.client() else { return }
        let symbol = symbolChoice
        let interval = BinanceClient.Interval(rawValue: vpsInterval) ?? .m1
        let start = Date().addingTimeInterval(-Double(testDays) * 86_400)
        testing = true
        defer { testing = false }
        do {
            testProgress = "Đang tải nến \(symbol)…"
            // The newest bar is still forming: left out.
            var bars = Array(try await client.mt5Candles(symbol: symbol, interval: interval, count: 5000).dropLast())
            var pages = 0
            while let first = bars.first, first.time > start, pages < 20 {
                testProgress = "Đang tải nến \(symbol)… \(bars.count)"
                let older = try await client.mt5Candles(symbol: symbol, interval: interval, count: 5000, before: first.time)
                    .filter { $0.time < first.time }
                guard !older.isEmpty else { break }
                bars = older + bars
                pages += 1
            }
            bars.removeAll { $0.time < start }
            guard bars.count >= 3 else {
                throw RemoteBotClient.ServerError(message: "MT5 chỉ trả \(bars.count) nến \(symbol) \(interval.rawValue).")
            }
            testedBars = bars.count
            testInfo = "\(symbol) \(interval.rawValue) · \(testDays) ngày · \(bars.count) nến Exness"
            report = CandleStopBot.backtest(candles: bars, symbol: symbol, config: bot.config, startingBalance: startingBalance)
        } catch {
            testError = error.localizedDescription
        }
    }

    private var startingBalance: Double {
        let balance = UserDefaults.standard.double(forKey: "position.balance")
        return balance > 0 ? balance : 10_000
    }
}

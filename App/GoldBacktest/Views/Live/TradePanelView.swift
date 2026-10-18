import SwiftUI
import BacktestKit

/// The "Giao dịch" tab: the demo account with open positions, pending
/// (limit) orders and closed trades, a manual order form, live strategy
/// signals and the backtest data sets. Orders fill against the live price.
struct TradePanelView: View {
    @Environment(PaperTrader.self) private var trader
    @Environment(LiveMarket.self) private var market
    @Environment(AppStore.self) private var store

    enum Page: String, CaseIterable, Identifiable {
        case open = "Đang mở", pending = "Lệnh chờ", history = "Lịch sử"
        var id: String { rawValue }
    }

    @AppStorage("trade.lots") private var lots = 0.01
    @State private var page = Page.open
    @State private var stopText = ""
    @State private var targetText = ""
    @State private var showVoiceSettings = false
    @State private var showAutoStops = false
    @State private var confirmReset = false
    @State private var resetBalance = 10_000.0

    private var symbol: String { market.symbolKey }
    private var price: Double { market.ticker?.lastPrice ?? market.candles.last?.close ?? 0 }
    private var decimals: Int { CandleChart.decimals(for: price) }

    var body: some View {
        List {
            accountSection
            Section {
                Picker("Lệnh", selection: $page) {
                    ForEach(Page.allCases) { item in
                        Text("\(item.rawValue) (\(count(item)))").tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                switch page {
                case .open: positionRows
                case .pending: pendingRows
                case .history: historyRows
                }
            }
            orderSection
            Section("Cài đặt") {
                Button { showAutoStops = true } label: { Label("SL/TP tự động & quản lý lệnh…", systemImage: "slider.horizontal.3") }
                Button { showVoiceSettings = true } label: { Label("Cảnh báo giọng nói…", systemImage: "speaker.wave.2") }
                Button { store.selectedTab = .live } label: { Label("Mở biểu đồ Live", systemImage: "chart.xyaxis.line") }
            }
            Section {
                NavigationLink {
                    DatasetListView()
                } label: {
                    Label("Dữ liệu backtest (CSV, Binance) · \(store.datasets.count)", systemImage: "chart.bar.xaxis")
                }
            } footer: {
                Text("Tài khoản demo trong app: lệnh khớp theo giá realtime đang xem (không qua sàn, không có spread/phí). Lệnh chỉ được theo dõi khi app đang chạy và đang mở đúng mã đó.")
            }
            Section {
                Button("Làm mới tài khoản demo", role: .destructive) {
                    resetBalance = trader.account.startingBalance
                    confirmReset = true
                }
            }
        }
        .navigationTitle("Giao dịch demo")
        .sheet(isPresented: $showVoiceSettings) { VoiceSettingsView() }
        .sheet(isPresented: $showAutoStops) { AutoStopSettingsView() }
        .alert("Làm mới tài khoản demo", isPresented: $confirmReset) {
            TextField("Số dư", value: $resetBalance, format: .number).keyboardType(.decimalPad)
            Button("Huỷ", role: .cancel) {}
            Button("Làm mới", role: .destructive) { trader.reset(balance: max(1, resetBalance)) }
        } message: {
            Text("Xoá mọi lệnh và lịch sử, đặt lại số dư.")
        }
    }

    private func count(_ page: Page) -> Int {
        switch page {
        case .open: return trader.account.positions.count
        case .pending: return trader.account.pending.count
        case .history: return trader.account.history.count
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        let closed = trader.account.balance - trader.account.startingBalance
        let wins = trader.account.history.filter { $0.profit > 0 }.count
        let total = trader.account.history.count
        return Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    stat("Số dư", money(trader.account.balance), .primary)
                    stat("Vốn hiện tại", money(trader.equity), .primary)
                }
                GridRow {
                    stat("Lãi/lỗ đang mở", signedMoney(trader.openProfit), trader.openProfit >= 0 ? .green : .red)
                    stat("Đã chốt", signedMoney(closed), closed >= 0 ? .green : .red)
                }
                GridRow {
                    stat("Lệnh đã đóng", "\(total)", .primary)
                    stat("Tỉ lệ thắng", total == 0 ? "–" : String(format: "%.0f%%", Double(wins) / Double(total) * 100), .primary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Tài khoản demo")
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Orders

    @ViewBuilder
    private var positionRows: some View {
        if trader.account.positions.isEmpty {
            Text("Chưa có lệnh đang mở").foregroundColor(.secondary)
        }
        ForEach(trader.account.positions) { position in
            let current = trader.price(position.symbol)
            let profit = current.map { position.profit(at: $0) }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sideText(position.side == .long ? "BUY" : "SELL", long: position.side == .long)
                    Text("\(PaperTrader.lots(position.lots)) lot \(LiveView.displayName(PaperTrader.bareSymbol(position.symbol)))")
                    Spacer()
                    Text(profit.map(signedMoney) ?? "–")
                        .fontWeight(.semibold)
                        .foregroundColor((profit ?? 0) >= 0 ? .green : .red)
                }
                HStack {
                    Text(levels(entry: position.entryPrice, stop: position.stop, target: position.target))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Đóng lệnh") { trader.close(position) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .disabled(current == nil)
                }
                Text(position.openTime.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pendingRows: some View {
        if trader.account.pending.isEmpty {
            Text("Chưa có lệnh chờ. Bấm \"Lệnh Limit\" trên biểu đồ Live để đặt.").foregroundColor(.secondary)
        }
        ForEach(trader.account.pending) { order in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sideText(orderType(order), long: order.side == .long)
                    Text("\(PaperTrader.lots(order.lots)) lot \(LiveView.displayName(PaperTrader.bareSymbol(order.symbol)))")
                    Spacer()
                    Button("Huỷ") { trader.cancel(order) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                Text(levels(entry: order.entry, stop: order.stop, target: order.target))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(order.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var historyRows: some View {
        if trader.account.history.isEmpty {
            Text("Chưa có lệnh đã đóng").foregroundColor(.secondary)
        }
        ForEach(trader.account.history.prefix(200)) { trade in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sideText(trade.side == .long ? "BUY" : "SELL", long: trade.side == .long)
                    Text("\(PaperTrader.lots(trade.lots)) \(LiveView.displayName(PaperTrader.bareSymbol(trade.symbol)))")
                    Spacer()
                    Text(signedMoney(trade.profit))
                        .fontWeight(.semibold)
                        .foregroundColor(trade.profit >= 0 ? .green : .red)
                }
                Text("\(CandleChart.format(trade.entryPrice, decimals)) → \(CandleChart.format(trade.exitPrice, decimals)) · \(reason(trade.reason))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text("\(trade.openTime.formatted(date: .abbreviated, time: .shortened)) → \(trade.closeTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sideText(_ text: String, long: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(.white)
            .background(long ? Color(red: 0.161, green: 0.384, blue: 1.0) : Color(red: 0.949, green: 0.212, blue: 0.271),
                        in: RoundedRectangle(cornerRadius: 4))
    }

    private var orderSection: some View {
        Section {
            HStack {
                Text(LiveView.displayName(market.symbol)).font(.headline)
                Spacer()
                Text(CandleChart.format(price, decimals)).font(.headline.monospacedDigit())
            }
            Stepper(value: $lots, in: 0.01...100, step: 0.01) {
                HStack {
                    Text("Khối lượng")
                    Spacer()
                    TextField("lot", value: $lots, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                    Text("lot").foregroundColor(.secondary)
                }
            }
            priceRow("Cắt lỗ (SL)", text: $stopText)
            priceRow("Chốt lời (TP)", text: $targetText)
            HStack(spacing: 12) {
                orderButton("BÁN", color: .red) {
                    trader.sell(symbol: symbol, lots: lots, price: price, stop: Self.parse(stopText), target: Self.parse(targetText))
                }
                orderButton("MUA", color: Color(red: 0.161, green: 0.384, blue: 1.0)) {
                    trader.buy(symbol: symbol, lots: lots, price: price, stop: Self.parse(stopText), target: Self.parse(targetText))
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("Lệnh thị trường")
        } footer: {
            Text("Để trống SL/TP nếu không dùng. Muốn đặt lệnh chờ: vẽ Vị thế Long/Short trên biểu đồ, chọn nó rồi bấm nút ✈︎ \"Vào lệnh demo\".")
        }
    }

    // MARK: - Helpers

    private func priceRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Không", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Button {
                text.wrappedValue = CandleChart.format(price, decimals)
            } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(.borderless)
        }
    }

    private func orderButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color, in: .rect(cornerRadius: 8))
                .foregroundColor(.white)
        }
        .buttonStyle(.borderless)
        .disabled(price <= 0 || lots <= 0)
    }

    private func orderType(_ order: PaperAccount.PendingOrder) -> String {
        switch (order.side, order.triggersAbove) {
        case (.long, true): return "BUY STOP"
        case (.long, false): return "BUY LIMIT"
        case (.short, true): return "SELL LIMIT"
        case (.short, false): return "SELL STOP"
        }
    }

    private func levels(entry: Double, stop: Double?, target: Double?) -> String {
        var parts = ["Vào \(CandleChart.format(entry, decimals))"]
        if let stop { parts.append("SL \(CandleChart.format(stop, decimals))") }
        if let target { parts.append("TP \(CandleChart.format(target, decimals))") }
        return parts.joined(separator: " · ")
    }

    private func reason(_ reason: PaperAccount.ExitReason) -> String {
        switch reason {
        case .target: return "Chạm TP"
        case .stop: return "Chạm SL"
        case .manual: return "Đóng tay"
        case .reversal: return "Tự chốt (đảo chiều)"
        }
    }

    /// Reads a price typed with either "." or "," as decimal separator.
    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func money(_ value: Double) -> String { String(format: "%.2f $", value) }
    private func signedMoney(_ value: Double) -> String { String(format: "%+.2f $", value) }
}

/// Voice alert phrases, language and background listening.
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(VoiceSettings.enabledKey) private var enabled = true
    @AppStorage(VoiceSettings.languageKey) private var language = "en-US"
    @AppStorage(VoiceSettings.targetKey) private var target = VoiceSettings.defaultTarget
    @AppStorage(VoiceSettings.stopKey) private var stop = VoiceSettings.defaultStop
    @AppStorage(VoiceSettings.entryKey) private var entry = VoiceSettings.defaultEntry
    @AppStorage(VoiceSettings.detailsKey) private var details = false
    @AppStorage(VoiceSettings.backgroundKey) private var background = false
    @AppStorage(VoiceSettings.keepAwakeKey) private var keepAwake = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Đọc cảnh báo bằng giọng nói", isOn: $enabled)
                    Picker("Giọng", selection: $language) {
                        Text("Tiếng Anh").tag("en-US")
                        Text("Tiếng Việt").tag("vi-VN")
                    }
                }
                Section("Câu đọc khi") {
                    phraseRow("Chạm TP", text: $target)
                    phraseRow("Chạm SL", text: $stop)
                    phraseRow("Lệnh chờ khớp", text: $entry)
                    Toggle("Đọc thêm mã, giá, số tiền lãi/lỗ", isOn: $details)
                }
                Section {
                    Toggle("Chạy nền (nghe khi khoá màn hình)", isOn: $background)
                    Toggle("Giữ màn hình luôn sáng", isOn: $keepAwake)
                } header: {
                    Text("Khi không cầm điện thoại")
                } footer: {
                    Text("Chạy nền giữ app hoạt động khi tắt màn hình để vẫn nhận giá, khớp lệnh demo và đọc cảnh báo. Tốn pin hơn; nên cắm sạc. Đừng vuốt tắt app khỏi đa nhiệm.")
                }
                Section {
                    Button { VoiceAnnouncer.shared.speak(target, force: true) } label: { Label("Nghe thử: \(target)", systemImage: "play.circle") }
                    Button { VoiceAnnouncer.shared.speak(stop, force: true) } label: { Label("Nghe thử: \(stop)", systemImage: "play.circle") }
                }
            }
            .navigationTitle("Cảnh báo giọng nói")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
    }

    private func phraseRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 180)
        }
    }
}

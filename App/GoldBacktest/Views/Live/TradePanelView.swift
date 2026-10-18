import SwiftUI
import BacktestKit

/// The demo account: quick buy/sell with SL/TP, open positions, pending
/// orders and closed trades. Orders fill against the live price.
struct TradePanelView: View {
    @Environment(PaperTrader.self) private var trader
    @Environment(LiveMarket.self) private var market
    @Environment(\.dismiss) private var dismiss

    @AppStorage("trade.lots") private var lots = 0.01
    @State private var stopText = ""
    @State private var targetText = ""
    @State private var showVoiceSettings = false
    @State private var confirmReset = false
    @State private var resetBalance = 10_000.0

    private var symbol: String { market.symbolKey }
    private var price: Double { market.ticker?.lastPrice ?? market.candles.last?.close ?? 0 }
    private var decimals: Int { CandleChart.decimals(for: price) }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                orderSection
                positionsSection
                pendingSection
                historySection
                Section {
                    Button { showVoiceSettings = true } label: { Label("Cảnh báo giọng nói…", systemImage: "speaker.wave.2") }
                    Button("Làm mới tài khoản demo", role: .destructive) {
                        resetBalance = trader.account.startingBalance
                        confirmReset = true
                    }
                } footer: {
                    Text("Tài khoản demo trong app: lệnh khớp theo giá realtime đang xem (không qua sàn, không có spread/phí). Lệnh chỉ được theo dõi khi app đang chạy và đang mở đúng mã đó.")
                }
            }
            .navigationTitle("Giao dịch demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
            .sheet(isPresented: $showVoiceSettings) { VoiceSettingsView() }
            .alert("Làm mới tài khoản demo", isPresented: $confirmReset) {
                TextField("Số dư", value: $resetBalance, format: .number).keyboardType(.decimalPad)
                Button("Huỷ", role: .cancel) {}
                Button("Làm mới", role: .destructive) { trader.reset(balance: max(1, resetBalance)) }
            } message: {
                Text("Xoá mọi lệnh và lịch sử, đặt lại số dư.")
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Tài khoản") {
            LabeledContent("Số dư", value: money(trader.account.balance))
            LabeledContent("Vốn hiện tại (equity)", value: money(trader.equity))
            LabeledContent("Lãi/lỗ đang mở") {
                Text(signedMoney(trader.openProfit)).foregroundColor(trader.openProfit >= 0 ? .green : .red)
            }
            LabeledContent("Tổng lãi/lỗ") {
                let total = trader.account.balance - trader.account.startingBalance
                Text(signedMoney(total)).foregroundColor(total >= 0 ? .green : .red)
            }
        }
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
                orderButton("MUA", color: .green) {
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

    @ViewBuilder
    private var positionsSection: some View {
        if !trader.account.positions.isEmpty {
            Section("Lệnh đang mở") {
                ForEach(trader.account.positions) { position in
                    let current = trader.price(position.symbol)
                    let profit = current.map { position.profit(at: $0) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(position.side == .long ? "MUA" : "BÁN")
                                .fontWeight(.bold)
                                .foregroundColor(position.side == .long ? .green : .red)
                            Text("\(PaperTrader.lots(position.lots)) lot \(LiveView.displayName(PaperTrader.bareSymbol(position.symbol)))")
                            Spacer()
                            Text(profit.map(signedMoney) ?? "–")
                                .fontWeight(.semibold)
                                .foregroundColor((profit ?? 0) >= 0 ? .green : .red)
                        }
                        Text(levels(entry: position.entryPrice, stop: position.stop, target: position.target))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .swipeActions {
                        Button("Đóng") { trader.close(position) }.tint(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !trader.account.pending.isEmpty {
            Section("Lệnh chờ") {
                ForEach(trader.account.pending) { order in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(orderType(order)).fontWeight(.bold)
                                .foregroundColor(order.side == .long ? .green : .red)
                            Text("\(PaperTrader.lots(order.lots)) lot \(LiveView.displayName(PaperTrader.bareSymbol(order.symbol)))")
                        }
                        Text(levels(entry: order.entry, stop: order.stop, target: order.target))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .swipeActions {
                        Button("Huỷ", role: .destructive) { trader.cancel(order) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !trader.account.history.isEmpty {
            Section("Lịch sử (\(trader.account.history.count) lệnh)") {
                ForEach(trader.account.history.prefix(50)) { trade in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(trade.side == .long ? "MUA" : "BÁN") \(PaperTrader.lots(trade.lots)) \(LiveView.displayName(PaperTrader.bareSymbol(trade.symbol)))")
                            Text("\(reason(trade.reason)) · \(trade.closeTime.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(signedMoney(trade.profit))
                            .foregroundColor(trade.profit >= 0 ? .green : .red)
                    }
                }
            }
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
    @AppStorage(VoiceSettings.buyKey) private var buy = VoiceSettings.defaultBuy
    @AppStorage(VoiceSettings.sellKey) private var sell = VoiceSettings.defaultSell
    @AppStorage(VoiceSettings.signalsKey) private var signals = true
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
                Section("Tín hiệu chiến lược") {
                    Toggle("Đọc tín hiệu MUA/BÁN", isOn: $signals)
                    phraseRow("Tín hiệu MUA", text: $buy)
                    phraseRow("Tín hiệu BÁN", text: $sell)
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

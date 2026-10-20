import SwiftUI
import BacktestKit

/// Shared look of the trade pages, like broker apps: the floating profit in
/// big type, then the account figures.
struct AccountSummary: View {
    let floating: Double
    let currency: String
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 10) {
            Text(String(format: "%.2f %@", floating, currency))
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundColor(floating >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                .frame(maxWidth: .infinity)
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0)
                    Spacer()
                    Text(rows[i].1).monospacedDigit()
                }
                .font(.system(size: 16))
            }
        }
        .padding(.vertical, 6)
    }
}

/// One order in the lists: "XAUUSD buy 0.10" / "4145.150 → 4146.621" / profit.
struct OrderRow: View {
    let symbol: String
    let detail: String
    let isBuy: Bool
    let line: String
    let trailing: String
    var trailingColor: Color = .primary

    static let profitColor = Color(red: 0.16, green: 0.45, blue: 0.95)
    static let lossColor = Color(red: 0.92, green: 0.27, blue: 0.24)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(symbol).font(.system(size: 16, weight: .bold))
                    Text(detail).font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isBuy ? Self.profitColor : Self.lossColor)
                }
                Text(line).font(.system(size: 14).monospacedDigit()).foregroundColor(.secondary)
            }
            Spacer()
            Text(trailing)
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundColor(trailingColor)
        }
        .padding(.vertical, 4)
    }
}

/// "Demo" page of the Giao dịch tab: the in-app demo account, laid out like
/// a broker app (summary, open positions, pending orders, history).
struct TradePanelView: View {
    @Environment(PaperTrader.self) private var trader
    @Environment(AppStore.self) private var store

    @State private var showVoiceSettings = false
    @State private var showAutoStops = false
    @State private var confirmReset = false
    @State private var resetBalance = 10_000.0
    @State private var closing: PaperAccount.Position?

    var body: some View {
        let account = trader.account
        let closed = account.balance - account.startingBalance
        let wins = account.history.filter { $0.profit > 0 }.count
        List {
            Section {
                AccountSummary(floating: trader.openProfit, currency: "USD", rows: [
                    ("Số dư", money(account.balance)),
                    ("Vốn", money(trader.equity)),
                    ("Đã chốt", String(format: "%+.2f", closed)),
                    ("Tỉ lệ thắng", account.history.isEmpty ? "–"
                        : String(format: "%.0f%% (%d lệnh)", Double(wins) / Double(account.history.count) * 100, account.history.count)),
                ])
            }
            Section("Lệnh có trạng thái") {
                if account.positions.isEmpty { Text("Không có lệnh đang mở").foregroundColor(.secondary) }
                ForEach(account.positions) { p in
                    let profit = trader.profit(p)
                    OrderRow(symbol: name(p.symbol), detail: "\(p.side == .long ? "buy" : "sell") \(PaperTrader.lots(p.lots))",
                             isBuy: p.side == .long,
                             line: "\(price(p.entryPrice)) → \(trader.closePrice(p).map(price) ?? "–")",
                             trailing: profit.map { String(format: "%.2f", $0) } ?? "–",
                             trailingColor: (profit ?? 0) >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                        .contentShape(Rectangle())
                        .onTapGesture { closing = p }
                        .swipeActions {
                            Button("Đóng", role: .destructive) { trader.close(p) }
                        }
                }
            }
            if !account.pending.isEmpty {
                Section("Các lệnh") {
                    ForEach(account.pending) { o in
                        OrderRow(symbol: name(o.symbol), detail: orderType(o), isBuy: o.side == .long,
                                 line: "\(PaperTrader.lots(o.lots)) at \(price(o.entry))", trailing: "placed",
                                 trailingColor: Color(red: 0.1, green: 0.2, blue: 0.45))
                            .swipeActions {
                                Button("Huỷ", role: .destructive) { trader.cancel(o) }
                            }
                    }
                }
            }
            Section {
                NavigationLink {
                    TradeHistoryView(source: .demo)
                } label: {
                    Label("Lịch sử lệnh · \(account.history.count)", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("Đặt lệnh trên biểu đồ Live: thanh BÁN/MUA bên dưới, giữ để mở bảng lệnh (Limit, Stop, SL, TP). Vuốt trái một lệnh để đóng hoặc huỷ.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Giao dịch demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { store.selectedTab = .live } label: { Label("Mở biểu đồ Live", systemImage: "chart.xyaxis.line") }
                    Button { showAutoStops = true } label: { Label("SL/TP tự động & quản lý lệnh…", systemImage: "slider.horizontal.3") }
                    Button { showVoiceSettings = true } label: { Label("Thông báo & giọng nói…", systemImage: "bell") }
                    NavigationLink {
                        DatasetListView()
                    } label: {
                        Label("Dữ liệu backtest · \(store.datasets.count)", systemImage: "chart.bar.xaxis")
                    }
                    Button(role: .destructive) {
                        resetBalance = trader.account.startingBalance
                        confirmReset = true
                    } label: { Label("Làm mới tài khoản demo", systemImage: "arrow.counterclockwise") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showVoiceSettings) { VoiceSettingsView() }
        .sheet(isPresented: $showAutoStops) { AutoStopSettingsView() }
        .confirmationDialog(closing.map { "\(name($0.symbol)) \($0.side == .long ? "buy" : "sell") \(PaperTrader.lots($0.lots))" } ?? "",
                            isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
                            titleVisibility: .visible) {
            Button("Đóng lệnh", role: .destructive) {
                if let p = closing { trader.close(p) }
                closing = nil
            }
        } message: {
            if let p = closing {
                Text("Vào \(price(p.entryPrice)) · SL \(p.stop.map(price) ?? "–") · TP \(p.target.map(price) ?? "–")")
            }
        }
        .alert("Làm mới tài khoản demo", isPresented: $confirmReset) {
            TextField("Số dư", value: $resetBalance, format: .number).keyboardType(.decimalPad)
            Button("Huỷ", role: .cancel) {}
            Button("Làm mới", role: .destructive) { trader.reset(balance: max(1, resetBalance)) }
        } message: {
            Text("Xoá mọi lệnh và lịch sử, đặt lại số dư.")
        }
    }

    private func name(_ key: String) -> String { LiveView.displayName(PaperTrader.bareSymbol(key)) }
    private func price(_ value: Double) -> String { CandleChart.format(value, CandleChart.decimals(for: value)) }
    private func money(_ value: Double) -> String { String(format: "%.2f", value) }

    private func orderType(_ order: PaperAccount.PendingOrder) -> String {
        switch (order.side, order.triggersAbove) {
        case (.long, true): return "buy stop"
        case (.long, false): return "buy limit"
        case (.short, true): return "sell limit"
        case (.short, false): return "sell stop"
        }
    }
}

/// Closed demo trades.
struct DemoHistoryView: View {
    @Environment(PaperTrader.self) private var trader

    var body: some View {
        List {
            if trader.account.history.isEmpty {
                Text("Chưa có lệnh đã đóng").foregroundColor(.secondary)
            }
            ForEach(trader.account.history.prefix(300)) { t in
                VStack(alignment: .leading, spacing: 2) {
                    OrderRow(symbol: LiveView.displayName(PaperTrader.bareSymbol(t.symbol)),
                             detail: "\(t.side == .long ? "buy" : "sell") \(PaperTrader.lots(t.lots))", isBuy: t.side == .long,
                             line: "\(PaperTrader.spoken(t.entryPrice)) → \(PaperTrader.spoken(t.exitPrice)) · \(Self.reason(t.reason))",
                             trailing: String(format: "%.2f", t.profit),
                             trailingColor: t.profit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                    Text("\(t.openTime.formatted(date: .abbreviated, time: .shortened)) → \(t.closeTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Lịch sử lệnh demo")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func reason(_ reason: PaperAccount.ExitReason) -> String {
        switch reason {
        case .target: return "TP"
        case .stop: return "SL"
        case .manual: return "đóng tay"
        case .reversal: return "tự chốt"
        }
    }
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
    @AppStorage(AlertSettings.ordersKey) private var notifyOrders = true
    @AppStorage(AlertSettings.signalsKey) private var notifySignals = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Thông báo lệnh (khớp, TP/SL, đóng)", isOn: $notifyOrders)
                    Toggle("Thông báo tín hiệu chiến lược", isOn: $notifySignals)
                } header: {
                    Text("Thông báo")
                } footer: {
                    Text("Áp dụng cho demo, tài khoản Exness/MT5 và bot. Khi đăng nhập tài khoản khác, lệnh cũ của tài khoản đó không được báo lại; chỉ lệnh mới khớp mới có thông báo.")
                }
                Section("Giọng nói") {
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
            .navigationTitle("Thông báo & giọng nói")
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

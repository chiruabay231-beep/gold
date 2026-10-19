import SwiftUI
import BacktestKit

/// "Giao dịch" tab: the in-app demo account, the broker (MT5) account, and
/// logging in to brokers, each on its own page.
struct TradeRootView: View {
    @AppStorage("trade.page") private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Trang", selection: $page) {
                Text("Demo").tag(0)
                Text("Sàn (MT5)").tag(1)
                Text("Đăng nhập").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch page {
            case 0: TradePanelView()
            case 1: BrokerTradeView(page: $page)
            default: BrokerLoginView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// "Sàn" page: the MT5 account on the VPS laid out like the broker's app:
/// floating profit, balance, equity, margin, open positions, pending orders.
struct BrokerTradeView: View {
    @Binding var page: Int
    @Environment(MT5Trader.self) private var mt5
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market
    @State private var closing: MT5TradingState.Position?
    @State private var showSymbols = false

    var body: some View {
        List {
            if RemoteBotSettings.client() == nil || mt5.state?.login == nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chưa có tài khoản sàn").font(.headline)
                        Text("Đăng nhập Exness (hoặc sàn MT5 khác) qua máy chủ VPS để xem và đặt lệnh tại đây.")
                            .font(.footnote).foregroundColor(.secondary)
                        Button("Đi tới Đăng nhập") { page = 2 }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            if let state = mt5.state, state.login != nil {
                Section {
                    AccountSummary(floating: state.profit ?? state.positions.reduce(0) { $0 + $1.profit },
                                   currency: state.currency ?? "USD", rows: summaryRows(state))
                } footer: {
                    Text("#\(state.login.map { String($0) } ?? "") · \(state.server ?? "") · \(state.mode == "real" ? "TIỀN THẬT" : "demo")")
                }
                if !state.tradingEnabled {
                    Section {
                        Label("Chưa bật đặt lệnh từ app (bật ở trang Đăng nhập).", systemImage: "lock")
                            .font(.footnote).foregroundColor(.orange)
                    }
                }
                Section("Lệnh có trạng thái") {
                    if state.positions.isEmpty { Text("Không có lệnh đang mở").foregroundColor(.secondary) }
                    ForEach(state.positions) { p in
                        TradeRow(symbol: p.symbol, detail: "\(p.side == "long" ? "buy" : "sell") \(Self.lots(p.lots))",
                                 isBuy: p.side == "long",
                                 line: "\(Self.price(p.entry)) → \(p.price.map(Self.price) ?? "–")",
                                 trailing: String(format: "%.2f", p.profit),
                                 trailingColor: p.profit >= 0 ? TradeRow.profitColor : TradeRow.lossColor)
                            .contentShape(Rectangle())
                            .onTapGesture { closing = p }
                            .swipeActions {
                                Button("Đóng", role: .destructive) { closing = p }
                            }
                    }
                }
                if !state.orders.isEmpty {
                    Section("Các lệnh") {
                        ForEach(state.orders) { o in
                            TradeRow(symbol: o.symbol, detail: "\(o.side == "long" ? "buy" : "sell") \(o.kind)",
                                     isBuy: o.side == "long", line: "\(Self.lots(o.lots)) at \(Self.price(o.entry))",
                                     trailing: "placed", trailingColor: Color(red: 0.1, green: 0.2, blue: 0.45))
                                .swipeActions {
                                    Button("Huỷ", role: .destructive) { Task { await mt5.cancel(o.ticket) } }
                                }
                        }
                    }
                }
                if !state.deals.isEmpty {
                    Section("Đã đóng (24 giờ)") {
                        ForEach(state.deals.reversed()) { d in
                            TradeRow(symbol: d.symbol, detail: "\(d.side == "long" ? "buy" : "sell") \(Self.lots(d.lots))",
                                     isBuy: d.side == "long",
                                     line: "\(Self.price(d.price)) · \(d.reason == "target" ? "TP" : (d.reason == "stop" ? "SL" : "đóng")) · \(Date(timeIntervalSince1970: d.time).formatted(date: .omitted, time: .shortened))",
                                     trailing: String(format: "%.2f", d.profit),
                                     trailingColor: d.profit >= 0 ? TradeRow.profitColor : TradeRow.lossColor)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tài khoản sàn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showSymbols = true } label: { Label("Mở biểu đồ để giao dịch…", systemImage: "chart.xyaxis.line") }
                    Button { Task { await mt5.refresh() } } label: { Label("Làm mới", systemImage: "arrow.clockwise") }
                    Button { page = 2 } label: { Label("Tài khoản & quyền đặt lệnh…", systemImage: "person.badge.key") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await mt5.watch() }
        .refreshable { await mt5.refresh() }
        .sheet(isPresented: $showSymbols) {
            MT5SymbolSearchView { symbol in
                market.select(source: .mt5, symbol: symbol, interval: market.interval.isSeconds ? .m1 : nil)
                store.selectedTab = .live
            }
        }
        .confirmationDialog(closing.map { "Đóng \($0.symbol) \($0.side == "long" ? "buy" : "sell") \(Self.lots($0.lots))?" } ?? "",
                            isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
                            titleVisibility: .visible) {
            Button("Đóng lệnh", role: .destructive) {
                if let ticket = closing?.ticket { Task { await mt5.close(ticket) } }
                closing = nil
            }
        } message: {
            if let p = closing {
                Text("Vào \(Self.price(p.entry)) · SL \(p.stop.map(Self.price) ?? "–") · TP \(p.target.map(Self.price) ?? "–") · lãi/lỗ \(String(format: "%+.2f", p.profit))\(mt5.isReal ? " · TIỀN THẬT" : "")")
            }
        }
        .alert("Lệnh MT5", isPresented: Binding(get: { mt5.lastError != nil }, set: { if !$0 { mt5.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mt5.lastError ?? "")
        }
    }

    private func summaryRows(_ s: MT5TradingState) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let v = s.balance { rows.append(("Số dư", String(format: "%.2f", v))) }
        if let v = s.equity { rows.append(("Vốn", String(format: "%.2f", v))) }
        if let v = s.margin { rows.append(("Tiền ký quỹ", String(format: "%.2f", v))) }
        if let v = s.marginFree { rows.append(("Ký quỹ dư", String(format: "%.2f", v))) }
        if let v = s.marginLevel, v > 0 { rows.append(("Mức ký quỹ (%)", String(format: "%.2f", v))) }
        return rows
    }

    static func price(_ value: Double) -> String { CandleChart.format(value, CandleChart.decimals(for: value)) }
    static func lots(_ value: Double) -> String { String(format: "%g", value) }
}

/// Logs the MT5 terminal on the VPS in to Exness (or any MT5 broker) and
/// opens its symbols on the Live chart; links to the other data sources.
struct BrokerLoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market
    @Environment(MT5Trader.self) private var mt5

    enum Broker: String, CaseIterable, Identifiable {
        case exness = "Exness"
        case other = "Sàn MT5 khác"
        var id: String { rawValue }
    }

    @State private var status: MT5AccountStatus?
    @State private var statusError: String?
    @State private var busy = false
    @State private var broker = Broker.exness
    @State private var brokerName = ""
    @State private var server = ""
    @State private var login = ""
    @State private var password = ""
    @State private var rememberOnVPS = true
    @State private var saveOnPhone = true
    @State private var saved = SavedBrokerAccount.all
    @State private var showOanda = false
    @State private var confirmLogout = false
    @State private var showSymbols = false

    private var hasVPS: Bool { RemoteBotSettings.client() != nil }

    var body: some View {
        List {
            vpsSection
            if hasVPS {
                accountSection
                if status?.connected == true {
                    tradingSection
                }
                loginSection
                if !saved.isEmpty { savedSection }
            }
            otherMarketsSection
        }
        .navigationTitle("Đăng nhập sàn")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .task(id: status?.login) {
            // Positions stay fresh while this page is open.
            guard status?.connected == true else { return }
            await mt5.watch()
        }
        .alert("Lệnh MT5", isPresented: Binding(get: { mt5.lastError != nil }, set: { if !$0 { mt5.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mt5.lastError ?? "")
        }
        .refreshable { await refresh() }
        .sheet(isPresented: $showOanda) { OandaSettingsView {} }
        .sheet(isPresented: $showSymbols) {
            MT5SymbolSearchView { symbol in open(symbol) }
        }
        .confirmationDialog("Đăng xuất MT5 trên VPS?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { Task { await logout() } }
        } message: {
            Text("Mật khẩu đã lưu trên VPS sẽ bị xoá.")
        }
    }

    // MARK: - Sections

    private var vpsSection: some View {
        Section {
            if hasVPS {
                LabeledContent("Máy chủ", value: RemoteBotSettings.url)
                    .lineLimit(1)
            } else {
                Text("Đăng nhập Exness/MT5 chạy qua máy chủ bot trên VPS Windows của bạn. Hãy cài VPS và kết nối trước.")
                    .font(.footnote)
            }
            NavigationLink { RemoteBotView() } label: {
                Label(hasVPS ? "Cài đặt máy chủ VPS" : "Kết nối máy chủ VPS", systemImage: "server.rack")
            }
        } header: {
            Text("Máy chủ VPS")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if busy && status == nil {
                HStack { ProgressView(); Text("Đang kiểm tra MT5 trên VPS…").foregroundColor(.secondary) }
            } else if let status, status.connected, let number = status.login {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#\(String(number))").font(.headline.monospacedDigit())
                        Text(status.mode == "real" ? "THẬT" : (status.mode ?? "").uppercased())
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(status.mode == "real" ? Color.red.opacity(0.2) : Color.green.opacity(0.2)))
                    }
                    Text("\(status.company ?? "") · \(status.server ?? "")").font(.caption).foregroundColor(.secondary)
                    if let balance = status.balance, let equity = status.equity {
                        Text("Số dư \(String(format: "%.2f", balance)) · Equity \(String(format: "%.2f", equity)) \(status.currency ?? "")")
                            .font(.subheadline.monospacedDigit())
                    }
                }
                Button { showSymbols = true } label: {
                    Label("Mở biểu đồ realtime (chọn mã)", systemImage: "chart.xyaxis.line")
                }
                Button("Đăng xuất", role: .destructive) { confirmLogout = true }
            } else {
                Label(status?.error ?? statusError ?? "Chưa đăng nhập", systemImage: "person.crop.circle.badge.xmark")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
        } header: {
            Text("MT5 đang đăng nhập trên VPS")
        }
    }

    private var tradingSection: some View {
        let state = mt5.state
        let enabled = state?.tradingEnabled ?? false
        let allowReal = state?.allowReal ?? false
        let maxLots = state?.maxLots ?? 0.1
        return Section {
            Toggle("Cho phép đặt lệnh từ app", isOn: Binding(get: { enabled }, set: { value in
                Task { await mt5.settings(tradingEnabled: value, allowReal: allowReal, maxLots: maxLots) }
            }))
            Toggle("Cho phép tài khoản THẬT", isOn: Binding(get: { allowReal }, set: { value in
                Task { await mt5.settings(tradingEnabled: enabled, allowReal: value, maxLots: maxLots) }
            }))
            .tint(.red)
            Stepper("Tối đa \(String(format: "%.2f", maxLots)) lot mỗi lệnh", value: Binding(get: { maxLots }, set: { value in
                Task { await mt5.settings(tradingEnabled: enabled, allowReal: allowReal, maxLots: value) }
            }), in: 0.01...10, step: 0.01)
            Button { showSymbols = true } label: {
                Label("Mở biểu đồ để giao dịch", systemImage: "chart.xyaxis.line")
            }
        } header: {
            Text("Giao dịch tài khoản này từ app")
        } footer: {
            Text("Khi bật, trên biểu đồ Live của mã MT5 (nguồn \"MT5 (VPS)\"): nút BUY/SELL, lệnh limit, kéo SL/TP và ✕ đóng lệnh đều gửi thẳng vào tài khoản này, như app MT5. Tài khoản THẬT luôn hỏi xác nhận. Cần mật khẩu chính (không phải investor) và nút Algo Trading bật trong MT5 trên VPS.")
        }
    }

    private var loginSection: some View {
        Section {
            Picker("Sàn", selection: $broker) {
                ForEach(Broker.allCases) { Text($0.rawValue).tag($0) }
            }
            if broker == .other {
                TextField("Tên sàn (IC Markets, XM…)", text: $brokerName)
            }
            TextField("Máy chủ (server)", text: $server)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if broker == .exness {
                HStack {
                    ForEach(["Exness-MT5Trial", "Exness-MT5Real"], id: \.self) { prefix in
                        Button(prefix.hasSuffix("Trial") ? "Demo (Trial…)" : "Thật (Real…)") { server = prefix }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            }
            TextField("Số tài khoản (login)", text: $login)
                .keyboardType(.numberPad)
            SecureField("Mật khẩu", text: $password)
                .textContentType(.password)
            Toggle("Ghi nhớ trên VPS (tự đăng nhập lại)", isOn: $rememberOnVPS)
            Toggle("Lưu vào danh sách trên iPhone", isOn: $saveOnPhone)
            Button {
                Task { await signIn(login: login, password: password, server: server) }
            } label: {
                HStack {
                    if busy { ProgressView() }
                    Text("Đăng nhập").frame(maxWidth: .infinity)
                }
            }
            .disabled(busy || login.isEmpty || password.isEmpty || server.isEmpty)
            if let statusError {
                Text(statusError).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Đăng nhập tài khoản MT5")
        } footer: {
            Text(broker == .exness
                 ? "Lấy số tài khoản và tên server trong Exness Personal Area → Tài khoản của tôi → ⋯ → Thông tin tài khoản (ví dụ Exness-MT5Trial7). Mật khẩu investor (chỉ đọc) đủ để xem giá; bot muốn đặt lệnh cần mật khẩu chính. Mật khẩu chỉ đi qua kết nối HTTPS tới VPS của bạn."
                 : "Cần cài MT5 của chính sàn đó trên VPS và đăng nhập một lần trong MT5 để máy biết server. Tên server xem trong email mở tài khoản hoặc trang khách hàng của sàn.")
        }
    }

    private var savedSection: some View {
        Section {
            ForEach(saved) { account in
                Button {
                    if let password = account.savedPassword {
                        Task { await signIn(login: account.login, password: password, server: account.server) }
                    } else {
                        broker = account.broker == Broker.exness.rawValue ? .exness : .other
                        brokerName = account.broker
                        login = account.login
                        server = account.server
                        password = ""
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(account.login) · \(account.broker)").foregroundColor(.primary)
                            Text(account.server).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if status?.login.map { String($0) } == account.login, status?.server == account.server {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { SavedBrokerAccount.forget(saved[index]) }
                saved = SavedBrokerAccount.all
            }
        } header: {
            Text("Tài khoản đã lưu")
        } footer: {
            Text("Chạm để đăng nhập nhanh (đổi tài khoản trên VPS). Vuốt trái để xoá; mật khẩu lưu trong Keychain của iPhone này.")
        }
    }

    private var otherMarketsSection: some View {
        Section {
            HStack {
                Label("Binance (vàng XAUUSDT, crypto)", systemImage: "bitcoinsign.circle")
                Spacer()
                Text("Không cần đăng nhập").font(.caption).foregroundColor(.secondary)
            }
            Button { showOanda = true } label: {
                HStack {
                    Label("OANDA (XAU_USD, forex, chỉ số)", systemImage: "key")
                    Spacer()
                    Text(OandaSettings.hasToken ? "Đã có token" : "Nhập token").font(.caption).foregroundColor(.secondary)
                }
            }
            Text("Sàn MT5 khác (IC Markets, XM, Pepperstone, FTMO…): chọn \"Sàn MT5 khác\" ở trên. Sàn chỉ có MT4 hoặc không có MT5 thì chưa hỗ trợ.")
                .font(.footnote)
                .foregroundColor(.secondary)
        } header: {
            Text("Thị trường khác")
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard let client = RemoteBotSettings.client() else { return }
        busy = true
        defer { busy = false }
        do {
            status = try await client.mt5Status()
            statusError = nil
        } catch {
            status = nil
            statusError = error.localizedDescription
        }
    }

    private func signIn(login: String, password: String, server: String) async {
        guard let client = RemoteBotSettings.client() else { return }
        busy = true
        defer { busy = false }
        let cleanLogin = login.filter(\.isNumber)
        let cleanServer = server.trimmingCharacters(in: .whitespaces)
        do {
            status = try await client.mt5Login(login: cleanLogin, password: password, server: cleanServer,
                                               remember: rememberOnVPS)
            statusError = nil
            if saveOnPhone {
                let name = broker == .exness ? Broker.exness.rawValue : (brokerName.isEmpty ? "MT5" : brokerName)
                SavedBrokerAccount.remember(SavedBrokerAccount(broker: name, login: cleanLogin, server: cleanServer),
                                            password: password)
                saved = SavedBrokerAccount.all
            }
            self.password = ""
        } catch {
            statusError = error.localizedDescription
        }
    }

    private func logout() async {
        guard let client = RemoteBotSettings.client() else { return }
        do {
            try await client.mt5Logout()
            status = MT5AccountStatus(connected: false, error: "Đã đăng xuất")
        } catch {
            statusError = error.localizedDescription
        }
    }

    /// Opens `symbol` from the MT5 account on the Live chart and adds it to the watchlist.
    private func open(_ symbol: String) {
        var items = WatchItem.decode(UserDefaults.standard.string(forKey: "live.watchlist") ?? "")
        let item = WatchItem(source: .mt5, symbol: symbol)
        if !items.contains(item) {
            items.insert(item, at: 0)
            UserDefaults.standard.set(WatchItem.encode(items), forKey: "live.watchlist")
        }
        if market.interval.isSeconds {
            market.select(source: .mt5, symbol: symbol, interval: .m1)
        } else {
            market.select(source: .mt5, symbol: symbol)
        }
        store.selectedTab = .live
    }
}

/// Search the symbols of the MT5 account on the VPS.
struct MT5SymbolSearchView: View {
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = "XAU"
    @State private var results: [MT5Symbol] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundColor(.orange).font(.footnote)
                }
                ForEach(results) { item in
                    Button {
                        onPick(item.name)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline).foregroundColor(.primary)
                            Text(item.description.isEmpty ? item.path : item.description)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "XAU, EURUSD, US30…")
            .textInputAutocapitalization(.never)
            .navigationTitle("Mã trên MT5")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, let client = RemoteBotSettings.client() else { return }
                do {
                    results = try await client.mt5Symbols(query: query)
                    error = results.isEmpty ? "Không tìm thấy mã" : nil
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
        }
    }
}

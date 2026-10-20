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
    @State private var showCopy = false

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
                        OrderRow(symbol: p.symbol, detail: "\(p.side == "long" ? "buy" : "sell") \(Self.lots(p.lots))",
                                 isBuy: p.side == "long",
                                 line: "\(Self.price(p.entry)) → \(p.price.map(Self.price) ?? "–")",
                                 trailing: String(format: "%.2f", p.profit),
                                 trailingColor: p.profit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
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
                            OrderRow(symbol: o.symbol, detail: "\(o.side == "long" ? "buy" : "sell") \(o.kind)",
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
                            OrderRow(symbol: d.symbol, detail: "\(d.side == "long" ? "buy" : "sell") \(Self.lots(d.lots))",
                                     isBuy: d.side == "long",
                                     line: "\(Self.price(d.price)) · \(d.reason == "target" ? "TP" : (d.reason == "stop" ? "SL" : "đóng")) · \(Date(timeIntervalSince1970: d.time).formatted(date: .omitted, time: .shortened))",
                                     trailing: String(format: "%.2f", d.profit),
                                     trailingColor: d.profit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
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
                    Button { showCopy = true } label: { Label("Copy trade…", systemImage: "doc.on.doc") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await mt5.watch() }
        .refreshable { await mt5.refresh() }
        .navigationDestination(isPresented: $showCopy) { CopyTradeView() }
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

/// "Đăng nhập" page: the MT5 accounts (the one logged in on the VPS and the
/// saved ones; tap to switch), adding an account, order permissions, and the
/// VPS server at the bottom.
struct BrokerLoginView: View {
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
    @State private var server = ""
    @State private var login = ""
    @State private var password = ""
    @State private var remember = true
    @State private var saved = SavedBrokerAccount.all
    /// A saved account without a stored password, waiting for it.
    @State private var askPassword: SavedBrokerAccount?
    @State private var promptPassword = ""
    @State private var confirmLogout = false

    private var hasVPS: Bool { RemoteBotSettings.client() != nil }

    /// The account logged in on the VPS, if any.
    private var current: SavedBrokerAccount? {
        guard let status, status.connected, let number = status.login else { return nil }
        return SavedBrokerAccount(broker: status.company ?? "MT5", login: String(number), server: status.server ?? "")
    }

    /// Saved accounts with the logged-in one first (added if it isn't saved).
    private var accounts: [SavedBrokerAccount] {
        guard let current else { return saved }
        return [saved.first { $0.id == current.id } ?? current] + saved.filter { $0.id != current.id }
    }

    var body: some View {
        List {
            if hasVPS {
                accountsSection
                loginSection
                if current != nil { tradingSection }
                Section {
                    NavigationLink { CopyTradeView() } label: {
                        Label("Copy trade sang tài khoản khác", systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text("Một lệnh trên tài khoản đang dùng được mở trên nhiều tài khoản MT5 khác.")
                }
            }
            vpsSection
        }
        .navigationTitle("Đăng nhập")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .task(id: status?.login) {
            guard status?.connected == true else { return }
            await mt5.watch()
        }
        .refreshable { await refresh() }
        .alert("Đăng nhập #\(askPassword?.login ?? "")", isPresented: Binding(get: { askPassword != nil },
                                                                              set: { if !$0 { askPassword = nil } })) {
            SecureField("Mật khẩu", text: $promptPassword)
            Button("Huỷ", role: .cancel) { promptPassword = "" }
            Button("Đăng nhập") {
                if let account = askPassword {
                    let typed = promptPassword
                    Task { await signIn(login: account.login, password: typed, server: account.server, brokerName: account.broker) }
                }
                promptPassword = ""
            }
        } message: {
            Text(askPassword?.server ?? "")
        }
        .alert("Lệnh MT5", isPresented: Binding(get: { mt5.lastError != nil }, set: { if !$0 { mt5.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mt5.lastError ?? "")
        }
        .confirmationDialog("Đăng xuất MT5 trên VPS?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { Task { await logout() } }
        } message: {
            Text("Mật khẩu đã lưu trên VPS sẽ bị xoá.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountsSection: some View {
        Section {
            if busy && status == nil {
                HStack { ProgressView(); Text("Đang kiểm tra MT5 trên VPS…").foregroundColor(.secondary) }
            }
            if accounts.isEmpty, !busy {
                Text(status?.error ?? statusError ?? "Chưa có tài khoản. Thêm tài khoản ở dưới.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            ForEach(accounts) { account in
                let isCurrent = account.id == current?.id
                Button { tap(account, isCurrent: isCurrent) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(account.login) · \(account.broker)").font(.body.weight(.semibold)).foregroundColor(.primary)
                            Text(account.server).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if isCurrent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(status?.mode == "real" ? "THẬT · đang dùng" : "Demo · đang dùng")
                                    .font(.caption.bold())
                                    .foregroundColor(status?.mode == "real" ? .red : .green)
                                if let balance = status?.balance {
                                    Text(String(format: "%.2f %@", balance, status?.currency ?? ""))
                                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("Đăng nhập").font(.caption).foregroundColor(.accentColor)
                        }
                    }
                }
                .disabled(busy)
                .swipeActions {
                    if isCurrent {
                        Button("Đăng xuất", role: .destructive) { confirmLogout = true }
                    } else {
                        Button("Xoá", role: .destructive) {
                            SavedBrokerAccount.forget(account)
                            saved = SavedBrokerAccount.all
                        }
                    }
                }
            }
            if let statusError, !accounts.isEmpty {
                Text(statusError).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Tài khoản MT5")
        } footer: {
            Text("Chạm một tài khoản để đăng nhập nó trên VPS. Vuốt trái để đăng xuất hoặc xoá.")
        }
    }

    private var loginSection: some View {
        Section {
            Picker("Sàn", selection: $broker) {
                ForEach(Broker.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField(broker == .exness ? "Server, vd Exness-MT5Trial7" : "Server của sàn", text: $server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if broker == .exness {
                    Menu {
                        Button("Demo: Exness-MT5Trial…") { server = "Exness-MT5Trial" }
                        Button("Thật: Exness-MT5Real…") { server = "Exness-MT5Real" }
                    } label: {
                        Image(systemName: "list.bullet.circle")
                    }
                }
            }
            TextField("Số tài khoản", text: $login).keyboardType(.numberPad)
            SecureField("Mật khẩu", text: $password).textContentType(.password)
            Toggle("Lưu tài khoản (tự đăng nhập lại)", isOn: $remember)
            Button {
                Task { await signIn(login: login, password: password, server: server,
                                    brokerName: broker == .exness ? Broker.exness.rawValue : "MT5") }
            } label: {
                HStack {
                    if busy { ProgressView() }
                    Text("Đăng nhập").frame(maxWidth: .infinity)
                }
            }
            .disabled(busy || login.isEmpty || password.isEmpty || server.isEmpty)
        } header: {
            Text("Thêm tài khoản")
        } footer: {
            Text(broker == .exness
                 ? "Server và số tài khoản xem trong Exness Personal Area → tài khoản → Thông tin. Mật khẩu investor chỉ xem giá; đặt lệnh cần mật khẩu chính."
                 : "Cần cài MT5 của sàn đó trên VPS và đăng nhập một lần trong MT5.")
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
            Stepper("Tối đa \(String(format: "%.2f", maxLots)) lot / lệnh", value: Binding(get: { maxLots }, set: { value in
                Task { await mt5.settings(tradingEnabled: enabled, allowReal: allowReal, maxLots: value) }
            }), in: 0.01...10, step: 0.01)
        } header: {
            Text("Quyền đặt lệnh")
        } footer: {
            Text("Đặt lệnh trên biểu đồ Live của mã MT5. Tài khoản thật luôn hỏi xác nhận; cần nút Algo Trading bật trong MT5 trên VPS.")
        }
    }

    private var vpsSection: some View {
        Section {
            NavigationLink { RemoteBotView() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(hasVPS ? "Máy chủ VPS" : "Kết nối máy chủ VPS", systemImage: "server.rack")
                    if hasVPS {
                        Text(RemoteBotSettings.url).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
        } footer: {
            if !hasVPS {
                Text("Đăng nhập Exness/MT5 chạy qua máy chủ bot trên VPS Windows của bạn.")
            }
        }
    }

    // MARK: - Actions

    private func tap(_ account: SavedBrokerAccount, isCurrent: Bool) {
        guard !isCurrent else { return }
        if let password = account.savedPassword {
            Task { await signIn(login: account.login, password: password, server: account.server, brokerName: account.broker) }
        } else {
            promptPassword = ""
            askPassword = account
        }
    }

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

    private func signIn(login: String, password: String, server: String, brokerName: String) async {
        guard let client = RemoteBotSettings.client() else { return }
        busy = true
        defer { busy = false }
        let cleanLogin = login.filter(\.isNumber)
        let cleanServer = server.trimmingCharacters(in: .whitespaces)
        do {
            status = try await client.mt5Login(login: cleanLogin, password: password, server: cleanServer, remember: remember)
            statusError = nil
            if remember {
                SavedBrokerAccount.remember(SavedBrokerAccount(broker: brokerName, login: cleanLogin, server: cleanServer),
                                            password: password)
                saved = SavedBrokerAccount.all
            }
            self.password = ""
            self.login = ""
            await mt5.refresh()
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
                guard !Task.isCancelled else { return }
                guard let client = RemoteBotSettings.client() else {
                    error = "Chưa kết nối máy chủ VPS: vào Giao dịch → Đăng nhập → Máy chủ VPS."
                    return
                }
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

import SwiftUI
import BacktestKit

/// "Giao dịch" tab: copy trade, the broker (MT5) account, signals shared with
/// members, and logging in to brokers, each on its own page. The in-app demo
/// account is under the Sàn menu.
struct TradeRootView: View {
    @AppStorage("trade.page") private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Trang", selection: $page) {
                Text("Copy").tag(0)
                Text("Sàn MT5").tag(1)
                Text("Tín hiệu").tag(3)
                Text("Đăng nhập").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch page {
            case 0: CopyTradeView()
            case 1: BrokerTradeView(page: $page)
            case 3: SignalsView()
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
                    AccountSummary(floating: (state.profit ?? state.positions.reduce(0) { $0 + $1.profit })
                                       + state.positions.reduce(0) { $0 + liveProfit($1) - $1.profit },
                                   currency: state.currency ?? "USD", rows: summaryRows(state),
                                   account: (state.mode == "real", "#\(state.login.map { String($0) } ?? "") · \(state.server ?? "")"))
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
                                 line: "\(Self.price(p.entry)) → \(livePrice(p).map(Self.price) ?? "–")",
                                 trailing: String(format: "%.2f", liveProfit(p)),
                                 trailingColor: liveProfit(p) >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
                            .contentShape(Rectangle())
                            .onTapGesture { closing = p }
                            .swipeActions {
                                Button("Đóng", role: .destructive) { Task { await mt5.close(p.ticket) } }
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
                // History right under the open positions and orders, today first.
                TradeHistoryView(source: .mt5, embedded: true, reloadKey: state.deals.count)
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
                    Button { page = 0 } label: { Label("Copy trade…", systemImage: "doc.on.doc") }
                    NavigationLink {
                        TradePanelView()
                    } label: {
                        Label("Tài khoản demo trong app…", systemImage: "briefcase")
                    }
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
        .sheet(item: $closing) { p in
            ClosePositionSheet(position: p) { lots in
                Task { await mt5.close(p.ticket, lots: lots < p.lots ? lots : nil) }
            }
        }
        .alert("Lệnh MT5", isPresented: Binding(get: { mt5.lastError != nil }, set: { if !$0 { mt5.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mt5.lastError ?? "")
        }
    }

    /// A position's profit at the live price when the chart streams its symbol from MT5.
    private func liveProfit(_ p: MT5TradingState.Position) -> Double {
        guard market.source == .mt5, market.symbol == p.symbol, let q = market.quote else { return p.profit }
        return p.liveProfit(bid: q.bid, ask: q.ask)
    }

    /// The price a position closes at now: bid for a buy, ask for a sell.
    private func livePrice(_ p: MT5TradingState.Position) -> Double? {
        guard market.source == .mt5, market.symbol == p.symbol, let q = market.quote, q.bid > 0 else { return p.price }
        return p.side == "long" ? q.bid : q.ask
    }

    private func summaryRows(_ s: MT5TradingState) -> [(String, String)] {
        var rows: [(String, String)] = []
        let drift = s.positions.reduce(0) { $0 + liveProfit($1) - $1.profit }
        if let v = s.balance { rows.append(("Số dư", String(format: "%.2f", v))) }
        if let v = s.equity { rows.append(("Vốn", String(format: "%.2f", v + drift))) }
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
    /// An account tapped in the list, waiting for "Chuyển tài khoản".
    @State private var switching: SavedBrokerAccount?
    /// The add-account form; folded once there are accounts.
    @State private var showAddForm: Bool?
    /// The account being logged in, for its spinner.
    @State private var switchingLogin: String?

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
                loginSection
                accountsSection
                if current != nil { tradingSection }
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
        .confirmationDialog("Chuyển sang tài khoản #\(switching?.login ?? "")?",
                            isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
                            titleVisibility: .visible) {
            Button("Chuyển tài khoản") {
                if let account = switching { signIn(saved: account) }
                switching = nil
            }
            Button("Huỷ", role: .cancel) { switching = nil }
        } message: {
            if let account = switching {
                Text("\(account.broker) · \(account.server) · \(Self.isReal(account) ? "tài khoản thật" : "demo")"
                     + (current.map { "\nĐang dùng #\($0.login) sẽ được thay." } ?? ""))
            }
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
                let real = isCurrent ? status?.mode == "real" : Self.isReal(account)
                Button { tap(account, isCurrent: isCurrent) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(real ? AccountSummary.gold : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(account.login)").font(.system(size: 16, weight: .semibold).monospacedDigit())
                                .foregroundColor(.primary)
                            Text("\(account.broker) · \(account.server)").font(.caption).foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if isCurrent {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Đang dùng")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.green, in: Capsule())
                                if let balance = status?.balance {
                                    Text(String(format: "%.2f %@", balance, status?.currency ?? ""))
                                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                }
                            }
                        } else if busy && switchingLogin == account.login {
                            ProgressView()
                        } else {
                            Text("Chuyển").font(.subheadline).foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 2)
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
            Text("Chạm một tài khoản để chuyển. Vuốt trái để đăng xuất hoặc xoá.")
        }
    }

    private var formOpen: Bool { showAddForm ?? accounts.isEmpty }

    private var loginSection: some View {
        Section {
            Button {
                withAnimation { showAddForm = !formOpen }
            } label: {
                HStack {
                    Label("Thêm tài khoản Exness / MT5", systemImage: "person.crop.circle.badge.plus")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(formOpen ? 180 : 0))
                }
            }
            if formOpen {
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
                SecureField("Mật khẩu chính", text: $password).textContentType(.password)
                Toggle("Lưu để chuyển nhanh", isOn: $remember)
                Button {
                    Task { await signIn(login: login, password: password, server: server,
                                        brokerName: broker == .exness ? Broker.exness.rawValue : "MT5") }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView().tint(.white) }
                        Text("Đăng nhập").bold()
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || login.isEmpty || password.isEmpty || server.isEmpty)
            }
        } footer: {
            if formOpen {
                Text(broker == .exness
                     ? "Server và số tài khoản: Exness Personal Area → tài khoản → Thông tin. Đặt lệnh cần mật khẩu chính (không phải investor)."
                     : "Cần cài MT5 của sàn đó trên VPS và đăng nhập một lần trong MT5.")
            }
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
            Toggle("Cho phép tài khoản thật", isOn: Binding(get: { allowReal }, set: { value in
                Task { await mt5.settings(tradingEnabled: enabled, allowReal: value, maxLots: maxLots) }
            }))
            .tint(.red)
            Stepper("Tối đa \(String(format: "%.2f", maxLots)) lot / lệnh", value: Binding(get: { maxLots }, set: { value in
                Task { await mt5.settings(tradingEnabled: enabled, allowReal: allowReal, maxLots: value) }
            }), in: 0.01...10, step: 0.01)
        } header: {
            Text("Quyền đặt lệnh")
        } footer: {
            Text("Đặt lệnh trên biểu đồ Live của mã MT5. Algo Trading trong MT5 được tự bật lại khi đổi tài khoản.")
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
        switching = account
    }

    /// Exness puts "Real" or "Trial" in the server name.
    static func isReal(_ account: SavedBrokerAccount) -> Bool {
        let server = account.server.lowercased()
        return server.contains("real") || !(server.contains("trial") || server.contains("demo"))
    }

    private func signIn(saved account: SavedBrokerAccount) {
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
        switchingLogin = login
        defer {
            busy = false
            switchingLogin = nil
        }
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
            showAddForm = false
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

/// Tap an open position: close all of it or part of it (e.g. 0.03 of 0.10 lot).
struct ClosePositionSheet: View {
    let position: MT5TradingState.Position
    var onClose: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lots: Double

    init(position: MT5TradingState.Position, onClose: @escaping (Double) -> Void) {
        self.position = position
        self.onClose = onClose
        _lots = State(initialValue: position.lots)
    }

    private var all: Bool { lots >= position.lots - 1e-9 }

    var body: some View {
        let p = position
        let buy = p.side == "long"
        let share = p.lots > 0 ? p.profit * lots / p.lots : 0
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.symbol).font(.system(size: 22, weight: .bold).width(.condensed))
                Text("\(buy ? "buy" : "sell") \(BrokerTradeView.lots(p.lots))")
                    .foregroundColor(buy ? OrderRow.profitColor : OrderRow.lossColor)
                Spacer()
                Text(String(format: "%+.2f", p.profit))
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundColor(p.profit >= 0 ? OrderRow.profitColor : OrderRow.lossColor)
            }
            Text("Vào \(BrokerTradeView.price(p.entry)) → \(p.price.map(BrokerTradeView.price) ?? "–") · SL \(p.stop.map(BrokerTradeView.price) ?? "–") · TP \(p.target.map(BrokerTradeView.price) ?? "–")")
                .font(.footnote.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Lots to close.
            HStack(spacing: 14) {
                Button { lots = max(0.01, round2(lots - 0.01)) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                VStack(spacing: 0) {
                    Text(BrokerTradeView.lots(lots))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    Text("lot đóng").font(.caption).foregroundColor(.secondary)
                }
                .frame(minWidth: 110)
                Button { lots = min(p.lots, round2(lots + 0.01)) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                    let value = fraction == 1 ? p.lots : max(0.01, round2(p.lots * fraction))
                    Button(fraction == 1 ? "Tất cả" : "\(Int(fraction * 100))%") { lots = value }
                        .buttonStyle(.bordered)
                        .tint(abs(lots - value) < 1e-9 ? .accentColor : .gray)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("Lãi/lỗ phần đóng ≈ \(String(format: "%+.2f", share)) · còn lại \(BrokerTradeView.lots(round2(p.lots - lots))) lot")
                .font(.footnote.monospacedDigit())
                .foregroundColor(.secondary)
            Button {
                onClose(lots)
                dismiss()
            } label: {
                Text(all ? "Đóng toàn bộ \(BrokerTradeView.lots(lots)) lot" : "Đóng \(BrokerTradeView.lots(lots)) lot")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundColor(.white)
                    .background(OrderRow.lossColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }

    private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

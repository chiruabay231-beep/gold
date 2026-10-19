import SwiftUI
import BacktestKit

/// "Giao dịch" tab: the in-app demo account or logging in to brokers.
struct TradeRootView: View {
    @AppStorage("trade.page") private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Trang", selection: $page) {
                Text("Demo").tag(0)
                Text("Đăng nhập sàn").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if page == 0 {
                TradePanelView()
            } else {
                BrokerLoginView()
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Logs the MT5 terminal on the VPS in to Exness (or any MT5 broker) and
/// opens its symbols on the Live chart; links to the other data sources.
struct BrokerLoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market

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
                loginSection
                if !saved.isEmpty { savedSection }
            }
            otherMarketsSection
        }
        .navigationTitle("Đăng nhập sàn")
        .task { await refresh() }
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

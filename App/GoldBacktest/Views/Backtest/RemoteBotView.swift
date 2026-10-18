import SwiftUI
import UIKit
import BacktestKit

/// Controls the bot running 24/7 on the VPS (bot-server/bot_server.py).
struct RemoteBotView: View {
    @Environment(AppStore.self) private var store
    @State private var remote = RemoteBot()

    @State private var urlText = RemoteBotSettings.url
    @State private var passwordText = ""
    @State private var editingConnection = RemoteBotSettings.client() == nil

    @AppStorage("vps.strategy") private var strategyIDText = ""
    @AppStorage("vps.source") private var source = "binance_futures"
    @AppStorage("vps.symbol") private var symbol = "XAUUSDT"
    @AppStorage("vps.interval") private var interval = "1m"
    @AppStorage("vps.broker") private var broker = "paper"
    @AppStorage("vps.lots") private var lots = 0.01
    @AppStorage("vps.riskPercent") private var riskPercent = 0.0
    @AppStorage("vps.allowLong") private var allowLong = true
    @AppStorage("vps.allowShort") private var allowShort = true
    @AppStorage("vps.reverse") private var reverse = true

    @State private var confirmReal = false

    private struct Source: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    private static let sources = [
        Source(id: "binance_futures", title: "Binance Futures", symbol: "XAUUSDT"),
        Source(id: "binance_spot", title: "Binance Spot", symbol: "PAXGUSDT"),
        Source(id: "mt5", title: "MT5 (Exness)", symbol: "XAUUSDm"),
    ]
    private static let intervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d"]

    private var strategy: StrategyDefinition? {
        store.strategies.first { $0.id.uuidString == strategyIDText }
    }

    private var running: Bool { remote.status?.running == true }

    var body: some View {
        List {
            connectionSection
            if let status = remote.status {
                statusSection(status)
                if !running { settingsSection }
                controlSection(status)
                positionsSection(status)
                historySection
                logSection
            } else if let error = remote.error {
                Section {
                    Label(error, systemImage: "wifi.exclamationmark").foregroundColor(.orange)
                }
            }
            Section {
                NavigationLink { VPSGuideView() } label: {
                    Label("Hướng dẫn thuê và cài VPS", systemImage: "book")
                }
            }
        }
        .navigationTitle("Bot trên VPS")
        .task(id: urlText + (editingConnection ? "1" : "0")) {
            guard !editingConnection else { return }
            await remote.refreshLoop()
        }
        .refreshable { await remote.refresh() }
        .confirmationDialog("Chạy bot với lệnh THẬT trên MT5?", isPresented: $confirmReal, titleVisibility: .visible) {
            Button("Chạy với tiền thật", role: .destructive) { startBot() }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Bot sẽ tự đặt lệnh trên tài khoản MT5 \(remote.status?.account?.login.map { "\($0)" } ?? "") (\(remote.status?.account?.mode == "real" ? "TÀI KHOẢN THẬT" : "demo")), tối đa \(String(format: "%.2f", remote.status?.mt5?.maxLots ?? 0)) lot mỗi lệnh. Hãy chạy demo ít nhất vài tuần trước.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            if editingConnection {
                TextField("https://….trycloudflare.com", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(RemoteBotSettings.password == nil ? "Mật khẩu máy chủ" : "Mật khẩu (để trống = giữ nguyên)", text: $passwordText)
                Button("Lưu và kết nối") {
                    RemoteBotSettings.url = urlText
                    if !passwordText.isEmpty { RemoteBotSettings.savePassword(passwordText) }
                    passwordText = ""
                    editingConnection = false
                }
                .disabled(RemoteBotClient.normalizedURL(urlText) == nil || (passwordText.isEmpty && RemoteBotSettings.password == nil))
            } else {
                HStack {
                    Circle().fill(remote.status != nil ? Color.green : (remote.error != nil ? Color.red : Color.gray))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading) {
                        Text(remote.status != nil ? "Đã kết nối" : (remote.error != nil ? "Mất kết nối" : "Đang kết nối…"))
                        Text(urlText).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Sửa") { editingConnection = true }
                }
            }
        } header: {
            Text("Máy chủ VPS")
        } footer: {
            Text("Địa chỉ và mật khẩu hiện ra khi cài xong trên VPS; bot Telegram gửi địa chỉ mới mỗi khi VPS khởi động lại (gõ /url). Mật khẩu chỉ lưu trong Keychain của máy này — đừng gửi cho ai.")
        }
    }

    private func statusSection(_ status: RemoteStatus) -> some View {
        Section("Trạng thái") {
            HStack {
                Label(running ? "Đang chạy 24/7" : "Đang dừng", systemImage: running ? "bolt.fill" : "pause.circle")
                    .foregroundColor(running ? .green : .secondary)
                Spacer()
                if let version = status.version { Text("v\(version)").font(.caption).foregroundColor(.secondary) }
            }
            if let s = status.settings, running {
                LabeledContent("Chiến lược", value: s.strategyName.isEmpty ? "—" : s.strategyName)
                LabeledContent("Mã / khung", value: "\(s.symbol) · \(s.interval) · \(Self.sourceTitle(s.source))")
            }
            if let price = status.price {
                LabeledContent("Giá", value: BotController.format(price))
            }
            if let account = status.account {
                LabeledContent("Tài khoản", value: Self.modeTitle(account.mode) + (account.login.map { " #\($0)" } ?? ""))
                if let balance = account.balance { LabeledContent("Số dư", value: String(format: "%.2f", balance)) }
                if let equity = account.equity { LabeledContent("Equity", value: String(format: "%.2f", equity)) }
                if let error = account.error { Text(error).font(.footnote).foregroundColor(.orange) }
            }
            if let error = status.error, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundColor(.orange)
            }
            if let mt5Error = status.mt5?.error, !mt5Error.isEmpty {
                Label(mt5Error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundColor(.orange)
            }
            if status.telegram?.configured == true {
                HStack {
                    Label(status.telegram?.linked == true ? "Telegram đã liên kết" : "Nhắn bất kỳ chữ nào cho bot Telegram để liên kết",
                          systemImage: "paperplane")
                        .font(.footnote)
                    Spacer()
                    if status.telegram?.linked == true {
                        Button("Thử") { Task { await remote.testTelegram() } }.font(.footnote)
                    }
                }
            }
            if let error = remote.error {
                Text(error).font(.footnote).foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        Section {
            Picker("Chiến lược", selection: $strategyIDText) {
                Text("Chọn…").tag("")
                ForEach(store.strategies) { Text($0.name).tag($0.id.uuidString) }
            }
            Picker("Nguồn giá", selection: $source) {
                ForEach(Self.sources) { Text($0.title).tag($0.id) }
            }
            .onChange(of: source) { _, new in
                symbol = Self.sources.first { $0.id == new }?.symbol ?? symbol
                if new != "mt5" { broker = "paper" }
            }
            HStack {
                Text("Mã")
                TextField("XAUUSDT", text: $symbol)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Picker("Khung", selection: $interval) {
                ForEach(Self.intervals, id: \.self) { Text($0).tag($0) }
            }
            if source == "mt5" {
                Picker("Đặt lệnh", selection: $broker) {
                    Text("Demo trên VPS").tag("paper")
                    Text("MT5 (lệnh thật)").tag("mt5")
                }
            }
        } header: {
            Text("Chạy gì")
        } footer: {
            Text(source == "mt5"
                 ? "MT5: cần đăng nhập MT5 trên VPS (giai đoạn 2). Exness thường dùng mã XAUUSDm (tài khoản Standard) hoặc XAUUSD."
                 : "Binance Futures XAUUSDT gần sát giá vàng XAUUSD, miễn phí, chạy 24/7. Lệnh vào tài khoản demo trên VPS.")
        }

        Section {
            Stepper("Khối lượng \(String(format: "%.2f", lots)) lot", value: $lots, in: 0.01...100, step: 0.01)
            Stepper(riskPercent > 0 ? "Rủi ro \(String(format: "%.1f", riskPercent))% / lệnh" : "Rủi ro theo %: tắt",
                    value: $riskPercent, in: 0...10, step: 0.5)
            Toggle("Cho phép MUA", isOn: $allowLong)
            Toggle("Cho phép BÁN", isOn: $allowShort)
            Toggle("Đảo lệnh khi có tín hiệu ngược", isOn: $reverse)
        } header: {
            Text("Lệnh")
        } footer: {
            Text("Rủi ro theo % (cần chiến lược có SL) thay cho khối lượng cố định. Dời SL và tự chốt khi đảo chiều dùng cài đặt của app (Live → Limit → ⚙︎).")
        }
    }

    private func controlSection(_ status: RemoteStatus) -> some View {
        Section {
            if running {
                Button(role: .destructive) { Task { await remote.stop() } } label: {
                    Label("Dừng bot trên VPS", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    if broker == "mt5" { confirmReal = true } else { startBot() }
                } label: {
                    Label(broker == "mt5" ? "Chạy bot (lệnh MT5)" : "Chạy bot 24/7 (demo)", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(strategy == nil || symbol.isEmpty)
            }
        } footer: {
            Text(running
                 ? "Bot vẫn chạy khi tắt app hay tắt điện thoại. Dừng bot không đóng lệnh đang mở; lệnh vẫn có SL/TP."
                 : "Gửi code chiến lược, chỉ báo tự viết và cài đặt Backtest lên VPS.")
        }
        .disabled(remote.isBusy)
    }

    @ViewBuilder
    private func positionsSection(_ status: RemoteStatus) -> some View {
        let positions = status.positions ?? []
        Section("Lệnh đang mở trên VPS") {
            if positions.isEmpty {
                Text("Không có lệnh").foregroundColor(.secondary)
            }
            ForEach(positions) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(p.isLong ? "MUA" : "BÁN") \(String(format: "%.2f", p.lots)) \(p.symbol)")
                            .foregroundColor(p.isLong ? .blue : .red)
                        Text("@ \(BotController.format(p.entryPrice)) · SL \(p.stop.map { BotController.format($0) } ?? "—") · TP \(p.target.map { BotController.format($0) } ?? "—")")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let profit = p.profit {
                        Text(String(format: "%+.2f", profit))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(profit >= 0 ? .green : .red)
                    }
                    Button { Task { await remote.close(p) } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            if positions.count > 1 {
                Button("Đóng tất cả", role: .destructive) { Task { await remote.close(nil) } }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !remote.history.isEmpty {
            Section("Lệnh đã đóng") {
                ForEach(remote.history.prefix(20), id: \.uniqueID) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(t.side == "long" ? "MUA" : "BÁN") \(t.symbol) · \(Self.reasonTitle(t.reason))")
                                .font(.subheadline)
                            if let time = t.exitTime {
                                Text(Date(timeIntervalSince1970: time).formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(String(format: "%+.2f", t.profit ?? 0))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor((t.profit ?? 0) >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private var logSection: some View {
        Section("Nhật ký VPS") {
            if remote.log.isEmpty { Text("Chưa có hoạt động").foregroundColor(.secondary) }
            ForEach(remote.log.prefix(40)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text).font(.footnote.monospacedDigit())
                    Text(Date(timeIntervalSince1970: entry.time).formatted(date: .omitted, time: .standard))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func startBot() {
        guard let strategy else { return }
        let request = RemoteStartRequest(
            source: source, symbol: symbol.trimmingCharacters(in: .whitespaces),
            interval: interval, broker: source == "mt5" ? broker : "paper",
            strategy: strategy, strategyName: strategy.name, indicators: store.indicators, config: store.config,
            lots: lots, riskPercent: riskPercent, allowLong: allowLong, allowShort: allowShort, reverse: reverse,
            rules: PaperTrader.rules)
        Task { await remote.start(request) }
    }

    // MARK: - Labels

    static func sourceTitle(_ id: String) -> String {
        sources.first { $0.id == id }?.title ?? (id == "sample" ? "Giả lập" : id)
    }

    static func modeTitle(_ mode: String?) -> String {
        switch mode {
        case "paper": return "Demo trên VPS"
        case "demo": return "MT5 demo"
        case "real": return "MT5 THẬT"
        case "contest": return "MT5 contest"
        default: return mode ?? "—"
        }
    }

    static func reasonTitle(_ reason: String?) -> String {
        switch reason {
        case "target": return "TP"
        case "stop": return "SL"
        case "reversal": return "đảo chiều"
        default: return "đóng"
        }
    }
}

/// Short in-app version of docs/VPS.md.
struct VPSGuideView: View {
    var body: some View {
        List {
            Section("1. Thuê VPS Windows") {
                Text("Chọn VPS Windows Server 2022, 2 GB RAM trở lên (ví dụ Contabo, Vultr, Kamatera hoặc nhà cung cấp Việt Nam). Gần Exness nhất là vị trí London hoặc Amsterdam.")
                Text("Nhà cung cấp gửi IP, tên đăng nhập (Administrator) và mật khẩu VPS. Đừng gửi mật khẩu VPS vào chat với ai.")
            }
            Section("2. Vào VPS từ iPhone / Mac") {
                Text("Cài app Windows App (Microsoft Remote Desktop) từ App Store → + → Add PC → nhập IP → đăng nhập.")
            }
            Section("3. Cài bot (1 lệnh)") {
                Text("Trên VPS: chuột phải Start → Terminal (Admin) hoặc Windows PowerShell (Admin), dán lệnh:")
                Text(Self.installCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("Sao chép lệnh cài") { UIPasteboard.general.string = Self.installCommand }
                Text("Khi được hỏi, dán token Telegram bot (tuỳ chọn). Cuối cùng màn hình hiện Địa chỉ máy chủ và Mật khẩu máy chủ.")
            }
            Section("4. Telegram (khuyên dùng)") {
                Text("Trong Telegram tìm @BotFather → /newbot → đặt tên → nhận token. Sau khi cài, nhắn bất kỳ chữ nào cho bot của bạn để liên kết. Bot báo mọi lệnh và gửi địa chỉ máy chủ mới; lệnh /status /url /stop /start /close.")
            }
            Section("5. Kết nối app") {
                Text("Nhập địa chỉ và mật khẩu ở mục Máy chủ VPS phía trên, chọn chiến lược → Chạy bot 24/7. Giờ có thể tắt app, tắt điện thoại; bot vẫn chạy trên VPS.")
            }
            Section("6. Giai đoạn 2: Exness MT5") {
                Text("Trên VPS cài MT5 của Exness, đăng nhập tài khoản. Sửa C:\\GoldBot\\config.json mục mt5 (login, server; mật khẩu investor nếu chỉ lấy giá). Muốn bot đặt lệnh: dùng mật khẩu chính và trading_enabled = true; tài khoản thật còn cần allow_real_account = true. max_lots giới hạn khối lượng mỗi lệnh.")
                Text("Chạy lại lệnh cài với -Mt5 (xem docs/VPS.md) để bot chạy trong phiên đăng nhập. Khi thoát Windows App chỉ đóng cửa sổ (Disconnect), KHÔNG Sign out, để MT5 tiếp tục chạy.")
            }
        }
        .navigationTitle("Hướng dẫn VPS")
    }

    static let installCommand = "irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1 | iex"
}

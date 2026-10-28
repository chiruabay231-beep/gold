import SwiftUI
import UIKit
import BacktestKit

// The chart's f(x) and ••• lists are sheets: a Menu rebuilt on every price
// tick jumps and cuts its rows while it is being scrolled.

/// Layers on the Live chart: ICT, the user's indicators and the built-in ones.
struct LiveIndicatorSheet: View {
    var onKillzoneSettings: () -> Void
    var onManage: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(MemberFeed.self) private var memberFeed
    @Environment(\.dismiss) private var dismiss
    @AppStorage("live.killzonePivots.on") private var showKillzonePivots = true
    @AppStorage(LiveIndicators.storageKey) private var liveIndicatorIDs = ""
    @AppStorage("live.showEMA200") private var showEMA200 = true
    @AppStorage(LiveIndicators.sharkKey) private var showSharkFlow = false
    @AppStorage(LiveIndicators.sharkMultipleKey) private var sharkMultiple = 2.5
    @AppStorage(LiveIndicators.sharkZonesKey) private var sharkZones = true
    @AppStorage("live.volume") private var showVolume = true
    @AppStorage("live.highLow") private var showHighLow = true

    var body: some View {
        NavigationStack {
            List {
                if memberFeed.allows(.killzones) {
                    Section("ICT") {
                        Toggle(LiveView.killzonePivotsName, isOn: $showKillzonePivots)
                        Button {
                            onKillzoneSettings()
                            dismiss()
                        } label: {
                            Label("Cài đặt Killzones + Pivots…", systemImage: "gearshape")
                        }
                    }
                }
                if memberFeed.allows(.indicators) {
                    Section("Chỉ báo của bạn (tab Chỉ báo)") {
                        ForEach(store.indicators) { indicator in
                            Toggle(indicator.title, isOn: Binding(
                                get: { LiveIndicators.ids(liveIndicatorIDs).contains(indicator.id) },
                                set: { _ in liveIndicatorIDs = LiveIndicators.toggled(indicator.id, in: liveIndicatorIDs) }))
                        }
                        Button {
                            onManage()
                            dismiss()
                        } label: {
                            Label(store.indicators.isEmpty ? "Viết chỉ báo mới…" : "Quản lý / sửa chỉ báo…", systemImage: "square.and.pencil")
                        }
                    }
                }
                if memberFeed.allows(.sharkflow) {
                    Section {
                        Toggle("🦈 Dòng tiền cá mập", isOn: $showSharkFlow)
                        if showSharkFlow {
                            Picker("Cá mập khi khối lượng ≥", selection: $sharkMultiple) {
                                Text("2 × trung bình").tag(2.0)
                                Text("2.5 × trung bình").tag(2.5)
                                Text("3 × trung bình").tag(3.0)
                                Text("4 × trung bình").tag(4.0)
                            }
                            Toggle("Vùng cung / cầu cá mập (ghi giá)", isOn: $sharkZones)
                        }
                    } header: {
                        Text("Dòng tiền")
                    } footer: {
                        Text("Hai dòng chữ trên biểu đồ: dòng tiền đang vào hay ra, và ý nghĩa — giá tăng + tiền vào = tăng khoẻ; ⚠️ giá tăng nhưng tiền ra = tăng yếu, dễ đảo chiều; giá giảm + tiền ra = giảm khoẻ; ⚠️ giá giảm nhưng tiền vào = có người gom, dễ bật lên. Bong bóng 🦈 trên nến = khối lượng lớn bất thường: xanh dưới nến là cá mập MUA, đỏ trên nến là cá mập BÁN. Vùng CẦU (xanh, dưới giá) = nơi cá mập đã mua nhiều nhất, hay chờ mua lại khi giá về; vùng CUNG (đỏ, trên giá) = nơi đã bán nhiều nhất, hay chờ bán; % là độ mạnh. Sàn forex/CFD (Exness) không có khối lượng thật và không lộ lệnh chờ, nên đây là ước lượng từ khối lượng tick.")
                    }
                }
                Section("Khác") {
                    Toggle("EMA 200", isOn: $showEMA200)
                    Toggle("Khối lượng", isOn: $showVolume)
                    Toggle("Nhãn Cao / Thấp", isOn: $showHighLow)
                }
            }
            .navigationTitle("Chỉ báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The ••• menu: Cài đặt (look, trading buttons, notifications) and chart actions.
struct LiveMoreSheet: View {
    var onSettings: () -> Void
    var onDemo: () -> Void
    var onAutoFit: () -> Void
    var onClearDrawings: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Cài đặt", "gearshape", onSettings)
                } footer: {
                    Text("Giao diện sáng/tối, màu nền biểu đồ, màu nến, nút BUY/SELL, thông báo.")
                }
                Section("Biểu đồ") {
                    row("Tự động căn thang giá", "arrow.up.and.down", onAutoFit)
                    row("Giao dịch demo…", "briefcase", onDemo)
                    Button(role: .destructive) {
                        onClearDrawings()
                        dismiss()
                    } label: {
                        Label("Xoá tất cả hình vẽ", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Biểu đồ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ systemImage: String, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

/// Play / pause for the bot, next to BUY/SELL: the bot of this app while it
/// has been started, otherwise the VPS bot or the VPS Stop bot (also the one
/// started from the website) once it has been set up.
struct LiveBotControl: View {
    let theme: ChartTheme
    var height: CGFloat = 70

    @Environment(AppStore.self) private var store
    @Environment(BotController.self) private var bot
    @Environment(StopBotController.self) private var stopBot
    @Environment(MT5Trader.self) private var mt5
    @State private var confirmRealStop = false
    @State private var remote = RemoteBot()
    @State private var confirmResume = false
    @State private var confirmVpsStop = false
    /// Why the last tap on the VPS bot failed.
    @State private var actionError: String?

    private enum Target { case app, stop, vps, vpsStop }

    private var target: Target? {
        let vps = remote.status
        let vpsHasStrategy = !(vps?.settings?.strategyName ?? "").isEmpty
        let vpsStop = remote.stopBot
        if bot.isRunning { return .app }
        if stopBot.isRunning { return .stop }
        if vps?.running == true { return .vps }
        if vpsStop?.isRunning == true { return .vpsStop }
        if bot.hasSession, bot.strategyID != nil { return .app }
        if stopBot.hasSession { return .stop }
        if vpsHasStrategy { return .vps }
        if vpsStop?.isConfigured == true { return .vpsStop }
        return nil
    }

    private var running: Bool {
        switch target {
        case .app: return bot.isRunning
        case .stop: return stopBot.isRunning
        case .vps: return remote.status?.running == true
        case .vpsStop: return remote.stopBot?.isRunning == true
        case nil: return false
        }
    }

    private func title(_ target: Target) -> (String, String) {
        switch target {
        case .app: return ("BOT", "app")
        case .stop: return ("STOP", "app")
        case .vps: return ("BOT", "VPS")
        case .vpsStop: return ("STOP", "VPS")
        }
    }

    var body: some View {
        Group {
            if let target {
                Button { tap(target) } label: {
                    let (name, place) = title(target)
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(running ? Color.white.opacity(0.22) : theme.accent.opacity(0.12))
                                .frame(width: 30, height: 30)
                            if remote.isBusy {
                                ProgressView().scaleEffect(0.7).tint(running ? .white : theme.accent)
                            } else {
                                Image(systemName: running ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        VStack(spacing: 0) {
                            Text(name).font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            Text(running ? "đang chạy" : place)
                                .font(.system(size: 8.5, weight: .semibold))
                                .opacity(0.8)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .frame(width: 52, height: height)
                    .foregroundColor(running ? .white : theme.accent)
                    .background {
                        if running {
                            LinearGradient(colors: [theme.up, theme.up.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        } else {
                            theme.accent.opacity(theme.isLight ? 0.06 : 0.10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(running ? theme.up.opacity(0.9) : theme.accent.opacity(0.35), lineWidth: 1))
                    .shadow(color: (running ? theme.up : Color.black).opacity(running ? 0.30 : 0.08), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(remote.isBusy)
                .accessibilityLabel(running ? "Tạm dừng bot" : "Chạy bot")
            }
        }
        .task {
            // The VPS bots can be started from Telegram, the website or the Bot tab: keep their state fresh.
            while !Task.isCancelled {
                await remote.refreshStatus()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .confirmationDialog("Bot Stop đặt lệnh TIỀN THẬT?", isPresented: $confirmRealStop, titleVisibility: .visible) {
            Button("Chạy bot trên tài khoản thật", role: .destructive) { stopBot.start() }
        } message: {
            Text("Mỗi nến đóng bot đặt Buy Stop / Sell Stop \(PaperTrader.lots(stopBot.config.lots)) lot vào tài khoản MT5 #\(mt5.state?.login.map { String($0) } ?? "").")
        }
        .confirmationDialog("Chạy lại bot trên VPS?", isPresented: $confirmResume, titleVisibility: .visible) {
            Button("Chạy bot") { Task { await remote.resume(); actionError = remote.error } }
        } message: {
            Text(resumeMessage)
        }
        .confirmationDialog("Chạy lại bot Stop trên VPS?", isPresented: $confirmVpsStop, titleVisibility: .visible) {
            Button("Chạy bot Stop") { Task { await remote.setStopBot(running: true); actionError = remote.error } }
        } message: {
            Text(vpsStopMessage)
        }
        .alert("Bot trên VPS", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var resumeMessage: String {
        guard let s = remote.status?.settings else { return "" }
        let orders = s.broker == "mt5" ? "lệnh vào tài khoản MT5" : "tài khoản demo trên VPS"
        return "\(s.strategyName) · \(s.symbol) \(s.interval) · \(orders)"
    }

    private var vpsStopMessage: String {
        guard let c = remote.stopBot?.config else { return "" }
        return "\(c.symbol ?? "") \(c.interval ?? "") · \(PaperTrader.lots(c.lots ?? 0.01)) lot · Buy Stop / Sell Stop quanh mỗi nến đóng, lệnh vào tài khoản MT5"
    }

    private func tap(_ target: Target) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch target {
        case .app:
            if bot.isRunning {
                bot.stop()
            } else if let name = store.strategies.first(where: { $0.id == bot.strategyID })?.name {
                bot.start(strategyName: name)
            }
        case .stop:
            if stopBot.isRunning {
                stopBot.stop()
            } else if stopBot.plannedDestination == .mt5, mt5.isReal {
                confirmRealStop = true
            } else {
                stopBot.start()
            }
        case .vps:
            if remote.status?.running == true {
                Task { await remote.stop(); actionError = remote.error }
            } else {
                confirmResume = true
            }
        case .vpsStop:
            if remote.stopBot?.isRunning == true {
                Task { await remote.setStopBot(running: false); actionError = remote.error }
            } else {
                confirmVpsStop = true
            }
        }
    }
}

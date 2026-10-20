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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("live.killzonePivots.on") private var showKillzonePivots = true
    @AppStorage(LiveIndicators.storageKey) private var liveIndicatorIDs = ""
    @AppStorage("live.showEMA200") private var showEMA200 = true
    @AppStorage("live.volume") private var showVolume = true
    @AppStorage("live.highLow") private var showHighLow = true

    var body: some View {
        NavigationStack {
            List {
                Section("ICT") {
                    Toggle(LiveView.killzonePivotsName, isOn: $showKillzonePivots)
                    Button {
                        onKillzoneSettings()
                        dismiss()
                    } label: {
                        Label("Cài đặt Killzones + Pivots…", systemImage: "gearshape")
                    }
                }
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

/// Chart look, notifications and chart actions.
struct LiveMoreSheet: View {
    var onChartSettings: () -> Void
    var onVoiceSettings: () -> Void
    var onDemo: () -> Void
    var onAutoFit: () -> Void
    var onClearDrawings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("live.theme") private var themeName = "tradingView"
    @AppStorage("live.candleStyle") private var candleStyle = CandleStyle.candles.rawValue
    @AppStorage(AlertSettings.ordersKey) private var notifyOrders = true
    @AppStorage(AlertSettings.signalsKey) private var notifySignals = true
    @AppStorage(VoiceSettings.enabledKey) private var voice = true

    var body: some View {
        NavigationStack {
            List {
                Section("Thông báo") {
                    Toggle(isOn: $notifyOrders) { Label("Thông báo lệnh", systemImage: "bell.badge") }
                    Toggle(isOn: $notifySignals) { Label("Thông báo tín hiệu", systemImage: "waveform.path.ecg") }
                    Toggle(isOn: $voice) { Label("Đọc bằng giọng nói", systemImage: "speaker.wave.2") }
                    row("Cài đặt thông báo & giọng nói…", "slider.horizontal.3", onVoiceSettings)
                }
                Section("Biểu đồ") {
                    Picker("Giao diện", selection: $themeName) {
                        Text("TradingView (sáng)").tag("tradingView")
                        Text("Binance (tối)").tag("binance")
                    }
                    Picker("Kiểu nến", selection: $candleStyle) {
                        ForEach(CandleStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    row("Tự động căn thang giá", "arrow.up.and.down", onAutoFit)
                    row("Cài đặt biểu đồ (màu nến…)", "gearshape", onChartSettings)
                }
                Section {
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
/// has been started, otherwise the VPS bot once it has a strategy.
struct LiveBotControl: View {
    let theme: ChartTheme
    var height: CGFloat = 66

    @Environment(AppStore.self) private var store
    @Environment(BotController.self) private var bot
    @State private var remote = RemoteBot()
    @State private var confirmResume = false
    /// Why the last tap on the VPS bot failed.
    @State private var actionError: String?

    private enum Target { case app, vps }

    private var target: Target? {
        let vps = remote.status
        let vpsHasStrategy = !(vps?.settings?.strategyName ?? "").isEmpty
        if bot.isRunning { return .app }
        if vps?.running == true { return .vps }
        if bot.hasSession, bot.strategyID != nil { return .app }
        if vpsHasStrategy { return .vps }
        return nil
    }

    private var running: Bool {
        switch target {
        case .app: return bot.isRunning
        case .vps: return remote.status?.running == true
        case nil: return false
        }
    }

    var body: some View {
        Group {
            if let target {
                Button { tap(target) } label: {
                    VStack(spacing: 3) {
                        if remote.isBusy {
                            ProgressView().tint(running ? .white : theme.accent)
                        } else {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                        }
                        Text(target == .vps ? "VPS" : "Bot")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .frame(width: 48, height: height)
                    .foregroundColor(running ? .white : theme.accent)
                    .background(RoundedRectangle(cornerRadius: 10).fill(running ? theme.up : theme.accent.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(running ? theme.up : theme.accent.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(remote.isBusy)
                .accessibilityLabel(running ? "Tạm dừng bot" : "Chạy bot")
            }
        }
        .task {
            // The VPS bot can be started from Telegram or the Bot tab: keep its state fresh.
            while !Task.isCancelled {
                await remote.refreshStatus()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .confirmationDialog("Chạy lại bot trên VPS?", isPresented: $confirmResume, titleVisibility: .visible) {
            Button("Chạy bot") { Task { await remote.resume(); actionError = remote.error } }
        } message: {
            Text(resumeMessage)
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

    private func tap(_ target: Target) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch target {
        case .app:
            if bot.isRunning {
                bot.stop()
            } else if let name = store.strategies.first(where: { $0.id == bot.strategyID })?.name {
                bot.start(strategyName: name)
            }
        case .vps:
            if remote.status?.running == true {
                Task { await remote.stop(); actionError = remote.error }
            } else {
                confirmResume = true
            }
        }
    }
}

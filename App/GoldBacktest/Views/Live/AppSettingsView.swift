import SwiftUI

/// "Cài đặt": the look of the app and chart, trading buttons, notifications —
/// what used to be spread over the ••• menu, in one place.
struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("live.theme") private var themeName = "tradingView"
    @AppStorage(ChartBackground.key) private var backgroundJSON = ""
    @AppStorage("live.candleStyle") private var candleStyle = CandleStyle.candles.rawValue
    @AppStorage("live.candleColors") private var candleColorsJSON = ""
    @AppStorage("live.precision") private var precision = -1
    @AppStorage("live.timeZone") private var timeZoneID = ""
    @AppStorage("position.balance") private var accountBalance = 0.0
    @AppStorage("position.riskPercent") private var riskPercent = 1.0
    @AppStorage("position.contractSize") private var contractSize = 100.0
    @AppStorage("live.volume") private var showVolume = true
    @AppStorage("live.highLow") private var showHighLow = true
    @AppStorage("live.showTradeButtons") private var showTradeButtons = true
    @AppStorage("live.tradeBarPosition") private var tradeBarPosition = "bottom"
    @AppStorage(AlertSettings.ordersKey) private var notifyOrders = true
    @AppStorage(AlertSettings.signalsKey) private var notifySignals = true
    @AppStorage(VoiceSettings.enabledKey) private var voice = true
    @AppStorage(VoiceSettings.keepAwakeKey) private var keepAwake = false

    @State private var showCandles = false
    @State private var showVoice = false
    @State private var showAutoStops = false

    private var dark: Bool { themeName == "binance" }
    private var theme: ChartTheme {
        (dark ? ChartTheme.binance : .tradingView).with(background: ChartBackground.decode(backgroundJSON))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Giao diện", selection: Binding(get: { themeName }, set: { name in
                        themeName = name
                        // A background made for the other theme would hide the candles.
                        backgroundJSON = ""
                    })) {
                        Label("Sáng", systemImage: "sun.max").tag("tradingView")
                        Label("Tối", systemImage: "moon").tag("binance")
                    }
                    .pickerStyle(.segmented)
                    ColorPicker("Màu nền biểu đồ", selection: Binding(
                        get: { theme.background },
                        set: { backgroundJSON = ChartBackground.encode($0) }), supportsOpacity: false)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ChartBackground.presets.filter { $0.2 == !dark }, id: \.0) { preset in
                                Button { backgroundJSON = ChartBackground.encode(preset.1) } label: {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(preset.1)
                                            .frame(width: 44, height: 30)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                                        Text(preset.0).font(.caption2).foregroundColor(.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Button { backgroundJSON = "" } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .frame(width: 44, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                                    Text("Mặc định").font(.caption2).foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    preview
                } header: {
                    Text("Giao diện")
                }

                Section("Nến & biểu đồ") {
                    Picker("Kiểu nến", selection: $candleStyle) {
                        ForEach(CandleStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button { showCandles = true } label: {
                        Label("Màu nến, độ chính xác, múi giờ…", systemImage: "paintpalette")
                    }
                    Toggle("Khối lượng", isOn: $showVolume)
                    Toggle("Nhãn Cao / Thấp", isOn: $showHighLow)
                }

                Section("Giao dịch") {
                    Toggle("Hiện nút BUY/SELL", isOn: $showTradeButtons)
                    Picker("Vị trí nút BUY/SELL", selection: $tradeBarPosition) {
                        Text("Dưới biểu đồ").tag("bottom")
                        Text("Trên biểu đồ").tag("top")
                    }
                    Button { showAutoStops = true } label: {
                        Label("SL/TP tự động & quản lý lệnh…", systemImage: "slider.horizontal.3")
                    }
                }

                Section("Thông báo") {
                    Toggle(isOn: $notifyOrders) { Label("Thông báo lệnh", systemImage: "bell.badge") }
                    Toggle(isOn: $notifySignals) { Label("Thông báo tín hiệu", systemImage: "waveform.path.ecg") }
                    Toggle(isOn: $voice) { Label("Đọc bằng giọng nói", systemImage: "speaker.wave.2") }
                    Toggle(isOn: $keepAwake) { Label("Giữ màn hình luôn sáng", systemImage: "sun.max") }
                    Button { showVoice = true } label: {
                        Label("Cài đặt thông báo & giọng nói…", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
            .sheet(isPresented: $showCandles) {
                ChartSettingsView(theme: theme, colorsJSON: $candleColorsJSON, candleStyle: $candleStyle,
                                  precision: $precision, timeZoneID: $timeZoneID, balance: $accountBalance,
                                  riskPercent: $riskPercent, contractSize: $contractSize)
            }
            .sheet(isPresented: $showVoice) { VoiceSettingsView() }
            .sheet(isPresented: $showAutoStops) { AutoStopSettingsView() }
        }
    }

    /// A few candles on the chosen background.
    private var preview: some View {
        let colors = CandleColors.decode(candleColorsJSON) ?? .standard(for: theme)
        let bars: [(Double, Double, Double, Double)] = [(0.3, 0.8, 0.2, 0.7), (0.7, 0.9, 0.5, 0.6), (0.6, 0.65, 0.3, 0.35),
                                                        (0.35, 0.6, 0.25, 0.55), (0.55, 0.95, 0.5, 0.9), (0.9, 0.95, 0.6, 0.65)]
        return Canvas { context, size in
            let width = size.width / CGFloat(bars.count)
            func y(_ v: Double) -> CGFloat { size.height * (1 - CGFloat(v)) }
            for (i, bar) in bars.enumerated() {
                let up = bar.3 >= bar.0
                let x = width * (CGFloat(i) + 0.5)
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(bar.1)))
                wick.addLine(to: CGPoint(x: x, y: y(bar.2)))
                context.stroke(wick, with: .color((up ? colors.upWick : colors.downWick).color), lineWidth: 1)
                let top = y(max(bar.0, bar.3)), bottom = y(min(bar.0, bar.3))
                context.fill(Path(CGRect(x: x - width * 0.25, y: top, width: width * 0.5, height: max(bottom - top, 1))),
                             with: .color((up ? colors.upBody : colors.downBody).color))
            }
        }
        .frame(height: 70)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.background))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
    }
}

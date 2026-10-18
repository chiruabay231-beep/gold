import SwiftUI

/// Chart settings laid out like TradingView's "Mã" (Symbol) page: candle
/// body / border / wick colours, data precision and time zone.
struct ChartSettingsView: View {
    let theme: ChartTheme
    @Binding var colorsJSON: String
    @Binding var candleStyle: String
    @Binding var precision: Int
    @Binding var timeZoneID: String
    @Binding var balance: Double
    @Binding var riskPercent: Double
    @Binding var contractSize: Double

    @Environment(\.dismiss) private var dismiss
    @State private var colors = CandleColors.standard(for: .tradingView)
    @State private var style = CandleStyle.candles
    @State private var decimals = -1
    @State private var zone = ""
    @State private var accountBalance = 0.0
    @State private var risk = 1.0
    @State private var contract = 100.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Biểu đồ nến") {
                    Picker("Kiểu", selection: $style) {
                        ForEach(CandleStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Các thanh màu dựa trên đóng cửa phiên trước", isOn: $colors.colorByPreviousClose)
                    colorRow("Thân", isOn: $colors.showBody, up: $colors.upBody, down: $colors.downBody)
                    colorRow("Đường viền", isOn: $colors.showBorder, up: $colors.upBorder, down: $colors.downBorder)
                    colorRow("Bóng nến", isOn: $colors.showWick, up: $colors.upWick, down: $colors.downWick)
                    preview
                }

                Section("Mẫu màu nhanh") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            preset("TradingView", up: Color(red: 0.031, green: 0.6, blue: 0.506),
                                   down: Color(red: 0.949, green: 0.212, blue: 0.271), wick: nil)
                            preset("Binance", up: BinanceTheme.up, down: BinanceTheme.down, wick: nil)
                            preset("Xanh / Đen", up: Color(red: 0.031, green: 0.6, blue: 0.506), down: .black, wick: .black)
                            preset("Trắng / Đen", up: .white, down: .black, wick: .black)
                            preset("Xanh dương / Đỏ", up: Color(red: 0.161, green: 0.384, blue: 1.0),
                                   down: Color(red: 0.949, green: 0.212, blue: 0.271), wick: nil)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Điều chỉnh dữ liệu") {
                    Picker("Độ chính xác", selection: $decimals) {
                        Text("Mặc định").tag(-1)
                        ForEach(0...5, id: \.self) { d in
                            Text(d == 0 ? "1" : "0." + String(repeating: "0", count: d - 1) + "1").tag(d)
                        }
                    }
                    Picker("Múi giờ", selection: $zone) {
                        ForEach(ChartTimeZones.options, id: \.id) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }

                Section {
                    numberRow("Vốn tài khoản ($)", value: $accountBalance)
                    numberRow("Rủi ro mỗi lệnh (%)", value: $risk)
                    numberRow("Hợp đồng / 1 lot", value: $contract)
                } header: {
                    Text("Vị thế Long / Short")
                } footer: {
                    Text("Dùng để tính số lot trên công cụ Vị thế. XAUUSD: 1 lot = 100 oz. Forex: 100 000. Để vốn = 0 để ẩn.")
                }
            }
            .navigationTitle("Cài đặt biểu đồ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy bỏ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ok") { save() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        Button("Đặt lại màu mặc định", role: .destructive) {
                            colors = CandleColors.standard(for: theme)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private var preview: some View {
        HStack(spacing: 14) {
            Spacer()
            ForEach(Array([true, false, true, true, false].enumerated()), id: \.offset) { _, up in
                candlePreview(up: up)
            }
            Spacer()
        }
        .frame(height: 56)
        .background(theme.background, in: .rect(cornerRadius: 8))
    }

    private func candlePreview(up: Bool) -> some View {
        let bodyColor = up ? colors.upBody.color : colors.downBody.color
        let border = up ? colors.upBorder.color : colors.downBorder.color
        let wick = up ? colors.upWick.color : colors.downWick.color
        let hollow = style == .hollow && up
        let fill: Color = hollow ? theme.background : (colors.showBody ? bodyColor : .clear)
        let outline: Color = colors.showBorder ? border : (hollow ? bodyColor : .clear)
        return ZStack {
            Rectangle().fill(colors.showWick ? wick : .clear).frame(width: 1.5, height: 44)
            Rectangle()
                .fill(fill)
                .overlay(Rectangle().stroke(outline, lineWidth: 1))
                .frame(width: 12, height: 24)
        }
    }

    private func colorRow(_ title: String, isOn: Binding<Bool>, up: Binding<RGBAColor>, down: Binding<RGBAColor>) -> some View {
        HStack {
            Toggle(isOn: isOn) { Text(title) }
                .toggleStyle(SquareCheckboxStyle())
            Spacer()
            swatch(up)
            swatch(down)
        }
    }

    private func swatch(_ color: Binding<RGBAColor>) -> some View {
        ColorPicker("", selection: Binding(get: { color.wrappedValue.color },
                                           set: { color.wrappedValue = RGBAColor($0) }), supportsOpacity: true)
            .labelsHidden()
            .frame(width: 44)
    }

    private func preset(_ name: String, up: Color, down: Color, wick: Color?) -> some View {
        Button {
            let u = RGBAColor(up), d = RGBAColor(down)
            colors.upBody = u
            colors.downBody = d
            colors.upBorder = wick.map(RGBAColor.init) ?? u
            colors.downBorder = wick.map(RGBAColor.init) ?? d
            colors.upWick = wick.map(RGBAColor.init) ?? u
            colors.downWick = wick.map(RGBAColor.init) ?? d
            colors.showBody = true
            colors.showBorder = true
            colors.showWick = true
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(up).frame(width: 12, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(wick ?? up, lineWidth: 1))
                    RoundedRectangle(cornerRadius: 2).fill(down).frame(width: 12, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(wick ?? down, lineWidth: 1))
                }
                .padding(6)
                .background(theme.background, in: .rect(cornerRadius: 6))
                Text(name).font(.caption2).foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func numberRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }

    private func load() {
        colors = CandleColors.decode(colorsJSON) ?? CandleColors.standard(for: theme)
        style = CandleStyle(rawValue: candleStyle) ?? .candles
        decimals = precision
        zone = timeZoneID
        accountBalance = balance
        risk = riskPercent
        contract = contractSize
    }

    private func save() {
        // Default colours are not stored, so they keep following the theme.
        colorsJSON = colors == CandleColors.standard(for: theme) ? "" : colors.json
        candleStyle = style.rawValue
        precision = decimals
        timeZoneID = zone
        balance = max(0, accountBalance)
        riskPercent = max(0, risk)
        contractSize = max(0, contract)
        dismiss()
    }
}

/// Square checkbox like TradingView's settings.
struct SquareCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(configuration.isOn ? .primary : .secondary)
                configuration.label.foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

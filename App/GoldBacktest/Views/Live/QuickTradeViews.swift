import SwiftUI
import BacktestKit

/// One-click SELL | lot | BUY panel for the top right of the live screen,
/// like MT5's one-click trading.
struct QuickTradePanel: View {
    let price: Double
    let decimals: Int
    @Binding var lots: Double
    var onSell: () -> Void
    var onBuy: () -> Void

    @State private var showLots = false

    var body: some View {
        HStack(spacing: 0) {
            sideButton("SELL", color: Color(red: 0.949, green: 0.212, blue: 0.271), action: onSell)
            Button { showLots = true } label: {
                Text(Self.lotText(lots))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 34)
                    .background(Color(.systemBackground))
            }
            .popover(isPresented: $showLots) {
                LotPicker(lots: $lots).presentationCompactAdaptation(.popover)
            }
            sideButton("BUY", color: Color(red: 0.161, green: 0.384, blue: 1.0), action: onBuy)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        .fixedSize()
    }

    private func sideButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).font(.system(size: 8, weight: .bold))
                Text(CandleChart.format(price, decimals))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundColor(.white)
            .frame(width: 62, height: 34)
            .background(color)
        }
        .disabled(price <= 0 || lots <= 0)
    }

    static func lotText(_ lots: Double) -> String { String(format: "%.2f", lots) }
}

/// Lot size picker like MT5: presets, quick increments and a stepper.
struct LotPicker: View {
    @Binding var lots: Double

    private static let presets: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Self.presets, id: \.self) { value in
                    Button { lots = value } label: {
                        Text(String(format: "%g", value))
                            .font(.system(size: 17, weight: value == lots ? .bold : .regular))
                            .foregroundColor(value == lots ? .blue : .primary)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                }
            }
            HStack {
                ForEach([0.01, 0.1, 0.5], id: \.self) { step in
                    Button("+\(String(format: "%g", step))") { set(lots + step) }
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 16))
            Divider()
            HStack {
                Button { set(lots - 0.01) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 32) }
                Spacer()
                Text(QuickTradePanel.lotText(lots)).font(.system(size: 18, weight: .semibold).monospacedDigit())
                Spacer()
                Button { set(lots + 0.01) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 32) }
            }
        }
        .padding(14)
        .frame(width: 250)
    }

    private func set(_ value: Double) {
        lots = min(100, max(0.01, (value * 100).rounded() / 100))
    }
}

/// How SL/TP are set automatically on new orders.
enum AutoStopMode: String, CaseIterable, Identifiable {
    /// SL = multiplier × typical bar range of the chart.
    case volatility
    /// SL a fixed price distance from the entry (e.g. 5.0 = $5 on gold).
    case price
    /// SL where the loss reaches a fixed amount of money.
    case money

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volatility: return "Theo biến động (× biên độ nến)"
        case .price: return "Khoảng giá cố định"
        case .money: return "Số tiền rủi ro ($)"
        }
    }
}

/// Automatic SL/TP settings, stored in UserDefaults.
enum AutoStops {
    static let enabledKey = "trade.auto.enabled"
    static let marketKey = "trade.auto.market"
    static let modeKey = "trade.auto.mode"
    static let valueKey = "trade.auto.value"
    static let rrKey = "trade.auto.rr"

    private static var defaults: UserDefaults { .standard }

    static var enabled: Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }
    static var applyToMarket: Bool { defaults.object(forKey: marketKey) as? Bool ?? false }
    static var mode: AutoStopMode { defaults.string(forKey: modeKey).flatMap(AutoStopMode.init) ?? .volatility }
    static var value: Double { defaults.object(forKey: valueKey) as? Double ?? 3 }
    static var riskReward: Double { defaults.object(forKey: rrKey) as? Double ?? 2 }

    /// Distance from the entry to the stop, or nil when automatic SL/TP is off.
    static func stopDistance(lots: Double, contractSize: Double, typicalRange: Double) -> Double? {
        guard enabled, value > 0 else { return nil }
        switch mode {
        case .volatility: return typicalRange * value
        case .price: return value
        case .money: return lots > 0 && contractSize > 0 ? value / (lots * contractSize) : nil
        }
    }
}

/// Settings of automatic SL/TP for limit and one-click orders.
struct AutoStopSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AutoStops.enabledKey) private var enabled = true
    @AppStorage(AutoStops.marketKey) private var applyToMarket = false
    @AppStorage(AutoStops.modeKey) private var mode = AutoStopMode.volatility.rawValue
    @AppStorage(AutoStops.valueKey) private var value = 3.0
    @AppStorage(AutoStops.rrKey) private var riskReward = 2.0
    @State private var rules = PaperTrader.rules

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Tự đặt SL/TP cho lệnh Limit", isOn: $enabled)
                    Toggle("Cả lệnh SELL/BUY một chạm", isOn: $applyToMarket)
                        .disabled(!enabled)
                }
                Section {
                    Picker("Cách tính SL", selection: $mode) {
                        ForEach(AutoStopMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    HStack {
                        Text(valueTitle)
                        Spacer()
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    Stepper("TP = \(String(format: "%g", riskReward)) × SL (RR)", value: $riskReward, in: 0.5...20, step: 0.5)
                } header: {
                    Text("Khoảng cách")
                } footer: {
                    Text("Sau khi đặt, vẫn kéo tay được đường SL/TP trên biểu đồ.")
                }
                Section {
                    Toggle("Tự dời SL", isOn: $rules.moveStop)
                    if rules.moveStop {
                        Stepper("Khi giá đạt \(String(format: "%g", rules.triggerR))R (R:R 1:\(String(format: "%g", rules.triggerR)))",
                                value: $rules.triggerR, in: 0.5...10, step: 0.5)
                        Stepper(rules.lockR == 0 ? "Dời SL về hoà vốn" : "Dời SL khoá lời +\(String(format: "%g", rules.lockR))R",
                                value: $rules.lockR, in: 0...9, step: 0.5)
                        Stepper(rules.trailStepR == 0 ? "Trailing: tắt" : "Trailing: mỗi +\(String(format: "%g", rules.trailStepR))R dời thêm",
                                value: $rules.trailStepR, in: 0...5, step: 0.5)
                    }
                } header: {
                    Text("Tự dời SL (lệnh demo và Replay)")
                } footer: {
                    Text("1R = khoảng cách từ giá vào tới SL ban đầu. Ví dụ: vào 4000, SL 3990 (1R = 10$): khi giá tới 4020 (2R), SL dời lên 4010 (+1R). Bật trailing thì cứ thêm mỗi bước R, SL dời theo.")
                }
                Section {
                    Toggle("Tự chốt khi giá quay đầu", isOn: $rules.closeOnReversal)
                    if rules.closeOnReversal {
                        Stepper("Chỉ khi đang lời ≥ \(String(format: "%g", rules.minProfitR))R", value: $rules.minProfitR, in: 0...10, step: 0.5)
                        Toggle("MSS / phá cấu trúc ngược chiều", isOn: $rules.reversalStructure)
                        if rules.reversalStructure {
                            Stepper("Swing \(rules.swingLength) nến mỗi bên", value: $rules.swingLength, in: 1...10)
                        }
                        Toggle("Nến nhấn chìm ngược chiều", isOn: $rules.reversalEngulfing)
                        Stepper(rules.givebackPercent == 0 ? "Trả lại lợi nhuận: tắt" : "Trả lại \(Int(rules.givebackPercent))% lợi nhuận cao nhất",
                                value: $rules.givebackPercent, in: 0...90, step: 10)
                    }
                } header: {
                    Text("Tự chốt khi quay đầu")
                } footer: {
                    Text("Kiểm tra mỗi khi một cây nến đóng trên khung đang xem. Lệnh đóng ở giá hiện tại và app đọc \"Closed on reversal\".")
                }
            }
            .onChange(of: rules) { _, value in PaperTrader.saveRules(value) }
            .navigationTitle("SL/TP & quản lý lệnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
        }
    }

    private var valueTitle: String {
        switch AutoStopMode(rawValue: mode) ?? .volatility {
        case .volatility: return "Số lần biên độ nến"
        case .price: return "Khoảng giá (vd 5 = 5$ vàng)"
        case .money: return "Rủi ro mỗi lệnh ($)"
        }
    }
}

/// All timeframes in a grid: tap to switch, tick ☆ to keep it in the row
/// under the price.
struct IntervalPicker: View {
    let current: BinanceClient.Interval
    let favorites: Set<BinanceClient.Interval>
    var onSelect: (BinanceClient.Interval) -> Void
    var onToggleFavorite: (BinanceClient.Interval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Khung thời gian").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(LiveMarket.intervals, id: \.self) { interval in
                    let selected = interval == current
                    let favorite = favorites.contains(interval)
                    Button { onSelect(interval) } label: {
                        Text(LiveView.label(interval))
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundColor(selected ? .white : .primary)
                            .background(selected ? Color.accentColor : Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button { onToggleFavorite(interval) } label: {
                                    Image(systemName: favorite ? "star.fill" : "star")
                                        .font(.system(size: 10))
                                        .foregroundColor(favorite ? .yellow : .secondary)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Chạm để đổi khung. Bấm ☆ để hiện khung đó ở hàng ngang dưới giá.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 300)
    }
}

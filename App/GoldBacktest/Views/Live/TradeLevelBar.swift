import SwiftUI
import BacktestKit

/// The selected trade's SL / TP, set in pips from its entry: − / + by 1 pip, quick picks (SL 10 / 15 / 20 pip,
/// TP 1R / 2R / 3R), the price and money, and nothing sent before Xác nhận. Tight stops (10–20 pip) are easy
/// here, where pulling them out of the entry line was not.
struct TradeLevelBar: View {
    struct Info {
        var title: String
        var side: PaperAccount.Side
        var entry: Double
        var stop: Double?
        var target: Double?
        /// Price of one pip (gold 0.1).
        var pip: Double
        var decimals: Int
    }

    struct Edit: Equatable {
        /// "sl" or "tp".
        var field: String
        var price: Double
    }

    let info: Info
    @Binding var edit: Edit?
    let theme: ChartTheme
    var money: (Double) -> String
    var problem: (String, Double) -> String?
    var onConfirm: (String, Double) -> Void
    var onClose: () -> Void

    @AppStorage("trade.slPips") private var slPips = 15.0

    var body: some View {
        Group {
            if let edit { editor(edit) } else { summary }
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.background.opacity(0.97), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.78, green: 0.54, blue: 0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(.horizontal, 8)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Text(info.title).foregroundColor(theme.primaryText).lineLimit(1)
            Spacer(minLength: 4)
            chip(info.stop == nil ? "+SL" : "SL ✎", color: theme.down) { start("sl") }
            chip(info.target == nil ? "+TP" : "TP ✎", color: theme.up) { start("tp") }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(theme.text)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private func editor(_ e: Edit) -> some View {
        let isStop = e.field == "sl"
        let sign = info.side.sign * (isStop ? -1 : 1)
        let pips = (e.price - info.entry) * sign / info.pip
        let risk = info.stop.map { abs(info.entry - $0) } ?? 0
        let warning = problem(e.field, e.price)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(isStop ? "SL" : "TP").foregroundColor(isStop ? theme.down : theme.up)
                HStack(spacing: 0) {
                    stepButton("minus") { set(e.price - sign * info.pip) }
                    Text(String(format: "%.1f pip", pips)).monospacedDigit().frame(minWidth: 70)
                    stepButton("plus") { set(e.price + sign * info.pip) }
                }
                .background(theme.grid.opacity(0.6), in: .rect(cornerRadius: 9))
                if isStop {
                    ForEach([10.0, 15.0, 20.0], id: \.self) { p in
                        pick("\(Int(p))", on: abs(pips - p) < 0.05) { slPips = p; set(info.entry + sign * p * info.pip) }
                    }
                } else if risk > 0 {
                    ForEach([1.0, 2.0, 3.0], id: \.self) { r in
                        pick("\(Int(r))R", on: abs(pips * info.pip - r * risk) < info.pip / 2) { set(info.entry + sign * r * risk) }
                    }
                } else {
                    ForEach([20.0, 30.0, 40.0], id: \.self) { p in
                        pick("\(Int(p))", on: abs(pips - p) < 0.05) { set(info.entry + sign * p * info.pip) }
                    }
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(CandleChart.format(e.price, info.decimals)).monospacedDigit().foregroundColor(theme.primaryText)
                    Text(money(e.price)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundColor(money(e.price).hasPrefix("-") ? theme.down : theme.up)
                }
                if let warning {
                    Text(warning).font(.system(size: 11)).foregroundColor(theme.down).lineLimit(2)
                }
                Spacer(minLength: 4)
                Button("Huỷ") { edit = nil }
                    .buttonStyle(.bordered)
                Button("Xác nhận") {
                    onConfirm(e.field, e.price)
                    edit = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.54, blue: 0.09))
                .disabled(warning != nil)
            }
        }
    }

    /// SL at the last pip distance used (15 at first), TP at 2R (or 30 pip without an SL).
    private func start(_ field: String) {
        let sign = info.side.sign * (field == "sl" ? -1 : 1)
        if field == "sl" {
            edit = Edit(field: field, price: rounded(info.stop ?? info.entry + sign * slPips * info.pip))
        } else {
            let risk = info.stop.map { abs(info.entry - $0) } ?? 15 * info.pip
            edit = Edit(field: field, price: rounded(info.target ?? info.entry + sign * risk * 2))
        }
    }

    private func set(_ price: Double) {
        guard let e = edit else { return }
        edit = Edit(field: e.field, price: rounded(price))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func rounded(_ price: Double) -> Double {
        let f = pow(10, Double(info.decimals))
        return (price * f).rounded() / f
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(theme.primaryText)
                .frame(width: 34, height: 30)
        }
    }

    private func pick(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 12, weight: .semibold))
                .foregroundColor(on ? Color(red: 0.95, green: 0.76, blue: 0.31) : theme.text)
                .padding(.horizontal, 7).frame(height: 26)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color(red: 0.95, green: 0.76, blue: 0.31) : theme.grid, lineWidth: 1))
        }
    }

    private func chip(_ text: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).foregroundColor(color)
                .padding(.horizontal, 10).frame(height: 30)
                .background(theme.grid.opacity(0.6), in: Capsule())
        }
    }

    /// Price of a pip as traders count it: gold 0.1, silver / oil / JPY pairs 0.01, crypto and indices 1, FX 0.0001.
    static func pip(for symbol: String) -> Double {
        let s = symbol.uppercased()
        if s.contains("XAU") || s.contains("GOLD") { return 0.1 }
        if ["XAG", "SILVER", "OIL", "XTI", "XBR", "WTI", "BRENT", "JPY"].contains(where: s.contains) { return 0.01 }
        if ["BTC", "ETH", "SOL", "BNB", "LTC", "US30", "USTEC", "NAS", "SPX", "US500", "DE30", "DE40", "JP225", "UK100", "HK50"].contains(where: s.contains) { return 1 }
        return 0.0001
    }
}

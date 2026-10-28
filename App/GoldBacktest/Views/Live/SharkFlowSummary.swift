import SwiftUI
import BacktestKit

/// "Dòng tiền cá mập" in the legend above the chart: what money is doing and
/// what price and money together mean, in two lines of plain words.
struct SharkFlowSummary: View {
    let output: SharkFlow.Output
    let total: Int
    let theme: ChartTheme
    var showZones = true
    var decimals = 2

    /// The strongest demand under the price and supply above it: where to look for an entry.
    private var zonesLine: String? {
        let buy = output.zones.first { $0.demand }, sell = output.zones.first { !$0.demand }
        guard buy != nil || sell != nil else { return nil }
        let text = { (z: SharkFlow.Zone) in
            "\(CandleChart.format(z.bottom, decimals))–\(CandleChart.format(z.top, decimals)) (\(Int((z.strength * 100).rounded()))%)"
        }
        return [buy.map { "🟢 Chờ MUA \(text($0))" }, sell.map { "🔴 Chờ BÁN \(text($0))" }].compactMap { $0 }.joined(separator: " · ")
    }

    static let green = Color(red: 0.03, green: 0.6, blue: 0.5)
    static let red = Color(red: 0.95, green: 0.21, blue: 0.27)

    static func verdict(_ flow: Double) -> (text: String, color: Color) {
        switch flow {
        case 0.25...: return ("Tiền VÀO mạnh", green)
        case 0.08..<0.25: return ("Tiền đang vào", green)
        case -0.08..<0.08: return ("Tiền cân bằng", .gray)
        case -0.25 ..< -0.08: return ("Tiền đang ra", red)
        default: return ("Tiền RA mạnh", red)
        }
    }

    /// One sentence a beginner can act on.
    static func advice(_ situation: SharkFlow.Situation?) -> (text: String, color: Color) {
        switch situation {
        case .strongUp: return ("Giá tăng + tiền vào → xu hướng tăng khoẻ, ưu tiên MUA", green)
        case .weakUp: return ("⚠️ Giá tăng nhưng tiền RA → tăng yếu, dễ đảo chiều giảm", .orange)
        case .strongDown: return ("Giá giảm + tiền ra → xu hướng giảm khoẻ, ưu tiên BÁN", red)
        case .weakDown: return ("⚠️ Giá giảm nhưng tiền VÀO → có người gom hàng, dễ bật tăng", .orange)
        case .flat: return ("Giá đi ngang → chờ dòng tiền chọn hướng", .gray)
        case nil: return ("Chưa đủ nến để đọc dòng tiền", .gray)
        }
    }

    var body: some View {
        let flow = output.current ?? 0
        let verdict = Self.verdict(flow)
        let advice = Self.advice(output.situation)
        let lastShark = output.sharks.last
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("🦈 Dòng tiền").foregroundColor(theme.primaryText)
                Text("\(verdict.text) \(String(format: "%+.0f%%", flow * 100))")
                    .foregroundColor(verdict.color)
                    .fontWeight(.semibold)
                if let lastShark, lastShark.index >= total - 30 {
                    Text("· cá mập \(lastShark.buying ? "MUA" : "BÁN") ×\(String(format: "%.1f", lastShark.ratio))")
                        .foregroundColor(lastShark.buying ? theme.up : theme.down)
                }
            }
            Text(advice.text).foregroundColor(advice.color)
            if showZones, let line = zonesLine {
                Text(line).foregroundColor(theme.primaryText)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

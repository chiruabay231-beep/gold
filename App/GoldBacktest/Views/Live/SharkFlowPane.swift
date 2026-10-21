import SwiftUI
import BacktestKit

/// "Dòng tiền cá mập" under the chart: a plain-words verdict (money coming in
/// or going out, how strongly, the latest shark) and green/red bars per candle.
struct SharkFlowPane: View {
    let output: SharkFlow.Output
    let range: Range<Int>
    let theme: ChartTheme
    /// Plot width of the main chart (without its price axis), to line the bars up.
    var axisWidth: CGFloat = 66

    static func verdict(_ flow: Double) -> (text: String, color: Color) {
        switch flow {
        case 0.25...: return ("Tiền đang VÀO mạnh", Color(red: 0.03, green: 0.6, blue: 0.5))
        case 0.08..<0.25: return ("Tiền đang vào", Color(red: 0.03, green: 0.6, blue: 0.5))
        case -0.08..<0.08: return ("Cân bằng", .gray)
        case -0.25 ..< -0.08: return ("Tiền đang ra", Color(red: 0.95, green: 0.21, blue: 0.27))
        default: return ("Tiền đang RA mạnh", Color(red: 0.95, green: 0.21, blue: 0.27))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Canvas { context, size in draw(in: &context, size: size) }
        }
        .padding(.top, 3)
        .frame(height: 92)
        .background(theme.background)
        .overlay(alignment: .top) { Rectangle().fill(theme.grid).frame(height: 1) }
    }

    private var header: some View {
        let flow = output.current ?? 0
        let verdict = Self.verdict(flow)
        let lastShark = output.sharks.last
        return HStack(spacing: 6) {
            Text("🦈 Dòng tiền")
                .foregroundColor(theme.primaryText)
            Text("\(verdict.text) \(String(format: "%+.0f%%", flow * 100))")
                .foregroundColor(verdict.color)
                .fontWeight(.semibold)
            if let lastShark, lastShark.index >= range.lowerBound {
                Text("· cá mập \(lastShark.buying ? "MUA" : "BÁN") \(String(format: "×%.1f", lastShark.ratio))")
                    .foregroundColor(lastShark.buying ? theme.up : theme.down)
            }
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 6)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let width = max(size.width - axisWidth, 10)
        let count = max(range.count, 1)
        let barWidth = width / CGFloat(count)
        let mid = size.height / 2
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: mid))
        zero.addLine(to: CGPoint(x: width, y: mid))
        context.stroke(zero, with: .color(theme.grid), lineWidth: 1)
        for (k, i) in range.enumerated() where i < output.flow.count {
            let value = output.flow[i]
            guard value.isFinite else { continue }
            let h = CGFloat(abs(value)) * (mid - 2)
            let x = CGFloat(k) * barWidth
            let rect = CGRect(x: x + barWidth * 0.15, y: value >= 0 ? mid - h : mid, width: max(barWidth * 0.7, 1), height: h)
            context.fill(Path(rect), with: .color((value >= 0 ? theme.up : theme.down).opacity(0.75)))
        }
        // Sharks as dots on the zero line.
        for shark in output.sharks where range.contains(shark.index) {
            let x = (CGFloat(shark.index - range.lowerBound) + 0.5) * barWidth
            let r: CGFloat = 3
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: mid - r, width: r * 2, height: r * 2)),
                         with: .color(shark.buying ? theme.up : theme.down))
        }
        context.draw(Text("VÀO").font(.system(size: 9)).foregroundColor(theme.text),
                     at: CGPoint(x: width + 6, y: 8), anchor: .leading)
        context.draw(Text("RA").font(.system(size: 9)).foregroundColor(theme.text),
                     at: CGPoint(x: width + 6, y: size.height - 8), anchor: .leading)
    }
}

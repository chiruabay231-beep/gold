import SwiftUI
import BacktestKit

/// "Dòng tiền cá mập" under the chart: what price and money are doing in plain
/// words, green/red bars lined up with the candles above, ⚠ where price and
/// money start to disagree. Drag the grip at the top to make it taller.
struct SharkFlowPane: View {
    let output: SharkFlow.Output
    /// The main chart's view: bars sit under their candles, the last one too.
    let viewport: ChartViewport
    let total: Int
    let theme: ChartTheme
    @Binding var height: Double
    /// Price axis width of the main chart.
    var axisWidth: CGFloat = 66

    @State private var dragStart: Double?

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
        VStack(alignment: .leading, spacing: 2) {
            grip
            header
            Canvas { context, size in draw(in: &context, size: size) }
        }
        .frame(height: height)
        .background(theme.background)
        .overlay(alignment: .top) { Rectangle().fill(theme.grid).frame(height: 1) }
    }

    /// Drag up or down to resize.
    private var grip: some View {
        Capsule()
            .fill(theme.text.opacity(0.45))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = dragStart ?? height
                    dragStart = start
                    height = min(max(start - Double(value.translation.height), 80), 320)
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityLabel("Kéo để đổi chiều cao")
    }

    private var header: some View {
        let flow = output.current ?? 0
        let verdict = Self.verdict(flow)
        let advice = Self.advice(output.situation)
        let lastShark = output.sharks.last
        return VStack(alignment: .leading, spacing: 1) {
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
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 6)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let width = max(size.width - axisWidth, 10)
        let (start, _) = viewport.bounds(total: total)
        let barWidth = width / CGFloat(max(viewport.visibleCount, 1))
        func x(_ index: Int) -> CGFloat { CGFloat(Double(index) - start + 0.5) * barWidth }
        let range = viewport.range(total: total)
        let mid = size.height / 2
        var zero = Path()
        zero.move(to: CGPoint(x: 0, y: mid))
        zero.addLine(to: CGPoint(x: width, y: mid))
        context.stroke(zero, with: .color(theme.grid), lineWidth: 1)
        var plot = context
        plot.clip(to: Path(CGRect(x: 0, y: 0, width: width, height: size.height)))
        for i in range where i < output.flow.count {
            let value = output.flow[i]
            guard value.isFinite else { continue }
            let h = CGFloat(abs(value)) * (mid - 2)
            let rect = CGRect(x: x(i) - barWidth * 0.35, y: value >= 0 ? mid - h : mid, width: max(barWidth * 0.7, 1), height: h)
            plot.fill(Path(rect), with: .color((value >= 0 ? theme.up : theme.down).opacity(0.75)))
        }
        // Sharks as dots on the zero line.
        for shark in output.sharks where range.contains(shark.index) {
            let r: CGFloat = 3
            plot.fill(Path(ellipseIn: CGRect(x: x(shark.index) - r, y: mid - r, width: r * 2, height: r * 2)),
                      with: .color(shark.buying ? theme.up : theme.down))
        }
        // Where price and money start to disagree.
        for d in output.divergences where range.contains(d.index) {
            plot.draw(Text("⚠️").font(.system(size: 10)),
                      at: CGPoint(x: x(d.index), y: d.bullish ? size.height - 8 : 8), anchor: .center)
        }
        context.draw(Text("VÀO").font(.system(size: 9)).foregroundColor(theme.text),
                     at: CGPoint(x: width + 6, y: 8), anchor: .leading)
        context.draw(Text("RA").font(.system(size: 9)).foregroundColor(theme.text),
                     at: CGPoint(x: width + 6, y: size.height - 8), anchor: .leading)
    }
}

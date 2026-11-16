import SwiftUI
import BacktestKit

/// MT5's timeframe ring: a tap on the chart shows it round the finger; a tap on a timeframe switches to it.
/// It turns in with a little spring, its labels popping in one after another round it.
struct TimeframeRing: View {
    var current: BinanceClient.Interval
    var color: Color
    var compareOn: Bool
    var onPick: (BinanceClient.Interval) -> Void
    var onIndicators: () -> Void
    var onCompare: () -> Void
    var onSettings: () -> Void

    static let size: CGFloat = 186
    static let intervals: [(BinanceClient.Interval, String)] = [
        (.m1, "M1"), (.m5, "M5"), (.m15, "M15"), (.m30, "M30"), (.h1, "H1"), (.h4, "H4"), (.d1, "D1"), (.w1, "W1"),
    ]

    @State private var shown = false

    private enum Item: Identifiable {
        case interval(BinanceClient.Interval, String)
        case indicators, compare, settings
        var id: String {
            switch self {
            case .interval(let i, _): return i.rawValue
            case .indicators: return "ind"
            case .compare: return "cmp"
            case .settings: return "set"
            }
        }
    }

    private var items: [Item] {
        Self.intervals.map { Item.interval($0.0, $0.1) } + [.settings, .compare, .indicators]
    }

    var body: some View {
        let list = items
        let tfCount = Self.intervals.count
        let step = 360.0 / Double(list.count)
        // The timeframes over the top, the three tools centred at the bottom.
        let start = 180 - (Double(tfCount) + 1) * step
        let radius = Self.size / 2 - 23
        ZStack {
            Circle()
                .stroke(color, lineWidth: 44)
                .frame(width: Self.size - 44, height: Self.size - 44)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                let angle = (start + step * Double(index) - 90) * .pi / 180
                button(item)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.02), value: shown)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .scaleEffect(shown ? 1 : 0.55)
        .rotationEffect(.degrees(shown ? 0 : -80))
        .opacity(shown ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.68), value: shown)
        .onAppear { shown = true }
    }

    @ViewBuilder
    private func button(_ item: Item) -> some View {
        switch item {
        case .interval(let interval, let name):
            let on = interval == current
            Button { onPick(interval) } label: {
                Text(name)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(on ? color : .white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 32, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white : Color.clear))
            }
            .buttonStyle(.plain)
        case .indicators:
            tool("function", on: false, action: onIndicators)
        case .compare:
            tool("rectangle.split.1x2", on: compareOn, action: onCompare)
        case .settings:
            tool("slider.vertical.3", on: false, action: onSettings)
        }
    }

    private func tool(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(on ? color : .white)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

/// The ring's colour, kept as a hex string in AppStorage.
enum TimeframeRingStyle {
    static let enabledKey = "live.tfRing"
    static let colorKey = "live.tfRingColor"
    static let defaultHex = "#4068F6"

    static func color(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return color(defaultHex) }
        return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }

    static func hex(_ color: Color) -> String {
        let c = RGBAColor(color)
        let r = Int((c.red * 255).rounded()), g = Int((c.green * 255).rounded()), b = Int((c.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

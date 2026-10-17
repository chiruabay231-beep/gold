import SwiftUI
import UIKit
import BacktestKit

/// Colours of Binance's dark chart theme.
enum BinanceTheme {
    static let background = Color(red: 0.086, green: 0.102, blue: 0.118)      // #161A1E
    static let panel = Color(red: 0.094, green: 0.102, blue: 0.125)           // #181A20
    static let grid = Color(red: 0.169, green: 0.192, blue: 0.224)            // #2B3139
    static let text = Color(red: 0.518, green: 0.557, blue: 0.612)            // #848E9C
    static let primaryText = Color(red: 0.918, green: 0.925, blue: 0.937)     // #EAECEF
    static let up = Color(red: 0.055, green: 0.796, blue: 0.506)              // #0ECB81
    static let down = Color(red: 0.965, green: 0.275, blue: 0.365)            // #F6465D
    static let yellow = Color(red: 0.941, green: 0.725, blue: 0.043)          // #F0B90B
    /// MA(7), MA(25), MA(99) colours.
    static let maColors = [Color(red: 0.941, green: 0.725, blue: 0.043),
                           Color(red: 0.882, green: 0.329, blue: 0.835),
                           Color(red: 0.494, green: 0.408, blue: 0.894)]
}

/// Which part of the history is visible. `rightOffset` is how many bars
/// the view is scrolled back from the latest bar (0 = follows live data).
struct ChartViewport: Equatable {
    var visibleCount: Double = 80
    var rightOffset: Double = 0
    /// Empty space after the last candle, in bars.
    var rightPadding: Double = 3
    /// Fixed price range set by dragging the price axis; nil = auto-fit.
    var manualPriceRange: ClosedRange<Double>?

    func bounds(total: Int) -> (start: Double, end: Double) {
        let end = Double(total) - rightOffset + rightPadding
        return (end - visibleCount, end)
    }

    func range(total: Int) -> Range<Int> {
        let (start, end) = bounds(total: total)
        let lower = max(0, Int(floor(start)))
        let upper = min(total, Int(ceil(end)))
        return lower < upper ? lower..<upper : 0..<0
    }
}

struct ChartMarker: Identifiable {
    enum Kind { case buy, sell, exit }

    var id = UUID()
    var index: Int
    var price: Double
    var kind: Kind
    /// Draw a dashed line from this marker to another bar/price (entry → exit).
    var linkTo: (index: Int, price: Double, isWin: Bool)?
}

/// Candlestick chart styled after Binance: dark theme, MA overlays, volume
/// pane, right-hand price axis and last-price line. Drag to scroll, pinch to
/// zoom, press and hold to show the crosshair with OHLC values.
struct CandleChart: View {
    let candles: [Candle]
    var overlays: [ChartLine] = []
    var markers: [ChartMarker] = []
    var showVolume = true
    /// Bar length in seconds; shows a countdown to the close of the last bar.
    var countdownInterval: TimeInterval?
    @Binding var viewport: ChartViewport

    private enum DragMode { case pan, axis, crosshair }

    @State private var dragMode: DragMode?
    @State private var panStartOffset: Double = 0
    @State private var dragStartRange: ClosedRange<Double>?
    @State private var zoomStartCount: Double?
    @State private var crosshair: CGPoint?
    @State private var pressEndedAt = Date.distantPast

    private let axisWidth: CGFloat = 62
    private let timeAxisHeight: CGFloat = 18
    private let headerHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, axisWidth: axisWidth, timeAxisHeight: timeAxisHeight,
                                headerHeight: headerHeight, showVolume: showVolume)
            ZStack(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: countdownInterval == nil ? 3600 : 1)) { timeline in
                    Canvas { context, _ in
                        draw(in: &context, layout: layout, now: timeline.date)
                    }
                }
                header(layout: layout)
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
            }
            .background(BinanceTheme.background)
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(layout: layout))
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(crosshairGesture)
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                // Double tap on the price axis: back to auto-fit.
                if value.location.x > layout.axisX { viewport.manualPriceRange = nil }
            })
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                // The release of a long press also ends as a tap; keep that crosshair.
                guard value.location.x < layout.axisX, Date().timeIntervalSince(pressEndedAt) > 0.3 else { return }
                crosshair = crosshair == nil ? value.location : nil
            })
        }
        .onChange(of: candles.count) { oldCount, newCount in
            // Keep the same bars on screen when scrolled back and a new bar arrives.
            if viewport.rightOffset > 0.5, newCount > oldCount, oldCount > 0 {
                viewport.rightOffset += Double(newCount - oldCount)
            }
        }
    }

    // MARK: - Layout

    struct Layout {
        var plot: CGRect
        var volume: CGRect
        var timeAxis: CGRect
        var axisX: CGFloat

        init(size: CGSize, axisWidth: CGFloat, timeAxisHeight: CGFloat, headerHeight: CGFloat, showVolume: Bool) {
            let width = max(10, size.width - axisWidth)
            let usable = max(40, size.height - timeAxisHeight - headerHeight)
            let volumeHeight = showVolume ? usable * 0.2 : 0
            plot = CGRect(x: 0, y: headerHeight, width: width, height: usable - volumeHeight)
            volume = CGRect(x: 0, y: plot.maxY, width: width, height: volumeHeight)
            timeAxis = CGRect(x: 0, y: volume.maxY, width: width, height: timeAxisHeight)
            axisX = width
        }
    }

    private struct Scale {
        var start: Double
        var barWidth: CGFloat
        var low: Double
        var high: Double
        var plot: CGRect

        func x(_ index: Int) -> CGFloat { CGFloat(Double(index) - start + 0.5) * barWidth }
        func y(_ price: Double) -> CGFloat {
            guard high > low else { return plot.midY }
            return plot.maxY - CGFloat((price - low) / (high - low)) * plot.height
        }
        func price(atY y: CGFloat) -> Double {
            low + Double((plot.maxY - y) / plot.height) * (high - low)
        }
        func index(atX x: CGFloat) -> Int { Int(floor(Double(x / barWidth) + start)) }
    }

    private func scale(layout: Layout) -> Scale {
        let (start, _) = viewport.bounds(total: candles.count)
        let barWidth = layout.plot.width / CGFloat(max(viewport.visibleCount, 1))
        var low = Double.infinity, high = -Double.infinity
        let range = viewport.range(total: candles.count)
        for i in range {
            low = min(low, candles[i].low)
            high = max(high, candles[i].high)
        }
        let candleLow = low, candleHigh = high
        for line in overlays where !line.isHorizontal {
            for i in range where i < line.values.count {
                let v = line.values[i]
                // Skip lines far from price (e.g. a 0/1 flag) so candles stay readable.
                if v.isFinite, v > candleLow * 0.8, v < candleHigh * 1.2 {
                    low = min(low, v)
                    high = max(high, v)
                }
            }
        }
        if let manual = viewport.manualPriceRange {
            return Scale(start: start, barWidth: barWidth, low: manual.lowerBound, high: manual.upperBound, plot: layout.plot)
        }
        if !low.isFinite || !high.isFinite { low = 0; high = 1 }
        if low == high { low -= 1; high += 1 }
        let pad = (high - low) * 0.08
        return Scale(start: start, barWidth: barWidth, low: low - pad, high: high + pad, plot: layout.plot)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, layout: Layout, now: Date) {
        guard !candles.isEmpty else { return }
        let s = scale(layout: layout)
        let range = viewport.range(total: candles.count)
        let ticks = priceTicks(low: s.low, high: s.high, count: 5)
        let decimals = Self.decimals(for: s.high)

        // Grid and price axis.
        for tick in ticks {
            let y = s.y(tick)
            guard y > layout.plot.minY + 6, y < layout.plot.maxY - 4 else { continue }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: layout.axisX, y: y))
            context.stroke(line, with: .color(BinanceTheme.grid), lineWidth: 0.5)
            context.draw(Text(Self.format(tick, decimals)).font(.system(size: 10)).foregroundColor(BinanceTheme.text),
                         at: CGPoint(x: layout.axisX + 4, y: y), anchor: .leading)
        }
        let timeStep = max(1, Int(Double(range.count) / 4))
        let timeFormat = Self.timeFormat(for: candles)
        for i in range where (i - range.lowerBound) % timeStep == timeStep / 2 {
            let x = s.x(i)
            var line = Path()
            line.move(to: CGPoint(x: x, y: layout.plot.minY))
            line.addLine(to: CGPoint(x: x, y: layout.volume.maxY))
            context.stroke(line, with: .color(BinanceTheme.grid), lineWidth: 0.5)
            context.draw(Text(candles[i].time.formatted(timeFormat)).font(.system(size: 10)).foregroundColor(BinanceTheme.text),
                         at: CGPoint(x: x, y: layout.timeAxis.midY), anchor: .center)
        }
        var separator = Path()
        separator.move(to: CGPoint(x: layout.axisX, y: layout.plot.minY))
        separator.addLine(to: CGPoint(x: layout.axisX, y: layout.timeAxis.minY))
        context.stroke(separator, with: .color(BinanceTheme.grid), lineWidth: 0.5)

        // Volume.
        if showVolume, layout.volume.height > 0 {
            let maxVolume = range.map { candles[$0].volume }.max() ?? 0
            if maxVolume > 0 {
                for i in range {
                    let c = candles[i]
                    let h = CGFloat(c.volume / maxVolume) * (layout.volume.height - 4)
                    let rect = CGRect(x: s.x(i) - s.barWidth * 0.35, y: layout.volume.maxY - h,
                                      width: max(1, s.barWidth * 0.7), height: h)
                    context.fill(Path(rect), with: .color((c.close >= c.open ? BinanceTheme.up : BinanceTheme.down).opacity(0.45)))
                }
            }
        }

        // Candles.
        var context2 = context
        context2.clip(to: Path(layout.plot))
        for i in range {
            let c = candles[i]
            let color = c.close >= c.open ? BinanceTheme.up : BinanceTheme.down
            let x = s.x(i)
            var wick = Path()
            wick.move(to: CGPoint(x: x, y: s.y(c.high)))
            wick.addLine(to: CGPoint(x: x, y: s.y(c.low)))
            context2.stroke(wick, with: .color(color), lineWidth: 1)
            let top = s.y(max(c.open, c.close))
            let bottom = s.y(min(c.open, c.close))
            let body = CGRect(x: x - s.barWidth * 0.35, y: top, width: max(1, s.barWidth * 0.7), height: max(1, bottom - top))
            context2.fill(Path(body), with: .color(color))
        }

        // Overlays.
        for line in overlays {
            if line.isHorizontal {
                guard let v = line.values.first(where: \.isFinite) else { continue }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: s.y(v)))
                path.addLine(to: CGPoint(x: layout.axisX, y: s.y(v)))
                context2.stroke(path, with: .color(BinanceTheme.text), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                continue
            }
            var path = Path()
            var drawing = false
            for i in range where i < line.values.count {
                let v = line.values[i]
                guard v.isFinite else { drawing = false; continue }
                let point = CGPoint(x: s.x(i), y: s.y(v))
                if drawing { path.addLine(to: point) } else { path.move(to: point); drawing = true }
            }
            context2.stroke(path, with: .color(line.color), lineWidth: 1.2)
        }

        // Trade / signal markers.
        for marker in markers where range.contains(marker.index) || (marker.linkTo.map { range.contains($0.index) } ?? false) {
            if let link = marker.linkTo {
                var path = Path()
                path.move(to: CGPoint(x: s.x(marker.index), y: s.y(marker.price)))
                path.addLine(to: CGPoint(x: s.x(link.index), y: s.y(link.price)))
                context2.stroke(path, with: .color((link.isWin ? BinanceTheme.up : BinanceTheme.down).opacity(0.8)),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            guard range.contains(marker.index) else { continue }
            let x = s.x(marker.index)
            let c = candles[marker.index]
            switch marker.kind {
            case .buy:
                let tip = CGPoint(x: x, y: s.y(c.low) + 4)
                context2.fill(triangle(tip: tip, pointingUp: true), with: .color(BinanceTheme.up))
                context2.draw(Text("B").font(.system(size: 9, weight: .bold)).foregroundColor(BinanceTheme.up),
                              at: CGPoint(x: x, y: tip.y + 16), anchor: .center)
            case .sell:
                let tip = CGPoint(x: x, y: s.y(c.high) - 4)
                context2.fill(triangle(tip: tip, pointingUp: false), with: .color(BinanceTheme.down))
                context2.draw(Text("S").font(.system(size: 9, weight: .bold)).foregroundColor(BinanceTheme.down),
                              at: CGPoint(x: x, y: tip.y - 16), anchor: .center)
            case .exit:
                let rect = CGRect(x: x - 3, y: s.y(marker.price) - 3, width: 6, height: 6)
                context2.stroke(Path(ellipseIn: rect), with: .color(BinanceTheme.primaryText), lineWidth: 1.2)
            }
        }

        // Last price line and label.
        if let last = candles.last {
            let y = s.y(last.close)
            let color = last.close >= last.open ? BinanceTheme.up : BinanceTheme.down
            if y >= layout.plot.minY, y <= layout.plot.maxY {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.axisX, y: y))
                context.stroke(path, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            }
            let countdown = countdownInterval.map { Self.countdown(until: last.time.addingTimeInterval($0), now: now) }
            let boxHeight: CGFloat = countdown == nil ? 16 : 28
            let labelY = min(max(y, layout.plot.minY + boxHeight / 2), layout.plot.maxY - boxHeight / 2)
            let box = CGRect(x: layout.axisX + 1, y: labelY - 8, width: axisWidth - 2, height: boxHeight)
            context.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(color))
            context.draw(Text(Self.format(last.close, decimals)).font(.system(size: 10, weight: .semibold)).foregroundColor(.white),
                         at: CGPoint(x: box.midX, y: box.minY + 8), anchor: .center)
            if let countdown {
                context.draw(Text(countdown).font(.system(size: 10).monospacedDigit()).foregroundColor(.white.opacity(0.9)),
                             at: CGPoint(x: box.midX, y: box.minY + 20), anchor: .center)
            }
        }

        // Crosshair.
        if let point = crosshair, let index = crosshairIndex(layout: layout) {
            let x = s.x(index)
            let y = min(max(point.y, layout.plot.minY), layout.plot.maxY)
            var path = Path()
            path.move(to: CGPoint(x: x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: x, y: layout.volume.maxY))
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: layout.axisX, y: y))
            context.stroke(path, with: .color(BinanceTheme.primaryText.opacity(0.6)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            let priceBox = CGRect(x: layout.axisX + 1, y: y - 8, width: axisWidth - 2, height: 16)
            context.fill(Path(roundedRect: priceBox, cornerRadius: 2), with: .color(BinanceTheme.grid))
            context.draw(Text(Self.format(s.price(atY: y), decimals)).font(.system(size: 10)).foregroundColor(BinanceTheme.primaryText),
                         at: CGPoint(x: priceBox.midX, y: priceBox.midY), anchor: .center)
            let timeText = candles[index].time.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits).hour().minute())
            let timeBox = CGRect(x: x - 52, y: layout.timeAxis.minY + 1, width: 104, height: 16)
            context.fill(Path(roundedRect: timeBox, cornerRadius: 2), with: .color(BinanceTheme.grid))
            context.draw(Text(timeText).font(.system(size: 10)).foregroundColor(BinanceTheme.primaryText),
                         at: CGPoint(x: timeBox.midX, y: timeBox.midY), anchor: .center)
        }
    }

    private func triangle(tip: CGPoint, pointingUp: Bool) -> Path {
        var path = Path()
        let dy: CGFloat = pointingUp ? 7 : -7
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 5, y: tip.y + dy))
        path.addLine(to: CGPoint(x: tip.x + 5, y: tip.y + dy))
        path.closeSubpath()
        return path
    }

    // MARK: - Header (OHLC + overlay values)

    private func crosshairIndex(layout: Layout) -> Int? {
        guard let point = crosshair, !candles.isEmpty else { return nil }
        let s = scale(layout: layout)
        return min(max(s.index(atX: point.x), 0), candles.count - 1)
    }

    @ViewBuilder
    private func header(layout: Layout) -> some View {
        if let index = crosshairIndex(layout: layout) ?? (candles.isEmpty ? nil : candles.count - 1) {
            let c = candles[index]
            let decimals = Self.decimals(for: c.close)
            let change = c.open == 0 ? 0 : (c.close - c.open) / c.open * 100
            let color = c.close >= c.open ? BinanceTheme.up : BinanceTheme.down
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ohlc("O", c.open, decimals, color)
                    ohlc("H", c.high, decimals, color)
                    ohlc("L", c.low, decimals, color)
                    ohlc("C", c.close, decimals, color)
                    Text(String(format: "%+.2f%%", change)).foregroundColor(color)
                }
                HStack(spacing: 8) {
                    ForEach(overlays.filter { !$0.isHorizontal }.prefix(4)) { line in
                        let value = index < line.values.count ? line.values[index] : .nan
                        Text("\(line.title): \(value.isFinite ? Self.format(value, decimals) : "–")")
                            .foregroundColor(line.color)
                    }
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func ohlc(_ label: String, _ value: Double, _ decimals: Int, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundColor(BinanceTheme.text)
            Text(Self.format(value, decimals)).foregroundColor(color)
        }
    }

    // MARK: - Gestures

    /// One drag gesture for everything: on the price axis it stretches the
    /// price scale, with the crosshair shown it moves the crosshair, otherwise
    /// it scrolls (and, once the price scale is manual, moves prices too).
    private func dragGesture(layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragMode == nil {
                    let range = currentPriceRange(layout: layout)
                    if value.startLocation.x > layout.axisX {
                        dragMode = .axis
                        dragStartRange = range
                    } else if crosshair != nil {
                        dragMode = .crosshair
                    } else if abs(value.translation.width) > abs(value.translation.height) || viewport.manualPriceRange != nil {
                        dragMode = .pan
                        panStartOffset = viewport.rightOffset
                        dragStartRange = viewport.manualPriceRange
                    } else {
                        return   // mostly vertical: leave it to the enclosing scroll view
                    }
                }
                switch dragMode {
                case .axis:
                    guard let range = dragStartRange else { return }
                    // Drag down = wider range (smaller candles), drag up = taller candles.
                    let factor = pow(2, Double(value.translation.height / 120))
                    let mid = (range.lowerBound + range.upperBound) / 2
                    let half = max((range.upperBound - range.lowerBound) / 2 * factor, 1e-9)
                    viewport.manualPriceRange = (mid - half)...(mid + half)
                case .crosshair:
                    crosshair = value.location
                case .pan:
                    let barWidth = layout.plot.width / CGFloat(max(viewport.visibleCount, 1))
                    let offset = panStartOffset + Double(value.translation.width / barWidth)
                    viewport.rightOffset = min(max(offset, 0), Double(max(candles.count - 10, 0)))
                    if let range = dragStartRange {
                        let pricePerPoint = (range.upperBound - range.lowerBound) / Double(max(layout.plot.height, 1))
                        let shift = Double(value.translation.height) * pricePerPoint
                        viewport.manualPriceRange = (range.lowerBound + shift)...(range.upperBound + shift)
                    }
                case nil:
                    break
                }
            }
            .onEnded { _ in
                dragMode = nil
                dragStartRange = nil
            }
    }

    private func currentPriceRange(layout: Layout) -> ClosedRange<Double> {
        let s = scale(layout: layout)
        return s.low...s.high
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStartCount == nil { zoomStartCount = viewport.visibleCount }
                let count = (zoomStartCount ?? 80) / Double(max(value.magnification, 0.1))
                viewport.visibleCount = min(max(count, 15), Double(max(candles.count + 10, 30)), 600)
            }
            .onEnded { _ in zoomStartCount = nil }
    }

    private var crosshairGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    crosshair = drag.location
                }
            }
            .onEnded { _ in pressEndedAt = Date() }
    }

    // MARK: - Formatting

    /// Time left until `close`, like Binance: "mm:ss", "hh:mm:ss" or "1d 04:12".
    static func countdown(until close: Date, now: Date) -> String {
        let seconds = max(0, Int(close.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if days > 0 { return String(format: "%dd %02d:%02d", days, hours, minutes) }
        if hours > 0 { return String(format: "%02d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func decimals(for price: Double) -> Int {
        switch abs(price) {
        case 1000...: return 2
        case 10...: return 3
        case 1...: return 4
        default: return 6
        }
    }

    static func format(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    static func timeFormat(for candles: [Candle]) -> Date.FormatStyle {
        let interval = candles.count > 1 ? candles[candles.count - 1].time.timeIntervalSince(candles[candles.count - 2].time) : 3600
        if interval >= 86_400 { return .dateTime.day(.twoDigits).month(.twoDigits) }
        return .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    }

    private func priceTicks(low: Double, high: Double, count: Int) -> [Double] {
        let span = high - low
        guard span > 0 else { return [low] }
        let raw = span / Double(count)
        let magnitude = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? raw
        var ticks: [Double] = []
        var v = ceil(low / step) * step
        while v <= high {
            ticks.append(v)
            v += step
        }
        return ticks
    }
}

extension ChartMarker {
    /// Entry and exit markers for backtest trades.
    static func from(trades: [Trade]) -> [ChartMarker] {
        trades.flatMap { trade -> [ChartMarker] in
            [ChartMarker(index: trade.entryIndex, price: trade.entryPrice,
                         kind: trade.direction == .long ? .buy : .sell,
                         linkTo: (trade.exitIndex, trade.exitPrice, trade.isWin)),
             ChartMarker(index: trade.exitIndex, price: trade.exitPrice, kind: .exit)]
        }
    }
}

/// A candle chart with a button that opens it full screen (with rotation).
struct ExpandableCandleChart: View {
    var title: String
    let candles: [Candle]
    var overlays: [ChartLine] = []
    var markers: [ChartMarker] = []
    var showVolume = true
    var countdownInterval: TimeInterval?
    @Binding var viewport: ChartViewport

    @State private var fullScreen = false

    var body: some View {
        chart
            .overlay(alignment: .topTrailing) {
                Button {
                    fullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BinanceTheme.text)
                        .frame(width: 34, height: 30)
                }
            }
            .fullScreenCover(isPresented: $fullScreen) {
                FullScreenChart(title: title, onClose: { fullScreen = false }) { chart }
            }
    }

    private var chart: CandleChart {
        CandleChart(candles: candles, overlays: overlays, markers: markers, showVolume: showVolume,
                    countdownInterval: countdownInterval, viewport: $viewport)
    }
}

struct FullScreenChart<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var landscape = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BinanceTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                Button {
                    landscape.toggle()
                    Self.rotate(landscape ? .landscapeRight : .portrait)
                } label: {
                    Image(systemName: "rotate.right")
                }
                Button {
                    Self.rotate(.portrait)
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(BinanceTheme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            content()
        }
        .background(BinanceTheme.background.ignoresSafeArea())
        .statusBarHidden(landscape)
    }

    static func rotate(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
    }
}

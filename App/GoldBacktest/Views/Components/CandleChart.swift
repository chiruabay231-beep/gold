import SwiftUI
import UIKit
import BacktestKit

/// Colours of Binance's dark chart theme (also used for the Live screen chrome).
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

/// Colours of a chart.
struct ChartTheme: Equatable {
    var background: Color
    var panel: Color
    var grid: Color
    var text: Color
    var primaryText: Color
    var up: Color
    var down: Color
    var crosshairLabel: Color
    var accent: Color

    static let binance = ChartTheme(background: BinanceTheme.background, panel: BinanceTheme.panel,
                                    grid: BinanceTheme.grid, text: BinanceTheme.text,
                                    primaryText: BinanceTheme.primaryText, up: BinanceTheme.up,
                                    down: BinanceTheme.down, crosshairLabel: BinanceTheme.grid,
                                    accent: BinanceTheme.yellow)

    /// TradingView's light theme.
    static let tradingView = ChartTheme(background: .white,
                                        panel: Color(red: 0.973, green: 0.976, blue: 0.984),        // #F8F9FD
                                        grid: Color(red: 0.941, green: 0.953, blue: 0.980),         // #F0F3FA
                                        text: Color(red: 0.471, green: 0.482, blue: 0.525),         // #787B86
                                        primaryText: Color(red: 0.075, green: 0.090, blue: 0.133),  // #131722
                                        up: Color(red: 0.031, green: 0.6, blue: 0.506),             // #089981
                                        down: Color(red: 0.949, green: 0.212, blue: 0.271),         // #F23645
                                        crosshairLabel: Color(red: 0.075, green: 0.090, blue: 0.133),
                                        accent: Color(red: 0.161, green: 0.384, blue: 1.0))         // #2962FF

    var isLight: Bool { self == .tradingView }
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

/// How bars are drawn.
enum CandleStyle: String, CaseIterable, Identifiable {
    case candles, hollow, bars, line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .candles: return "Nến"
        case .hollow: return "Nến rỗng"
        case .bars: return "Thanh OHLC"
        case .line: return "Đường"
        }
    }
}

/// A highlighted time window (killzone, ICT macro…) drawn as a box from the
/// window's low to its high.
struct SessionBox: Identifiable {
    enum Style { case filled, dotted }

    var id: String
    var range: ClosedRange<Int>
    var high: Double
    var low: Double
    var label: String
    var color: Color
    var style: Style
    var fillOpacity = 0.10
    var showBorder = false
}

/// A horizontal line between two bars with a small label at its right end;
/// `end == nil` extends to the price axis. Not part of the price auto-scale.
struct ChartSegment {
    var start: Double
    var end: Double?
    var price: Double
    var color: Color
    var width: CGFloat = 1
    var dash: [CGFloat] = []
    var label = ""
}

/// A full-width price line that can be dragged up and down (order entry,
/// stop loss, take profit), like MT5's trade levels.
struct ChartPriceLine {
    var id: String
    var price: Double
    var color: Color
    var label: String
    var dash: [CGFloat] = []
    var draggable = true
    /// Horizontal position of the drag handle, as a fraction of the plot width.
    var handleFraction: CGFloat = 0.5
    /// Running profit shown in a coloured pill after the label (green up, red down).
    var value = ""
    var valueColor: Color?
    /// Bar where the order was filled; drawn as a dot on the line.
    var markerIndex: Int?
}

/// A vertical line at a bar (timestamps).
struct ChartVerticalLine {
    var index: Int
    var color: Color
    var dash: [CGFloat] = [4, 4]
    var label = ""
}

/// Text at the bottom of the plot under a bar (day-of-week labels).
struct ChartNote {
    var index: Int
    var text: String
    var color: Color
}

/// Candlestick chart in the style of Binance / TradingView: MA overlays,
/// volume, right price axis with labels, last price + countdown, session
/// boxes and user drawings. Drag to scroll, pinch to zoom, drag the price
/// axis to stretch prices, hold or tap for the crosshair.
struct CandleChart: View {
    let candles: [Candle]
    var overlays: [ChartLine] = []
    var markers: [ChartMarker] = []
    var showVolume = true
    /// Bar length in seconds; shows a countdown to the close of the last bar.
    var countdownInterval: TimeInterval?
    /// Pan/zoom/crosshair gestures. Off for charts inside scrolling lists,
    /// where they would compete with the list for touches.
    var interactive = true
    var theme: ChartTheme = .binance
    var sessionBoxes: [SessionBox] = []
    var segments: [ChartSegment] = []
    var verticalLines: [ChartVerticalLine] = []
    var notes: [ChartNote] = []
    var priceLines: [ChartPriceLine] = []
    /// A price line was dragged to a price; `true` when the finger lifts.
    var onPriceLineDrag: ((String, Double, Bool) -> Void)?
    /// Labels for the visible high and low on the price axis.
    var showHighLowLabels = false
    var drawings: [Drawing] = []
    /// When set, taps place points of a new drawing of this kind.
    var drawingTool: DrawingTool?
    var selectedDrawingID: UUID?
    var onDrawingCreated: ((Drawing) -> Void)?
    var onDrawingChanged: ((Drawing) -> Void)?
    var onSelectDrawing: ((UUID?) -> Void)?
    var showHeader = true
    var candleStyle: CandleStyle = .candles
    /// Snap new drawing points to the open, high, low or close of the bar.
    var magnet = false
    /// Custom body/border/wick colours; nil = the theme's up/down colours.
    var candleColors: CandleColors?
    /// Fixed number of decimals for prices; nil = automatic.
    var priceDecimals: Int?
    var timeZone: TimeZone = .current
    /// When true no drawing can be moved.
    var drawingsLocked = false
    /// Shows the lot size on long/short position drawings.
    var positionSizing: PositionSizing?
    @Binding var viewport: ChartViewport

    private enum DragMode { case pan, axis, crosshair, moveDrawing, moveHandle, create, priceLine }

    @State private var dragMode: DragMode?
    @State private var panStartOffset: Double = 0
    @State private var dragStartRange: ClosedRange<Double>?
    @State private var zoomStartCount: Double?
    @State private var crosshair: CGPoint?
    @State private var pressEndedAt = Date.distantPast
    @State private var pendingPoints: [ChartPoint] = []
    @State private var movingOriginal: Drawing?
    @State private var movingPreview: Drawing?
    /// Drawing being dragged out with the active tool.
    @State private var creatingPreview: Drawing?
    /// Finger position while creating or reshaping, shown as a guide.
    @State private var guidePoint: CGPoint?
    /// Handle of the selected drawing being dragged (2 = position target).
    @State private var handleIndex: Int?
    /// Price line being dragged and its latest price.
    @State private var draggedLine: (id: String, price: Double)?

    private let axisWidth: CGFloat = 66
    private let timeAxisHeight: CGFloat = 18

    private var headerHeight: CGFloat { showHeader ? 34 : 4 }

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
                if showHeader {
                    header(layout: layout)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }
            }
            .background(theme.background)
            .contentShape(Rectangle())
            .modifier(ChartGestures(enabled: interactive) { content in
                content
                    .simultaneousGesture(dragGesture(layout: layout))
                    .simultaneousGesture(zoomGesture)
                    .simultaneousGesture(crosshairGesture)
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                        // Double tap on the price axis: back to auto-fit.
                        if value.location.x > layout.axisX { viewport.manualPriceRange = nil }
                    })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        handleTap(at: value.location, layout: layout)
                    })
            })
        }
        .onChange(of: candles.count) { oldCount, newCount in
            // Keep the same bars on screen when scrolled back and a new bar arrives.
            if viewport.rightOffset > 0.5, newCount > oldCount, oldCount > 0 {
                viewport.rightOffset += Double(newCount - oldCount)
            }
        }
        .onChange(of: drawingTool) { _, _ in pendingPoints = [] }
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
            let volumeHeight = showVolume ? usable * 0.18 : 0
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

        func x(_ index: Int) -> CGFloat { x(Double(index)) }
        func x(_ index: Double) -> CGFloat { CGFloat(index - start + 0.5) * barWidth }
        func y(_ price: Double) -> CGFloat {
            guard high > low else { return plot.midY }
            return plot.maxY - CGFloat((price - low) / (high - low)) * plot.height
        }
        func price(atY y: CGFloat) -> Double {
            low + Double((plot.maxY - y) / plot.height) * (high - low)
        }
        func index(atX x: CGFloat) -> Int { Int(floor(Double(x / barWidth) + start)) }
        func fractionalIndex(atX x: CGFloat) -> Double { Double(x / barWidth) + start - 0.5 }
        var pricePerPoint: Double { (high - low) / Double(max(plot.height, 1)) }
    }

    private func scale(layout: Layout) -> Scale {
        let (start, _) = viewport.bounds(total: candles.count)
        let barWidth = layout.plot.width / CGFloat(max(viewport.visibleCount, 1))
        if let manual = viewport.manualPriceRange {
            return Scale(start: start, barWidth: barWidth, low: manual.lowerBound, high: manual.upperBound, plot: layout.plot)
        }
        var low = Double.infinity, high = -Double.infinity
        let range = viewport.range(total: candles.count)
        for i in range {
            low = min(low, candles[i].low)
            high = max(high, candles[i].high)
        }
        let candleLow = low, candleHigh = high
        for line in overlays where !line.isHorizontal && !line.axisLabel {
            for i in range where i < line.values.count {
                let v = line.values[i]
                // Skip lines far from price (e.g. a 0/1 flag) so candles stay readable.
                if v.isFinite, v > candleLow * 0.8, v < candleHigh * 1.2 {
                    low = min(low, v)
                    high = max(high, v)
                }
            }
        }
        if !low.isFinite || !high.isFinite { low = 0; high = 1 }
        if low == high { low -= 1; high += 1 }
        let pad = (high - low) * 0.08
        return Scale(start: start, barWidth: barWidth, low: low - pad, high: high + pad, plot: layout.plot)
    }

    // MARK: - Time ↔ bar index

    private var barInterval: TimeInterval {
        guard candles.count > 1 else { return 60 }
        let d = candles[candles.count - 1].time.timeIntervalSince(candles[candles.count - 2].time)
        return d > 0 ? d : 60
    }

    /// Fractional bar index of a time; extrapolates past either end.
    private func index(for time: Date) -> Double {
        guard let first = candles.first, let last = candles.last else { return 0 }
        if time >= last.time { return Double(candles.count - 1) + time.timeIntervalSince(last.time) / barInterval }
        if time <= first.time { return time.timeIntervalSince(first.time) / barInterval }
        var lo = 0, hi = candles.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if candles[mid].time <= time { lo = mid } else { hi = mid - 1 }
        }
        let next = lo + 1 < candles.count ? candles[lo + 1].time : candles[lo].time.addingTimeInterval(barInterval)
        let span = next.timeIntervalSince(candles[lo].time)
        let fraction = span > 0 ? time.timeIntervalSince(candles[lo].time) / span : 0
        return Double(lo) + min(max(fraction, 0), 1)
    }

    private func time(forIndex index: Double) -> Date {
        guard let first = candles.first, let last = candles.last else { return Date() }
        let lastIndex = Double(candles.count - 1)
        if index >= lastIndex { return last.time.addingTimeInterval((index - lastIndex) * barInterval) }
        if index <= 0 { return first.time.addingTimeInterval(index * barInterval) }
        let lower = Int(floor(index))
        let fraction = index - Double(lower)
        return candles[lower].time.addingTimeInterval(fraction * candles[lower + 1].time.timeIntervalSince(candles[lower].time))
    }

    private func chartPoint(at location: CGPoint, layout: Layout) -> ChartPoint {
        let s = scale(layout: layout)
        // Snap to the nearest bar like TradingView.
        let index = s.fractionalIndex(atX: location.x).rounded()
        var price = s.price(atY: location.y)
        if magnet, let bar = Int(exactly: index), candles.indices.contains(bar) {
            let c = candles[bar]
            let nearest = [c.open, c.high, c.low, c.close].min { abs(s.y($0) - location.y) < abs(s.y($1) - location.y) }!
            if abs(s.y(nearest) - location.y) < 28 { price = nearest }
        }
        return ChartPoint(time: time(forIndex: index), price: price)
    }

    /// Screen position of a chart point (after magnet snapping).
    private func screenPoint(_ point: ChartPoint, layout: Layout) -> CGPoint {
        let s = scale(layout: layout)
        return CGPoint(x: s.x(index(for: point.time)), y: s.y(point.price))
    }

    /// A new drawing from its defining points; positions get the stop on the losing side.
    private func makeDrawing(_ tool: DrawingTool, points: [ChartPoint]) -> Drawing {
        var drawing = Drawing(tool: tool, points: points)
        if tool == .longPosition || tool == .shortPosition, points.count > 1 {
            let entry = points[0].price
            var distance = abs(points[1].price - entry)
            if distance == 0 { distance = max(abs(entry) * 0.001, 1e-6) }
            drawing.points[1].price = tool == .longPosition ? entry - distance : entry + distance
        }
        return drawing
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, layout: Layout, now: Date) {
        guard !candles.isEmpty else { return }
        let s = scale(layout: layout)
        let range = viewport.range(total: candles.count)
        let ticks = priceTicks(low: s.low, high: s.high, count: 6)
        let decimals = priceDecimals ?? Self.decimals(for: s.high)

        // Grid and price axis.
        for tick in ticks {
            let y = s.y(tick)
            guard y > layout.plot.minY + 6, y < layout.plot.maxY - 4 else { continue }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: layout.axisX, y: y))
            context.stroke(line, with: .color(theme.grid), lineWidth: theme.isLight ? 1 : 0.5)
            context.draw(Text(Self.format(tick, decimals)).font(.system(size: 10)).foregroundColor(theme.text),
                         at: CGPoint(x: layout.axisX + 5, y: y), anchor: .leading)
        }
        let timeStep = max(1, Int(Double(range.count) / 4))
        var timeFormat = Self.timeFormat(for: candles)
        timeFormat.timeZone = timeZone
        for i in range where (i - range.lowerBound) % timeStep == timeStep / 2 {
            let x = s.x(i)
            var line = Path()
            line.move(to: CGPoint(x: x, y: layout.plot.minY))
            line.addLine(to: CGPoint(x: x, y: layout.volume.maxY))
            context.stroke(line, with: .color(theme.grid), lineWidth: theme.isLight ? 1 : 0.5)
            context.draw(Text(candles[i].time.formatted(timeFormat)).font(.system(size: 10)).foregroundColor(theme.text),
                         at: CGPoint(x: x, y: layout.timeAxis.midY), anchor: .center)
        }
        var separator = Path()
        separator.move(to: CGPoint(x: layout.axisX, y: layout.plot.minY))
        separator.addLine(to: CGPoint(x: layout.axisX, y: layout.timeAxis.minY))
        context.stroke(separator, with: .color(theme.grid), lineWidth: 1)

        var plotContext = context
        plotContext.clip(to: Path(layout.plot))

        // Session boxes (behind candles).
        for box in sessionBoxes where box.range.upperBound >= range.lowerBound && box.range.lowerBound < range.upperBound {
            let rect = CGRect(x: s.x(box.range.lowerBound) - s.barWidth / 2, y: s.y(box.high),
                              width: s.x(box.range.upperBound) - s.x(box.range.lowerBound) + s.barWidth,
                              height: max(2, s.y(box.low) - s.y(box.high)))
            switch box.style {
            case .filled:
                plotContext.fill(Path(rect), with: .color(box.color.opacity(box.fillOpacity)))
                if box.showBorder {
                    plotContext.stroke(Path(rect), with: .color(box.color.opacity(0.7)), lineWidth: 1)
                }
            case .dotted:
                plotContext.stroke(Path(rect), with: .color(box.color.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if !box.label.isEmpty {
                plotContext.draw(Text(box.label).font(.system(size: 9)).foregroundColor(box.color),
                                 at: CGPoint(x: rect.minX + 2, y: rect.minY - 7), anchor: .leading)
            }
        }

        // Timestamps, segments (pivots, opens) and notes, behind the candles.
        for line in verticalLines where range.contains(line.index) {
            let x = s.x(line.index) - s.barWidth / 2
            var path = Path()
            path.move(to: CGPoint(x: x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: x, y: layout.plot.maxY))
            plotContext.stroke(path, with: .color(line.color), style: StrokeStyle(lineWidth: 1, dash: line.dash))
            if !line.label.isEmpty {
                plotContext.draw(Text(line.label).font(.system(size: 9)).foregroundColor(line.color),
                                 at: CGPoint(x: x + 3, y: layout.plot.minY + 8), anchor: .leading)
            }
        }
        for segment in segments {
            let startX = s.x(segment.start)
            let endX = segment.end.map { s.x($0) } ?? layout.axisX
            guard endX >= 0, startX <= layout.axisX else { continue }
            let y = s.y(segment.price)
            var path = Path()
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            plotContext.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.width, dash: segment.dash))
            if !segment.label.isEmpty {
                let labelX = min(endX, layout.axisX - 4)
                plotContext.draw(Text(segment.label).font(.system(size: 9, weight: .medium)).foregroundColor(segment.color),
                                 at: CGPoint(x: labelX, y: y - 6), anchor: .trailing)
            }
        }
        for note in notes where range.contains(note.index) {
            plotContext.draw(Text(note.text).font(.system(size: 10, weight: .medium)).foregroundColor(note.color),
                             at: CGPoint(x: s.x(note.index), y: layout.plot.maxY - 8), anchor: .center)
        }

        // Volume.
        if showVolume, layout.volume.height > 0 {
            let maxVolume = range.map { candles[$0].volume }.max() ?? 0
            if maxVolume > 0 {
                for i in range {
                    let c = candles[i]
                    let h = CGFloat(c.volume / maxVolume) * (layout.volume.height - 4)
                    let rect = CGRect(x: s.x(i) - s.barWidth * 0.35, y: layout.volume.maxY - h,
                                      width: max(1, s.barWidth * 0.7), height: h)
                    context.fill(Path(rect), with: .color((c.close >= c.open ? theme.up : theme.down).opacity(0.4)))
                }
            }
        }

        drawCandles(in: &plotContext, range: range, s: s)

        // Overlays.
        var axisLabels: [AxisLabel] = []
        for line in overlays {
            if line.isHorizontal {
                guard let v = line.values.first(where: \.isFinite) else { continue }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: s.y(v)))
                path.addLine(to: CGPoint(x: layout.axisX, y: s.y(v)))
                plotContext.stroke(path, with: .color(theme.text), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
            plotContext.stroke(path, with: .color(line.color),
                               style: line.axisLabel ? StrokeStyle(lineWidth: 1, dash: [5, 3]) : StrokeStyle(lineWidth: 1.2))
            if line.axisLabel, let value = line.values.last(where: \.isFinite) {
                axisLabels.append(AxisLabel(price: value, text: Self.format(value, decimals), tag: line.title,
                                            color: line.color, textColor: .white))
            }
        }

        // Trade / signal markers.
        for marker in markers where range.contains(marker.index) || (marker.linkTo.map { range.contains($0.index) } ?? false) {
            if let link = marker.linkTo {
                var path = Path()
                path.move(to: CGPoint(x: s.x(marker.index), y: s.y(marker.price)))
                path.addLine(to: CGPoint(x: s.x(link.index), y: s.y(link.price)))
                plotContext.stroke(path, with: .color((link.isWin ? theme.up : theme.down).opacity(0.8)),
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            guard range.contains(marker.index) else { continue }
            let x = s.x(marker.index)
            let c = candles[marker.index]
            switch marker.kind {
            case .buy:
                let tip = CGPoint(x: x, y: s.y(c.low) + 4)
                plotContext.fill(triangle(tip: tip, pointingUp: true), with: .color(theme.up))
                plotContext.draw(Text("B").font(.system(size: 9, weight: .bold)).foregroundColor(theme.up),
                                 at: CGPoint(x: x, y: tip.y + 16), anchor: .center)
            case .sell:
                let tip = CGPoint(x: x, y: s.y(c.high) - 4)
                plotContext.fill(triangle(tip: tip, pointingUp: false), with: .color(theme.down))
                plotContext.draw(Text("S").font(.system(size: 9, weight: .bold)).foregroundColor(theme.down),
                                 at: CGPoint(x: x, y: tip.y - 16), anchor: .center)
            case .exit:
                let rect = CGRect(x: x - 3, y: s.y(marker.price) - 3, width: 6, height: 6)
                plotContext.stroke(Path(ellipseIn: rect), with: .color(theme.primaryText), lineWidth: 1.2)
            }
        }

        // User drawings.
        for original in drawings {
            let drawingToShow = movingPreview?.id == original.id ? movingPreview! : original
            drawDrawing(drawingToShow, in: &plotContext, s: s, layout: layout, decimals: decimals,
                        selected: drawingToShow.id == selectedDrawingID, axisLabels: &axisLabels)
        }
        if let preview = creatingPreview {
            drawDrawing(preview, in: &plotContext, s: s, layout: layout, decimals: decimals,
                        selected: true, axisLabels: &axisLabels)
        }
        for point in pendingPoints {
            let center = CGPoint(x: s.x(index(for: point.time)), y: s.y(point.price))
            plotContext.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                             with: .color(theme.accent))
        }
        // Guide lines under the finger while drawing, since the finger hides the point.
        if let guide = guidePoint {
            var path = Path()
            path.move(to: CGPoint(x: guide.x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: guide.x, y: layout.plot.maxY))
            path.move(to: CGPoint(x: 0, y: guide.y))
            path.addLine(to: CGPoint(x: layout.axisX, y: guide.y))
            plotContext.stroke(path, with: .color(theme.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            let price = s.price(atY: guide.y)
            axisLabels.append(AxisLabel(price: price, text: Self.format(price, decimals), tag: "",
                                        color: theme.accent, textColor: .white))
        }

        // Visible high / low.
        if showHighLowLabels, !range.isEmpty {
            let high = range.map { candles[$0].high }.max() ?? 0
            let low = range.map { candles[$0].low }.min() ?? 0
            axisLabels.append(AxisLabel(price: high, text: Self.format(high, decimals), tag: "Cao",
                                        color: theme.isLight ? Color(red: 0.89, green: 0.93, blue: 1) : theme.grid,
                                        textColor: theme.primaryText))
            axisLabels.append(AxisLabel(price: low, text: Self.format(low, decimals), tag: "Thấp",
                                        color: theme.isLight ? Color(red: 0.89, green: 0.93, blue: 1) : theme.grid,
                                        textColor: theme.primaryText))
        }

        // Trade levels: full-width lines with a handle, a label and a price on the axis.
        for line in priceLines {
            let y = s.y(line.price)
            guard y >= layout.plot.minY - 1, y <= layout.plot.maxY + 1 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: layout.axisX, y: y))
            context.stroke(path, with: .color(line.color), style: StrokeStyle(lineWidth: 1.2, dash: line.dash))
            let label = context.resolve(Text(line.label).font(.system(size: 11, weight: .semibold)).foregroundColor(line.color))
            let labelSize = label.measure(in: CGSize(width: 400, height: 40))
            context.draw(label, at: CGPoint(x: 6, y: y - 9), anchor: .leading)
            if !line.value.isEmpty {
                let valueColor = line.valueColor ?? line.color
                let text = context.resolve(Text(line.value).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundColor(.white))
                let size = text.measure(in: CGSize(width: 400, height: 40))
                let pill = CGRect(x: 6 + labelSize.width + 6, y: y - 9 - size.height / 2 - 2, width: size.width + 10, height: size.height + 4)
                context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(valueColor))
                context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
            }
            if let index = line.markerIndex, range.contains(index) {
                // Entry point on the candle where the order filled.
                let dot = CGRect(x: s.x(index) - 5, y: y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dot), with: .color(line.color))
                context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 1.5)
            }
            if line.draggable {
                let center = CGPoint(x: layout.plot.width * line.handleFraction, y: y)
                let handle = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: handle), with: .color(theme.background))
                context.stroke(Path(ellipseIn: handle), with: .color(line.color), lineWidth: 2.5)
            }
            axisLabels.append(AxisLabel(price: line.price, text: Self.format(line.price, decimals), tag: "",
                                        color: line.color, textColor: .white))
        }

        // Axis labels, nudged apart so they don't overlap.
        let placed = Self.spread(axisLabels.map { (label: $0, y: s.y($0.price)) }, minGap: 17,
                                 bounds: (layout.plot.minY + 8)...(layout.plot.maxY - 8))
        for (label, y) in placed {
            let box = CGRect(x: layout.axisX + 1, y: y - 8, width: axisWidth - 2, height: 16)
            context.fill(Path(roundedRect: box, cornerRadius: 2), with: .color(label.color))
            context.draw(Text(label.text).font(.system(size: 10, weight: .medium)).foregroundColor(label.textColor),
                         at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            if !label.tag.isEmpty {
                let tagText = Text(label.tag).font(.system(size: 10)).foregroundColor(label.textColor)
                let width = CGFloat(label.tag.count) * 6 + 10
                let tag = CGRect(x: layout.axisX - width - 2, y: y - 8, width: width, height: 16)
                context.fill(Path(roundedRect: tag, cornerRadius: 3), with: .color(label.color.opacity(0.85)))
                context.draw(tagText, at: CGPoint(x: tag.midX, y: tag.midY), anchor: .center)
            }
        }

        // Last price line and label.
        if let last = candles.last {
            let y = s.y(last.close)
            let color = last.close >= last.open ? theme.up : theme.down
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
            context.stroke(path, with: .color(theme.text.opacity(0.8)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            let priceBox = CGRect(x: layout.axisX + 1, y: y - 8, width: axisWidth - 2, height: 16)
            context.fill(Path(roundedRect: priceBox, cornerRadius: 2), with: .color(theme.crosshairLabel))
            context.draw(Text(Self.format(s.price(atY: y), decimals)).font(.system(size: 10)).foregroundColor(.white),
                         at: CGPoint(x: priceBox.midX, y: priceBox.midY), anchor: .center)
            var crosshairFormat = Date.FormatStyle.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits).hour().minute()
            if barInterval < 60 { crosshairFormat = crosshairFormat.second(.twoDigits) }
            crosshairFormat.timeZone = timeZone
            let timeText = candles[index].time.formatted(crosshairFormat)
            let timeBox = CGRect(x: x - 60, y: layout.timeAxis.minY + 1, width: 120, height: 16)
            context.fill(Path(roundedRect: timeBox, cornerRadius: 2), with: .color(theme.crosshairLabel))
            context.draw(Text(timeText).font(.system(size: 10)).foregroundColor(.white),
                         at: CGPoint(x: timeBox.midX, y: timeBox.midY), anchor: .center)
        }
    }

    private struct AxisLabel {
        var price: Double
        var text: String
        var tag: String
        var color: Color
        var textColor: Color
    }

    /// Moves labels vertically so none are closer than `minGap`.
    private static func spread(_ items: [(label: AxisLabel, y: CGFloat)], minGap: CGFloat,
                               bounds: ClosedRange<CGFloat>) -> [(AxisLabel, CGFloat)] {
        var sorted = items.sorted { $0.y < $1.y }.map { ($0.label, min(max($0.y, bounds.lowerBound), bounds.upperBound)) }
        guard sorted.count > 1 else { return sorted }
        for i in 1..<sorted.count where sorted[i].1 - sorted[i - 1].1 < minGap {
            sorted[i].1 = sorted[i - 1].1 + minGap
        }
        return sorted
    }

    private func drawDrawing(_ d: Drawing, in context: inout GraphicsContext, s: Scale, layout: Layout,
                             decimals: Int, selected: Bool, axisLabels: inout [AxisLabel]) {
        let color = d.color
        let width = CGFloat(d.lineWidth) + (selected ? 0.8 : 0)
        let stroke = StrokeStyle(lineWidth: width, lineCap: d.lineStyle == .dotted ? .round : .butt, dash: d.lineStyle.dash)
        let points = d.points.map { CGPoint(x: s.x(index(for: $0.time)), y: s.y($0.price)) }
        guard let p0 = points.first else { return }
        func label(_ text: String, at point: CGPoint, anchor: UnitPoint = .leading, color labelColor: Color? = nil) {
            guard !text.isEmpty else { return }
            context.draw(Text(text).font(.system(size: 10, weight: .semibold)).foregroundColor(labelColor ?? color),
                         at: point, anchor: anchor)
        }
        switch d.tool {
        case .horizontalLine, .horizontalRay:
            var path = Path()
            path.move(to: CGPoint(x: d.tool == .horizontalRay ? p0.x : 0, y: p0.y))
            path.addLine(to: CGPoint(x: layout.axisX, y: p0.y))
            context.stroke(path, with: .color(color), style: stroke)
            axisLabels.append(AxisLabel(price: d.points[0].price, text: Self.format(d.points[0].price, decimals),
                                        tag: d.text, color: color, textColor: .white))
        case .verticalLine:
            var path = Path()
            path.move(to: CGPoint(x: p0.x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: p0.x, y: layout.plot.maxY))
            context.stroke(path, with: .color(color), style: stroke)
            label(d.text, at: CGPoint(x: p0.x + 4, y: layout.plot.minY + 10))
        case .trendLine, .trendRay:
            guard points.count > 1 else { break }
            var end = points[1]
            if d.tool == .trendRay {
                // Extend through the second point to the edge of the plot.
                let dx = end.x - p0.x, dy = end.y - p0.y
                let length = max(hypot(dx, dy), 0.001)
                let reach = (layout.plot.width + layout.plot.height) * 2
                end = CGPoint(x: p0.x + dx / length * reach, y: p0.y + dy / length * reach)
            }
            var path = Path()
            path.move(to: p0)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: stroke)
            label(d.text, at: CGPoint(x: points[1].x + 6, y: points[1].y))
        case .rectangle:
            guard points.count > 1 else { break }
            let rect = CGRect(x: min(p0.x, points[1].x), y: min(p0.y, points[1].y),
                              width: abs(points[1].x - p0.x), height: abs(points[1].y - p0.y))
            context.fill(Path(rect), with: .color(color.opacity(0.15)))
            context.stroke(Path(rect), with: .color(color), style: stroke)
            label(d.text, at: CGPoint(x: rect.minX + 4, y: rect.minY + 9))
        case .fibRetracement:
            guard points.count > 1 else { break }
            let left = min(p0.x, points[1].x)
            let right = max(max(p0.x, points[1].x), left + s.barWidth * 12)
            if let top = d.fibPrice(0.62), let bottom = d.fibPrice(0.79) {
                let y1 = s.y(top), y2 = s.y(bottom)
                let zone = CGRect(x: left, y: min(y1, y2), width: right - left, height: abs(y2 - y1))
                context.fill(Path(zone), with: .color(DrawingPalette.colors[3].opacity(0.16)))
            }
            for level in Drawing.fibLevels {
                guard let price = d.fibPrice(level) else { continue }
                let y = s.y(price)
                let levelColor: Color = level == 0 || level == 1 ? color
                    : (level < 0 ? theme.up : (level >= 0.62 && level <= 0.79 ? DrawingPalette.colors[3] : color))
                var path = Path()
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: right, y: y))
                context.stroke(path, with: .color(levelColor), lineWidth: level == 0.705 ? 1.4 : 1)
                let name = level == 0.705 ? "0.705 OTE" : String(format: "%g", level)
                label("\(name) (\(Self.format(price, decimals)))", at: CGPoint(x: left + 3, y: y - 6), color: levelColor)
            }
            var diagonal = Path()
            diagonal.move(to: p0)
            diagonal.addLine(to: points[1])
            context.stroke(diagonal, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .priceRange:
            guard points.count > 1 else { break }
            let rect = CGRect(x: min(p0.x, points[1].x), y: min(p0.y, points[1].y),
                              width: abs(points[1].x - p0.x), height: abs(points[1].y - p0.y))
            let change = d.points[1].price - d.points[0].price
            let rangeColor = change >= 0 ? theme.up : theme.down
            context.fill(Path(rect), with: .color(rangeColor.opacity(0.14)))
            var arrow = Path()
            arrow.move(to: CGPoint(x: rect.midX, y: p0.y))
            arrow.addLine(to: CGPoint(x: rect.midX, y: points[1].y))
            context.stroke(arrow, with: .color(rangeColor), lineWidth: 1.2)
            context.fill(triangle(tip: CGPoint(x: rect.midX, y: points[1].y), pointingUp: change >= 0), with: .color(rangeColor))
            let bars = Int((index(for: d.points[1].time) - index(for: d.points[0].time)).rounded())
            let seconds = abs(d.points[1].time.timeIntervalSince(d.points[0].time))
            let percent = d.points[0].price != 0 ? change / d.points[0].price * 100 : 0
            let text = "\(change >= 0 ? "+" : "")\(Self.format(change, decimals)) (\(String(format: "%+.2f", percent))%) · \(abs(bars)) nến · \(Self.duration(seconds))"
            let labelY = change >= 0 ? rect.minY - 10 : rect.maxY + 10
            let textView = Text(text).font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
            let size = context.resolve(textView).measure(in: CGSize(width: 400, height: 30))
            let box = CGRect(x: rect.midX - size.width / 2 - 5, y: labelY - size.height / 2 - 3,
                             width: size.width + 10, height: size.height + 6)
            context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(rangeColor))
            context.draw(textView, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        case .longPosition, .shortPosition:
            guard let levels = d.positionLevels, points.count > 1 else { break }
            let left = min(p0.x, points[1].x)
            let right = max(max(p0.x, points[1].x), left + s.barWidth * 20)
            let entryY = s.y(levels.entry), stopY = s.y(levels.stop), targetY = s.y(levels.target)
            let profit = CGRect(x: left, y: min(entryY, targetY), width: right - left, height: abs(targetY - entryY))
            let loss = CGRect(x: left, y: min(entryY, stopY), width: right - left, height: abs(stopY - entryY))
            context.fill(Path(profit), with: .color(theme.up.opacity(0.22)))
            context.fill(Path(loss), with: .color(theme.down.opacity(0.22)))
            var entryLine = Path()
            entryLine.move(to: CGPoint(x: left, y: entryY))
            entryLine.addLine(to: CGPoint(x: right, y: entryY))
            context.stroke(entryLine, with: .color(theme.primaryText.opacity(0.7)), lineWidth: selected ? 2 : 1)
            let risk = abs(levels.entry - levels.stop)
            let reward = abs(levels.target - levels.entry)
            let targetText = "TP \(Self.format(levels.target, decimals)) (+\(Self.format(reward, decimals))) · RR \(String(format: "%.1f", d.riskReward))"
            let stopText = "SL \(Self.format(levels.stop, decimals)) (−\(Self.format(risk, decimals)))"
            label(targetText, at: CGPoint(x: left + 4, y: targetY + (targetY < entryY ? 8 : -8)), color: theme.up)
            if let lots = positionSizing?.lots(entry: levels.entry, stop: levels.stop) {
                label("Lot \(String(format: lots < 1 ? "%.2f" : "%.1f", lots))", at: CGPoint(x: left + 4, y: entryY - 8),
                      color: theme.primaryText)
            }
            label(stopText, at: CGPoint(x: left + 4, y: stopY + (stopY < entryY ? 8 : -8)), color: theme.down)
            label("Vào \(Self.format(levels.entry, decimals))", at: CGPoint(x: right - 4, y: entryY - 8), anchor: .trailing,
                  color: theme.primaryText)
        case .text:
            let text = d.text.isEmpty ? "Ghi chú" : d.text
            context.draw(Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(color),
                         at: p0, anchor: .leading)
        }
        if selected {
            for p in handlePoints(of: d, s: s) {
                let handle = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: handle), with: .color(theme.background))
                context.stroke(Path(ellipseIn: handle), with: .color(color), lineWidth: 2)
            }
        }
    }

    /// Draggable points of a drawing on screen; for positions the target is the third.
    private func handlePoints(of d: Drawing, s: Scale) -> [CGPoint] {
        var points = d.points.map { CGPoint(x: s.x(index(for: $0.time)), y: s.y($0.price)) }
        if let levels = d.positionLevels, points.count > 1 {
            points.append(CGPoint(x: points[1].x, y: s.y(levels.target)))
        }
        return points
    }

    /// Bars of OHLC data in the chosen style. Wicks are snapped to device
    /// pixels so they stay sharp and visible at every zoom level.
    private func drawCandles(in context: inout GraphicsContext, range: Range<Int>, s: Scale) {
        let pixel = 1 / max(context.environment.displayScale, 1)
        func snap(_ v: CGFloat) -> CGFloat { (v / pixel).rounded() * pixel }
        let wickWidth: CGFloat = s.barWidth >= 16 ? 1.5 : 1
        let bodyWidth = max(pixel, snap(s.barWidth * 0.72))
        if candleStyle == .line {
            var path = Path()
            for i in range {
                let point = CGPoint(x: s.x(i), y: s.y(candles[i].close))
                if i == range.lowerBound { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(theme.accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            return
        }
        let colors = candleColors ?? CandleColors.standard(for: theme)
        let upBody = colors.upBody.color, downBody = colors.downBody.color
        let upBorder = colors.upBorder.color, downBorder = colors.downBorder.color
        let upWick = colors.upWick.color, downWick = colors.downWick.color
        for i in range {
            let c = candles[i]
            let reference = colors.colorByPreviousClose && i > 0 ? candles[i - 1].close : c.open
            let isUp = c.close >= reference
            let color = isUp ? upBody : downBody
            let wickColor = isUp ? upWick : downWick
            let borderColor = isUp ? upBorder : downBorder
            let x = snap(s.x(i))
            let highY = s.y(c.high), lowY = s.y(c.low)
            let top = s.y(max(c.open, c.close)), bottom = s.y(min(c.open, c.close))
            if candleStyle == .bars {
                var bar = Path()
                bar.move(to: CGPoint(x: x, y: highY))
                bar.addLine(to: CGPoint(x: x, y: lowY))
                let tick = max(2, bodyWidth / 2)
                bar.move(to: CGPoint(x: x - tick, y: s.y(c.open)))
                bar.addLine(to: CGPoint(x: x, y: s.y(c.open)))
                bar.move(to: CGPoint(x: x, y: s.y(c.close)))
                bar.addLine(to: CGPoint(x: x + tick, y: s.y(c.close)))
                context.stroke(bar, with: .color(color), lineWidth: max(1, wickWidth))
                continue
            }
            // Upper and lower wick as separate segments so hollow bodies stay empty.
            if colors.showWick {
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: highY))
                wick.addLine(to: CGPoint(x: x, y: top))
                wick.move(to: CGPoint(x: x, y: bottom))
                wick.addLine(to: CGPoint(x: x, y: lowY))
                context.stroke(wick, with: .color(wickColor), lineWidth: wickWidth)
            }
            // Very narrow bars are just the high–low line, like TradingView when zoomed out.
            guard s.barWidth >= 2.5 else {
                var line = Path()
                line.move(to: CGPoint(x: x, y: top))
                line.addLine(to: CGPoint(x: x, y: max(bottom, top + pixel)))
                context.stroke(line, with: .color(colors.showBody ? color : borderColor), lineWidth: wickWidth)
                continue
            }
            let body = CGRect(x: x - bodyWidth / 2, y: snap(top), width: bodyWidth,
                              height: max(pixel * 2, snap(bottom) - snap(top)))
            let hollow = candleStyle == .hollow && isUp
            if hollow {
                context.fill(Path(body), with: .color(theme.background))
            } else if colors.showBody {
                context.fill(Path(body), with: .color(color))
            }
            if colors.showBorder || hollow {
                context.stroke(Path(body.insetBy(dx: 0.5, dy: 0.5)),
                               with: .color(colors.showBorder ? borderColor : color), lineWidth: 1)
            }
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

    // MARK: - Hit testing

    private func hitDrawing(at location: CGPoint, layout: Layout) -> Drawing? {
        let s = scale(layout: layout)
        let tolerance: CGFloat = 16
        for d in drawings.reversed() {
            let points = d.points.map { CGPoint(x: s.x(index(for: $0.time)), y: s.y($0.price)) }
            guard let p0 = points.first else { continue }
            if handlePoints(of: d, s: s).contains(where: { hypot($0.x - location.x, $0.y - location.y) < tolerance }) {
                return d
            }
            switch d.tool {
            case .horizontalLine:
                if abs(location.y - p0.y) < tolerance { return d }
            case .horizontalRay:
                if abs(location.y - p0.y) < tolerance, location.x > p0.x - tolerance { return d }
            case .verticalLine:
                if abs(location.x - p0.x) < tolerance { return d }
            case .trendLine:
                if points.count > 1, Self.distance(from: location, toSegment: p0, points[1]) < tolerance { return d }
            case .trendRay:
                if points.count > 1 {
                    let dx = points[1].x - p0.x, dy = points[1].y - p0.y
                    let length = max(hypot(dx, dy), 0.001)
                    let reach = (layout.plot.width + layout.plot.height) * 2
                    let end = CGPoint(x: p0.x + dx / length * reach, y: p0.y + dy / length * reach)
                    if Self.distance(from: location, toSegment: p0, end) < tolerance { return d }
                }
            case .rectangle, .priceRange:
                if points.count > 1 {
                    let rect = CGRect(x: min(p0.x, points[1].x), y: min(p0.y, points[1].y),
                                      width: abs(points[1].x - p0.x), height: abs(points[1].y - p0.y))
                    if rect.insetBy(dx: -tolerance, dy: -tolerance).contains(location) { return d }
                }
            case .fibRetracement:
                if points.count > 1 {
                    let left = min(p0.x, points[1].x)
                    let right = max(max(p0.x, points[1].x), left + s.barWidth * 12)
                    let ys = Drawing.fibLevels.compactMap { d.fibPrice($0) }.map { s.y($0) }
                    if location.x > left - tolerance, location.x < right + tolerance,
                       let top = ys.min(), let bottom = ys.max(), location.y > top - tolerance, location.y < bottom + tolerance {
                        return d
                    }
                }
            case .longPosition, .shortPosition:
                if let levels = d.positionLevels, points.count > 1 {
                    let left = min(p0.x, points[1].x)
                    let right = max(max(p0.x, points[1].x), left + s.barWidth * 20)
                    let top = min(s.y(levels.stop), s.y(levels.target))
                    let bottom = max(s.y(levels.stop), s.y(levels.target))
                    if CGRect(x: left, y: top, width: right - left, height: bottom - top).contains(location) { return d }
                }
            case .text:
                if CGRect(x: p0.x - 6, y: p0.y - 14, width: 160, height: 28).contains(location) { return d }
            }
        }
        return nil
    }

    /// The draggable price line nearest to `location`, within a finger's reach.
    private func hitPriceLine(at location: CGPoint, layout: Layout) -> ChartPriceLine? {
        let s = scale(layout: layout)
        return priceLines
            .filter { $0.draggable && abs(s.y($0.price) - location.y) < 16 }
            .min { abs(s.y($0.price) - location.y) < abs(s.y($1.price) - location.y) }
    }

    /// Index of the selected drawing's handle under `location`.
    private func hitHandle(at location: CGPoint, layout: Layout) -> (Drawing, Int)? {
        guard let id = selectedDrawingID, let d = drawings.first(where: { $0.id == id }) else { return nil }
        let s = scale(layout: layout)
        let handles = handlePoints(of: d, s: s)
        guard let nearest = handles.indices.min(by: {
            hypot(handles[$0].x - location.x, handles[$0].y - location.y) < hypot(handles[$1].x - location.x, handles[$1].y - location.y)
        }), hypot(handles[nearest].x - location.x, handles[nearest].y - location.y) < 24 else { return nil }
        return (d, nearest)
    }

    /// Moves one handle of a drawing to `point`, keeping positions consistent.
    private func moving(_ d: Drawing, handle: Int, to point: ChartPoint) -> Drawing {
        var moved = d
        if let levels = d.positionLevels {
            let isLong = d.tool == .longPosition
            switch handle {
            case 0:
                moved.points[0] = point
                // Keep the stop on the losing side of the entry.
                if isLong ? levels.stop >= point.price : levels.stop <= point.price {
                    moved.points[1].price = isLong ? point.price - abs(levels.entry - levels.stop) : point.price + abs(levels.entry - levels.stop)
                }
            case 1:
                let gap = max(abs(levels.entry) * 0.00001, 1e-9)
                moved.points[1] = ChartPoint(time: point.time,
                                             price: isLong ? min(point.price, levels.entry - gap) : max(point.price, levels.entry + gap))
            default:
                let risk = abs(levels.entry - levels.stop)
                let reward = isLong ? point.price - levels.entry : levels.entry - point.price
                if risk > 0 { moved.riskReward = min(max((reward / risk * 10).rounded() / 10, 0.1), 50) }
            }
            return moved
        }
        if handle < moved.points.count { moved.points[handle] = point }
        return moved
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 48 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
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
            let decimals = priceDecimals ?? Self.decimals(for: c.close)
            let change = c.open == 0 ? 0 : (c.close - c.open) / c.open * 100
            let color = c.close >= c.open ? theme.up : theme.down
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ohlc("O", c.open, decimals, color)
                    ohlc("H", c.high, decimals, color)
                    ohlc("L", c.low, decimals, color)
                    ohlc("C", c.close, decimals, color)
                    Text(String(format: "%+.2f%%", change)).foregroundColor(color)
                }
                HStack(spacing: 8) {
                    ForEach(overlays.filter { !$0.isHorizontal && !$0.axisLabel }.prefix(4)) { line in
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
            Text(label).foregroundColor(theme.text)
            Text(Self.format(value, decimals)).foregroundColor(color)
        }
    }

    // MARK: - Gestures

    private func handleTap(at location: CGPoint, layout: Layout) {
        // The release of a long press also ends as a tap; keep that crosshair.
        guard location.x < layout.axisX, Date().timeIntervalSince(pressEndedAt) > 0.3 else { return }
        if let tool = drawingTool {
            // Tapping works too: one tap per point.
            pendingPoints.append(chartPoint(at: location, layout: layout))
            if pendingPoints.count >= tool.pointsNeeded {
                let drawing = makeDrawing(tool, points: pendingPoints)
                pendingPoints = []
                onDrawingCreated?(drawing)
            }
            return
        }
        if let hit = hitDrawing(at: location, layout: layout) {
            onSelectDrawing?(hit.id == selectedDrawingID ? nil : hit.id)
            return
        }
        if selectedDrawingID != nil {
            onSelectDrawing?(nil)
            return
        }
        crosshair = crosshair == nil ? location : nil
    }

    /// One drag gesture for everything: on the price axis it stretches the
    /// price scale, on the selected drawing it moves the drawing, with the
    /// crosshair shown it moves the crosshair, otherwise it scrolls (and, once
    /// the price scale is manual, moves prices too).
    private func dragGesture(layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragMode == nil {
                    let range = currentPriceRange(layout: layout)
                    if value.startLocation.x > layout.axisX {
                        dragMode = .axis
                        dragStartRange = range
                    } else if drawingTool == nil, let line = hitPriceLine(at: value.startLocation, layout: layout) {
                        dragMode = .priceLine
                        draggedLine = (line.id, line.price)
                        crosshair = nil
                    } else if drawingTool != nil {
                        dragMode = .create
                        crosshair = nil
                    } else if !drawingsLocked, let hit = hitHandle(at: value.startLocation, layout: layout), !hit.0.locked {
                        dragMode = .moveHandle
                        movingOriginal = hit.0
                        handleIndex = hit.1
                    } else if !drawingsLocked, let id = selectedDrawingID, let hit = hitDrawing(at: value.startLocation, layout: layout),
                              hit.id == id, !hit.locked {
                        dragMode = .moveDrawing
                        movingOriginal = hit
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
                case .moveDrawing:
                    guard let original = movingOriginal else { return }
                    let s = scale(layout: layout)
                    let barShift = (Double(value.translation.width / s.barWidth)).rounded()
                    let priceShift = -Double(value.translation.height) * s.pricePerPoint
                    var moved = original
                    moved.points = original.points.map { p in
                        ChartPoint(time: time(forIndex: index(for: p.time) + barShift), price: p.price + priceShift)
                    }
                    movingPreview = moved
                case .priceLine:
                    guard let line = draggedLine else { return }
                    let price = scale(layout: layout).price(atY: value.location.y)
                    draggedLine = (line.id, price)
                    onPriceLineDrag?(line.id, price, false)
                case .create:
                    guard let tool = drawingTool else { return }
                    let end = chartPoint(at: value.location, layout: layout)
                    if tool.pointsNeeded == 1 {
                        creatingPreview = makeDrawing(tool, points: [end])
                    } else {
                        let start = pendingPoints.first ?? chartPoint(at: value.startLocation, layout: layout)
                        creatingPreview = makeDrawing(tool, points: [start, end])
                    }
                    guidePoint = screenPoint(end, layout: layout)
                case .moveHandle:
                    guard let original = movingOriginal, let handle = handleIndex else { return }
                    let point = chartPoint(at: value.location, layout: layout)
                    movingPreview = moving(original, handle: handle, to: point)
                    guidePoint = screenPoint(point, layout: layout)
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
                if dragMode == .moveDrawing || dragMode == .moveHandle, let moved = movingPreview {
                    onDrawingChanged?(moved)
                }
                if dragMode == .priceLine, let line = draggedLine {
                    onPriceLineDrag?(line.id, line.price, true)
                }
                draggedLine = nil
                if dragMode == .create, let created = creatingPreview {
                    pendingPoints = []
                    onDrawingCreated?(created)
                }
                creatingPreview = nil
                guidePoint = nil
                handleIndex = nil
                dragMode = nil
                dragStartRange = nil
                movingOriginal = nil
                movingPreview = nil
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
                if drawingTool == nil, dragMode != .moveHandle, dragMode != .moveDrawing, dragMode != .priceLine,
                   case .second(true, let drag?) = value {
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
        if interval < 60 { return .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits) }
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

/// Applies the chart's gestures only when enabled.
private struct ChartGestures<Gestured: View>: ViewModifier {
    let enabled: Bool
    let apply: (AnyView) -> Gestured

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            apply(AnyView(content))
        } else {
            content
        }
    }
}

/// A candle chart with a button that opens it full screen (with rotation).
/// When `interactive` is false (charts inside lists), tapping the chart
/// opens it full screen, where all gestures work.
struct ExpandableCandleChart: View {
    var title: String
    let candles: [Candle]
    var overlays: [ChartLine] = []
    var markers: [ChartMarker] = []
    var showVolume = true
    var countdownInterval: TimeInterval?
    var interactive = true
    @Binding var viewport: ChartViewport

    @State private var fullScreen = false

    var body: some View {
        chart(interactive: interactive)
            .overlay {
                if !interactive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { fullScreen = true }
                }
            }
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
                FullScreenChart(title: title, onClose: { fullScreen = false }) { chart(interactive: true) }
            }
    }

    private func chart(interactive: Bool) -> CandleChart {
        CandleChart(candles: candles, overlays: overlays, markers: markers, showVolume: showVolume,
                    countdownInterval: countdownInterval, interactive: interactive, viewport: $viewport)
    }
}

struct FullScreenChart<Content: View>: View {
    let title: String
    var theme: ChartTheme = .binance
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var landscape = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.primaryText)
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
            .foregroundColor(theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            content()
        }
        .background(theme.background.ignoresSafeArea())
        .statusBarHidden(landscape)
    }

    static func rotate(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
    }
}

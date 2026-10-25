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

    var isLight: Bool { primaryText == ChartTheme.tradingView.primaryText }

    /// The theme with the chart background the user picked (Cài đặt → Màu nền).
    func with(background color: Color?) -> ChartTheme {
        guard let color else { return self }
        var copy = self
        copy.background = color
        return copy
    }
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
    var borderWidth: CGFloat = 1
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
    /// Price at `end` for a sloped line (SMT); nil = horizontal.
    var endPrice: Double? = nil
    /// The label sits in the middle of the line, which breaks around it (FVG).
    var centerLabel = false
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
    /// Shows a ✕ button at the right end of the line (close / cancel).
    var closable = false
}

/// A vertical line at a bar (timestamps).
struct ChartVerticalLine {
    var index: Int
    var color: Color
    var dash: [CGFloat] = [4, 4]
    var label = ""
    var width: CGFloat = 1
}

/// A big player on a bar ("Dòng tiền cá mập"): green under the bar for buying,
/// red above it for selling, bigger for bigger volume.
struct ChartBubble {
    var index: Int
    var buying: Bool
    /// Volume ÷ average volume.
    var ratio: Double
}

/// A moment marked on the time axis (economic news), possibly after the last bar.
struct ChartTimeEvent {
    var time: Date
    var label: String
    var color: Color
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
    /// News flags on the time axis.
    var timeEvents: [ChartTimeEvent] = []
    /// Shark bubbles: a big buyer under the bar, a big seller above it.
    var bubbles: [ChartBubble] = []
    /// Ask price, drawn as a second dotted line above the bid (the spread).
    var askPrice: Double?
    var priceLines: [ChartPriceLine] = []
    /// A price line was dragged to a price; `true` when the finger lifts.
    var onPriceLineDrag: ((String, Double, Bool) -> Void)?
    /// The ✕ of a closable price line was tapped.
    var onPriceLineClose: ((String) -> Void)?
    /// When set, a tap chooses a bar (bar replay start) instead of the usual tap actions.
    var onPickBar: ((Int) -> Void)?
    /// The bar chosen as the replay start: a line after it and the later bars dimmed.
    var pickIndex: Int?
    /// Called when scrolling reaches the oldest bars, to load more history.
    var onNeedOlder: (() -> Void)?
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
    /// A border around the plot (candles, volume): the chart sits in its own frame.
    var framed = false
    /// The crosshair shows only in this mode (Thước ngắm button): a tap places it, a drag moves it.
    var crosshairMode = false
    /// Off for the upper chart of the compare split, so the two frames touch.
    var showTimeAxis = true
    /// The background grid (Cài đặt → Lưới nền).
    var showGrid = true
    /// The OHLC header drawn over the top of the plot instead of above it.
    var headerInside = false
    /// Price axis on the left (left chart of the side-by-side split, so the two frames touch).
    var axisLeading = false
    /// A tap on the chart that hit nothing (no line, drawing or tool): e.g. closes
    /// the pending-order panel.
    var onBackgroundTap: (() -> Void)? = nil
    /// Time of the crosshair shared with another chart (compare split): moving
    /// it here moves the other chart's vertical line too.
    var linkedCrosshair: Binding<Date?>? = nil
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
    /// Order whose lines are shown fully (tapped recently); others are faint.
    @State private var activeLineGroup: String?
    /// Where a long press without moving was released: shows the reset menu there.
    @State private var menuPoint: CGPoint?

    private let axisWidth: CGFloat = 66
    /// Height of a price label on the axis (and of the last price row).
    static let axisLabelHeight: CGFloat = 20
    private var timeAxisHeight: CGFloat { showTimeAxis ? 18 : 0 }

    private var headerHeight: CGFloat { showHeader && !headerInside ? 34 : (headerInside ? 0 : 4) }

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size, axisWidth: axisWidth, timeAxisHeight: timeAxisHeight,
                                headerHeight: headerHeight, showVolume: showVolume)
            ZStack(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: countdownInterval == nil ? 3600 : 1)) { timeline in
                    Canvas { context, size in
                        if axisLeading {
                            // Same drawing, cut in two: the plot moved right of the axis, the axis on the left.
                            var plot = context
                            plot.translateBy(x: axisWidth, y: 0)
                            plot.clip(to: Path(CGRect(x: 0, y: 0, width: layout.axisX, height: size.height)))
                            draw(in: &plot, layout: layout, now: timeline.date)
                            var axis = context
                            axis.translateBy(x: -layout.axisX, y: 0)
                            axis.clip(to: Path(CGRect(x: layout.axisX, y: 0, width: axisWidth, height: size.height)))
                            draw(in: &axis, layout: layout, now: timeline.date, axisOnly: true)
                        } else {
                            draw(in: &context, layout: layout, now: timeline.date)
                        }
                    }
                }
                if showHeader {
                    header(layout: layout)
                        .padding(.horizontal, 6)
                        .padding(.leading, axisLeading ? axisWidth : 0)
                        // Inside the plot: clear of the price axis.
                        .padding(.trailing, headerInside && !axisLeading ? axisWidth : 0)
                        .padding(.top, 2)
                }
                if let point = menuPoint {
                    chartMenu
                        .position(x: min(max(point.x, 110), geometry.size.width - 110),
                                  y: min(max(point.y, 70), geometry.size.height - 70))
                }
            }
            .background(theme.background)
            .contentShape(Rectangle())
            .onChange(of: crosshair) { _, _ in
                guard let linked = linkedCrosshair else { return }
                let time = crosshairIndex(layout: layout, ownOnly: true).map { candles[$0].time }
                if linked.wrappedValue != time { linked.wrappedValue = time }
            }
            .modifier(ChartGestures(enabled: interactive) { content in
                content
                    .simultaneousGesture(dragGesture(layout: layout))
                    .simultaneousGesture(zoomGesture)
                    .simultaneousGesture(crosshairGesture)
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                        // Double tap on the price axis: back to auto-fit.
                        if chartLocation(value.location, layout: layout).x > layout.axisX { viewport.manualPriceRange = nil }
                    })
                    .simultaneousGesture(SpatialTapGesture().onEnded { value in
                        handleTap(at: value.location, layout: layout)
                    })
            })
        }
        .onChange(of: candles.last?.time) { oldTime, newTime in
            // Keep the same bars on screen when scrolled back and a new bar arrives.
            // (Older bars added in front don't move the view: it is anchored at the right.)
            if viewport.rightOffset > 0.5, let oldTime, let newTime, newTime > oldTime {
                viewport.rightOffset += 1
            }
        }
        .onChange(of: drawingTool) { _, _ in pendingPoints = [] }
        .onChange(of: crosshairMode) { _, on in if !on { crosshair = nil } }
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

    private func chartPoint(at location: CGPoint, layout: Layout, snap: Bool = true) -> ChartPoint {
        let s = scale(layout: layout)
        if !snap {
            return ChartPoint(time: time(forIndex: s.fractionalIndex(atX: location.x)), price: s.price(atY: location.y))
        }
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

    /// Fractional bar index of a time; times after the last bar continue at the bar length.
    private func barPosition(of time: Date) -> Double? {
        guard let first = candles.first, let last = candles.last, time >= first.time else { return nil }
        if time >= last.time {
            let step = countdownInterval
                ?? (candles.count > 1 ? last.time.timeIntervalSince(candles[candles.count - 2].time) : 60)
            return Double(candles.count - 1) + time.timeIntervalSince(last.time) / max(step, 1)
        }
        var low = 0, high = candles.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if candles[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return Double(low)
    }

    /// News flags: a faint dashed line through the chart and a coloured tag on the time axis.
    /// Events to the right of the screen are pinned to its right edge.
    /// A horizontal line broken in the middle of its visible part by its label.
    private func drawCenterLabeled(_ segment: ChartSegment, from startX: CGFloat, to endX: CGFloat, y: CGFloat,
                                   in context: inout GraphicsContext) {
        guard endX > startX else { return }
        let text = Text(segment.label).font(.system(size: 10, weight: .medium)).foregroundColor(theme.primaryText)
        let size = CGSize(width: CGFloat(segment.label.count) * 6.5 + 2, height: 12)
        let midX = (startX + endX) / 2
        let style = StrokeStyle(lineWidth: segment.width, dash: segment.dash)
        // Too short for the name: just the line.
        guard endX - startX > size.width + 16 else {
            var path = Path()
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: y))
            context.stroke(path, with: .color(segment.color), style: style)
            return
        }
        var path = Path()
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: midX - size.width / 2 - 4, y: y))
        path.move(to: CGPoint(x: midX + size.width / 2 + 4, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        context.stroke(path, with: .color(segment.color), style: style)
        context.draw(text, at: CGPoint(x: midX, y: y), anchor: .center)
    }

    private func drawTimeEvents(in context: inout GraphicsContext, layout: Layout, s: Scale) {
        var used: [CGRect] = []
        for event in timeEvents.sorted(by: { $0.time < $1.time }) {
            guard let position = barPosition(of: event.time) else { continue }
            let x = s.x(position)
            guard x >= 0 else { continue }
            let offscreen = x > layout.axisX
            if !offscreen {
                var line = Path()
                line.move(to: CGPoint(x: x, y: layout.plot.minY))
                line.addLine(to: CGPoint(x: x, y: layout.timeAxis.minY))
                context.stroke(line, with: .color(event.color.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            let text = Text(offscreen ? "\(event.label) ›" : event.label)
                .font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
            let resolved = context.resolve(text)
            let size = resolved.measure(in: CGSize(width: 200, height: 20))
            let width = size.width + 10
            var rect = CGRect(x: x - width / 2, y: layout.timeAxis.minY + 1.5, width: width, height: layout.timeAxis.height - 3)
            rect.origin.x = min(max(rect.minX, 2), layout.axisX - width - 2)
            // Skip a tag that would cover one already drawn.
            if used.contains(where: { $0.insetBy(dx: -2, dy: 0).intersects(rect) }) { continue }
            used.append(rect)
            context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(event.color))
            context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    /// A touch on screen in the chart's own coordinates (plot from x = 0, axis after it).
    private func chartLocation(_ point: CGPoint, layout: Layout) -> CGPoint {
        guard axisLeading else { return point }
        return CGPoint(x: point.x < axisWidth ? layout.axisX + point.x : point.x - axisWidth, y: point.y)
    }

    /// A finger moving over the plot: shifted only, so passing over the left axis doesn't jump.
    private func plotLocation(_ point: CGPoint) -> CGPoint {
        axisLeading ? CGPoint(x: point.x - axisWidth, y: point.y) : point
    }

    /// `axisOnly`: the pass that only shows the price axis (axis on the left), candles skipped.
    private func draw(in context: inout GraphicsContext, layout: Layout, now: Date, axisOnly: Bool = false) {
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
            if showGrid { context.stroke(line, with: .color(theme.grid), lineWidth: theme.isLight ? 1 : 0.5) }
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
            if showGrid { context.stroke(line, with: .color(theme.grid), lineWidth: theme.isLight ? 1 : 0.5) }
            if showTimeAxis {
                context.draw(Text(candles[i].time.formatted(timeFormat)).font(.system(size: 10)).foregroundColor(theme.text),
                         at: CGPoint(x: x, y: layout.timeAxis.midY), anchor: .center)
            }
        }
        if framed {
            let frame = CGRect(x: 0.5, y: layout.plot.minY + 0.5, width: layout.axisX - 0.5,
                               height: layout.timeAxis.minY - layout.plot.minY - 1)
            context.stroke(Path(frame), with: .color(theme.text.opacity(0.45)), lineWidth: 1)
        } else {
            var separator = Path()
            separator.move(to: CGPoint(x: layout.axisX, y: layout.plot.minY))
            separator.addLine(to: CGPoint(x: layout.axisX, y: layout.timeAxis.minY))
            context.stroke(separator, with: .color(theme.grid), lineWidth: 1)
        }

        var plotContext = context
        plotContext.clip(to: Path(layout.plot))
        drawTimeEvents(in: &context, layout: layout, s: s)

        // Session boxes (behind candles).
        for box in sessionBoxes where !axisOnly && box.range.upperBound >= range.lowerBound && box.range.lowerBound < range.upperBound {
            let rect = CGRect(x: s.x(box.range.lowerBound) - s.barWidth / 2, y: s.y(box.high),
                              width: s.x(box.range.upperBound) - s.x(box.range.lowerBound) + s.barWidth,
                              height: max(2, s.y(box.low) - s.y(box.high)))
            switch box.style {
            case .filled:
                plotContext.fill(Path(rect), with: .color(box.color.opacity(box.fillOpacity)))
                if box.showBorder {
                    plotContext.stroke(Path(rect), with: .color(box.color.opacity(0.7)), lineWidth: box.borderWidth)
                }
            case .dotted:
                plotContext.stroke(Path(rect), with: .color(box.color.opacity(0.8)),
                                   style: StrokeStyle(lineWidth: box.borderWidth, dash: [2, 3]))
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
            plotContext.stroke(path, with: .color(line.color), style: StrokeStyle(lineWidth: line.width, dash: line.dash))
            if !line.label.isEmpty {
                plotContext.draw(Text(line.label).font(.system(size: 9)).foregroundColor(line.color),
                                 at: CGPoint(x: x + 3, y: layout.plot.minY + 8), anchor: .leading)
            }
        }
        for segment in segments where !axisOnly {
            let startX = s.x(segment.start)
            let endX = segment.end.map { s.x($0) } ?? layout.axisX
            guard endX >= 0, startX <= layout.axisX else { continue }
            let y = s.y(segment.price)
            let endY = segment.endPrice.map { s.y($0) } ?? y
            if segment.centerLabel, !segment.label.isEmpty {
                drawCenterLabeled(segment, from: max(startX, 0), to: min(endX, layout.axisX), y: y, in: &plotContext)
                continue
            }
            var path = Path()
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: endX, y: endY))
            plotContext.stroke(path, with: .color(segment.color), style: StrokeStyle(lineWidth: segment.width, dash: segment.dash))
            if !segment.label.isEmpty {
                let labelX = min(endX, layout.axisX - 4)
                if segment.endPrice != nil {
                    // Sloped lines: label in the middle, on the outer side of the swing.
                    let above = endY <= y
                    plotContext.draw(Text(segment.label).font(.system(size: 9, weight: .semibold)).foregroundColor(segment.color),
                                     at: CGPoint(x: (startX + endX) / 2, y: min(y, endY) + (above ? -7 : abs(endY - y) + 7)),
                                     anchor: .center)
                } else {
                    plotContext.draw(Text(segment.label).font(.system(size: 9, weight: .medium)).foregroundColor(segment.color),
                                     at: CGPoint(x: labelX, y: y - 6), anchor: .trailing)
                }
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

        if !axisOnly {
            drawCandles(in: &plotContext, range: range, s: s)
            drawBubbles(in: &plotContext, range: range, s: s)
        }

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
        if creatingPreview == nil, let tool = drawingTool, pendingPoints.count >= 2 {
            drawDrawing(makeDrawing(tool, points: pendingPoints), in: &plotContext, s: s, layout: layout, decimals: decimals,
                        selected: false, axisLabels: &axisLabels)
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

        // Trade levels, MT5 style: a thin full-width line, its name at the left,
        // the money at the right and the price in an outlined box on the axis.
        // Faint until tapped; a tapped order shows its ✕ for a couple of seconds.
        for line in priceLines {
            let y = s.y(line.price)
            guard y >= layout.plot.minY - 1, y <= layout.plot.maxY + 1 else { continue }
            let active = isLineActive(line)
            // With an order selected the others step back.
            let alpha: Double = active ? 1 : (activeLineGroup == nil ? 0.6 : 0.25)
            let color = line.color.opacity(alpha)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: layout.axisX, y: y))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: active ? 1.3 : 1, dash: line.dash))

            let label = context.resolve(Text(line.label.uppercased()).font(.system(size: 11, weight: .medium))
                .kerning(0.6).foregroundColor(color))
            context.draw(label, at: CGPoint(x: 6, y: y - 9), anchor: .leading)
            if !line.value.isEmpty {
                let right = layout.axisX - (line.closable && active ? 40 : 6)
                let value = context.resolve(Text(line.value).font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor((line.valueColor ?? line.color).opacity(alpha)))
                context.draw(value, at: CGPoint(x: right, y: y - 9), anchor: .trailing)
            }
            if line.closable && active {
                let button = closeButtonRect(y: y, layout: layout)
                context.fill(Path(ellipseIn: button), with: .color(line.color))
                var cross = Path()
                let inset: CGFloat = 6
                cross.move(to: CGPoint(x: button.minX + inset, y: button.minY + inset))
                cross.addLine(to: CGPoint(x: button.maxX - inset, y: button.maxY - inset))
                cross.move(to: CGPoint(x: button.maxX - inset, y: button.minY + inset))
                cross.addLine(to: CGPoint(x: button.minX + inset, y: button.maxY - inset))
                context.stroke(cross, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            if let index = line.markerIndex, range.contains(index) {
                // Entry point on the candle where the order filled.
                let dot = CGRect(x: s.x(index) - 4, y: y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                context.stroke(Path(ellipseIn: dot), with: .color(theme.background.opacity(alpha)), lineWidth: 1.2)
            }
            axisLabels.append(AxisLabel(price: line.price, text: Self.format(line.price, decimals), tag: "",
                                        color: theme.background, textColor: line.color, border: line.color))
        }

        // Ask line: the spread above the bid (the last price below).
        if let ask = askPrice, let last = candles.last, ask > last.close {
            let y = s.y(ask)
            if y >= layout.plot.minY, y <= layout.plot.maxY {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: layout.axisX, y: y))
                context.stroke(path, with: .color(theme.down.opacity(0.85)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            }
        }

        // Axis labels, nudged apart so they don't overlap.
        // Price labels on the axis: taller boxes and bolder figures, easy to read at a glance.
        let tagH = Self.axisLabelHeight
        let placed = Self.spread(axisLabels.map { (label: $0, y: s.y($0.price)) }, minGap: tagH + 1,
                                 bounds: (layout.plot.minY + tagH / 2)...(layout.plot.maxY - tagH / 2))
        for (label, y) in placed {
            let box = CGRect(x: layout.axisX + 1, y: y - tagH / 2, width: axisWidth - 2, height: tagH)
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(label.color))
            if let border = label.border {
                context.stroke(Path(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 3), with: .color(border), lineWidth: 1.5)
            }
            context.draw(Text(label.text).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundColor(label.textColor),
                         at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            if !label.tag.isEmpty {
                let tagText = Text(label.tag).font(.system(size: 11, weight: .medium)).foregroundColor(label.textColor)
                let width = CGFloat(label.tag.count) * 6.6 + 12
                let tag = CGRect(x: layout.axisX - width - 2, y: y - tagH / 2, width: width, height: tagH)
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
            let row = Self.axisLabelHeight
            let boxHeight: CGFloat = countdown == nil ? row : row + 14
            let labelY = min(max(y, layout.plot.minY + boxHeight / 2), layout.plot.maxY - boxHeight / 2)
            let box = CGRect(x: layout.axisX + 1, y: labelY - row / 2, width: axisWidth - 2, height: boxHeight)
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(color))
            context.draw(Text(Self.format(last.close, decimals)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundColor(.white),
                         at: CGPoint(x: box.midX, y: box.minY + row / 2), anchor: .center)
            if let countdown {
                context.draw(Text(countdown).font(.system(size: 10.5, weight: .medium).monospacedDigit()).foregroundColor(.white.opacity(0.92)),
                             at: CGPoint(x: box.midX, y: box.minY + row + 6), anchor: .center)
            }
            // Ask price in an outlined box just above the bid box.
            if let ask = askPrice, ask > last.close {
                let askY = min(s.y(ask), box.minY - 9)
                if askY >= layout.plot.minY + 8 {
                    let askBox = CGRect(x: layout.axisX + 1, y: askY - 8, width: axisWidth - 2, height: 16)
                    context.fill(Path(roundedRect: askBox, cornerRadius: 2), with: .color(theme.background))
                    context.stroke(Path(roundedRect: askBox.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2),
                                   with: .color(theme.down), lineWidth: 1)
                    context.draw(Text(Self.format(ask, decimals)).font(.system(size: 10, weight: .medium)).foregroundColor(theme.down),
                                 at: CGPoint(x: askBox.midX, y: askBox.midY), anchor: .center)
                }
            }
        }

        // Bar replay: the chosen start bar, a line at its right edge, and the bars after it dimmed
        // (they are hidden once the replay starts).
        if !axisOnly, let pick = pickIndex, candles.indices.contains(pick) {
            let x = s.x(pick) + s.barWidth / 2 + 1
            if x < layout.axisX {
                let left = max(x, 0)
                context.fill(Path(CGRect(x: left, y: layout.plot.minY, width: layout.axisX - left, height: layout.volume.maxY - layout.plot.minY)),
                             with: .color(theme.background.opacity(0.72)))
                var path = Path()
                path.move(to: CGPoint(x: x, y: layout.plot.minY))
                path.addLine(to: CGPoint(x: x, y: layout.volume.maxY))
                context.stroke(path, with: .color(theme.accent), lineWidth: 1.5)
                var timeFormat = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).hour().minute()
                timeFormat.timeZone = timeZone
                let label = context.resolve(Text("✂︎ " + candles[pick].time.formatted(timeFormat))
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white))
                let size = label.measure(in: CGSize(width: 300, height: 30))
                let box = CGRect(x: min(max(x - size.width / 2 - 8, 2), layout.axisX - size.width - 18), y: layout.plot.minY + 6,
                                 width: size.width + 16, height: size.height + 8)
                context.fill(Path(roundedRect: box, cornerRadius: 7), with: .color(theme.accent))
                context.draw(label, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            }
        }

        // Crosshair.
        if crosshair == nil, let index = crosshairIndex(layout: layout) {
            // The other chart's crosshair: its time as a vertical line here.
            let x = s.x(index)
            var path = Path()
            path.move(to: CGPoint(x: x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: x, y: layout.volume.maxY))
            context.stroke(path, with: .color(theme.text.opacity(0.8)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
        }
        if let point = crosshair, let index = crosshairIndex(layout: layout) {
            let x = s.x(index)
            let y = min(max(point.y, layout.plot.minY), layout.plot.maxY)
            var path = Path()
            path.move(to: CGPoint(x: x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: x, y: layout.volume.maxY))
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: layout.axisX, y: y))
            context.stroke(path, with: .color(theme.text.opacity(0.8)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            let priceBox = CGRect(x: layout.axisX + 1, y: y - Self.axisLabelHeight / 2, width: axisWidth - 2, height: Self.axisLabelHeight)
            context.fill(Path(roundedRect: priceBox, cornerRadius: 3), with: .color(theme.crosshairLabel))
            context.draw(Text(Self.format(s.price(atY: y), decimals)).font(.system(size: 11.5, weight: .semibold).monospacedDigit()).foregroundColor(.white),
                         at: CGPoint(x: priceBox.midX, y: priceBox.midY), anchor: .center)
            var crosshairFormat = Date.FormatStyle.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits).hour().minute()
            if barInterval < 60 { crosshairFormat = crosshairFormat.second(.twoDigits) }
            crosshairFormat.timeZone = timeZone
            let timeText = candles[index].time.formatted(crosshairFormat)
            // Without a time axis (upper compare chart) the time sits at the bottom of the plot.
            let timeY = showTimeAxis ? layout.timeAxis.minY + 1 : layout.volume.maxY - 17
            let timeBox = CGRect(x: x - 60, y: timeY, width: 120, height: 16)
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
        /// MT5-style order price: background box with a coloured border.
        var border: Color? = nil
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
                                        tag: "", color: color, textColor: .white))
        case .verticalLine:
            var path = Path()
            path.move(to: CGPoint(x: p0.x, y: layout.plot.minY))
            path.addLine(to: CGPoint(x: p0.x, y: layout.plot.maxY))
            context.stroke(path, with: .color(color), style: stroke)
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
        case .rectangle:
            guard points.count > 1 else { break }
            let rect = CGRect(x: min(p0.x, points[1].x), y: min(p0.y, points[1].y),
                              width: abs(points[1].x - p0.x), height: abs(points[1].y - p0.y))
            context.fill(Path(rect), with: .color(color.opacity(0.15)))
            context.stroke(Path(rect), with: .color(color), style: stroke)
        case .fibRetracement, .fibExtension:
            drawFib(d, points: points, in: &context, s: s, layout: layout, decimals: decimals, color: color)
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
            context.stroke(arrow, with: .color(rangeColor), lineWidth: CGFloat(d.lineWidth) * 0.8)
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
        case .elliottImpulse, .elliottCorrection:
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color), style: stroke)
            let names = d.tool == .elliottImpulse ? ["(0)", "(1)", "(2)", "(3)", "(4)", "(5)"] : ["(0)", "(A)", "(B)", "(C)"]
            for (i, p) in points.enumerated() where i < names.count {
                let peak = Self.isPeak(i, points)
                label(names[i], at: CGPoint(x: p.x, y: p.y + (peak ? -10 : 10)), anchor: .center)
            }
        case .headShoulders:
            if points.count > 2 {
                var area = Path()
                area.addLines(points)
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.12)))
            }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color), style: stroke)
            if points.count > 4 {
                // Neckline through the two troughs, across the whole pattern.
                let a = points[2], b = points[4]
                let slope = b.x != a.x ? (b.y - a.y) / (b.x - a.x) : 0
                let x0 = points[0].x, x1 = points[points.count - 1].x
                var neck = Path()
                neck.move(to: CGPoint(x: x0, y: a.y + (x0 - a.x) * slope))
                neck.addLine(to: CGPoint(x: x1, y: a.y + (x1 - a.x) * slope))
                context.stroke(neck, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            for (i, name) in [(1, "Vai trái"), (3, "Đầu"), (5, "Vai phải")] where i < points.count {
                let peak = Self.isPeak(i, points)
                label(name, at: CGPoint(x: points[i].x, y: points[i].y + (peak ? -10 : 10)), anchor: .center)
            }
        case .trianglePattern:
            if points.count > 3 {
                var area = Path()
                area.addLines(points)
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.12)))
            }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color), style: stroke)
            // The converging sides: A–C and B–D.
            for (i, j) in [(0, 2), (1, 3)] where j < points.count {
                var side = Path()
                side.move(to: points[i])
                side.addLine(to: points[j])
                context.stroke(side, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            for (i, p) in points.enumerated() where i < 4 {
                let peak = Self.isPeak(i, points)
                label(["A", "B", "C", "D"][i], at: CGPoint(x: p.x, y: p.y + (peak ? -10 : 10)), anchor: .center)
            }
        case .fixedRangeVolume, .anchoredVolume:
            drawVolumeProfile(d, in: &context, s: s, decimals: decimals, color: color, selected: selected)
        case .brush:
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: width + 0.5, lineCap: .round, lineJoin: .round, dash: d.lineStyle.dash))
        case .arrow, .path:
            guard points.count > 1 else { break }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color), style: stroke)
            context.stroke(Self.arrowHead(from: points[points.count - 2], to: points[points.count - 1], size: 10 + width * 2),
                           with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        case .ellipse:
            guard points.count > 1 else { break }
            let rect = CGRect(x: min(p0.x, points[1].x), y: min(p0.y, points[1].y),
                              width: abs(points[1].x - p0.x), height: abs(points[1].y - p0.y))
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.15)))
            context.stroke(Path(ellipseIn: rect), with: .color(color), style: stroke)
        case .arrowMarker:
            guard points.count > 1 else { break }
            context.fill(Self.arrowShape(from: p0, to: points[1]), with: .color(color))
        case .text:
            let text = d.text.isEmpty ? "Ghi chú" : d.text
            let anchor: UnitPoint = d.textAlign == .left ? .leading : (d.textAlign == .center ? .center : .trailing)
            context.draw(Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(color),
                         at: p0, anchor: anchor)
        }
        if d.tool != .text, !d.text.isEmpty {
            drawText(of: d, points: points, in: &context, layout: layout, color: color)
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
        // A brush stroke is moved as a whole.
        if d.tool == .brush { return [] }
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

    /// True when point `i` is above its neighbours (a high), for label placement.
    private static func isPeak(_ i: Int, _ points: [CGPoint]) -> Bool {
        let y = points[i].y
        let neighbours = [i - 1, i + 1].filter { points.indices.contains($0) }.map { points[$0].y }
        guard !neighbours.isEmpty else { return points.count > 1 ? y < points[1].y : true }
        return neighbours.allSatisfy { y <= $0 }
    }

    /// Two strokes of an arrow head at `b`, pointing away from `a`.
    private static func arrowHead(from a: CGPoint, to b: CGPoint, size: CGFloat) -> Path {
        let angle = atan2(b.y - a.y, b.x - a.x)
        var path = Path()
        for side in [-0.45, 0.45] {
            path.move(to: b)
            path.addLine(to: CGPoint(x: b.x - size * cos(angle + side), y: b.y - size * sin(angle + side)))
        }
        return path
    }

    /// A filled block arrow from `a` to `b` (arrow marker).
    private static func arrowShape(from a: CGPoint, to b: CGPoint) -> Path {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 1)
        let u = CGPoint(x: dx / length, y: dy / length)
        let n = CGPoint(x: -u.y, y: u.x)
        let head = min(22, length * 0.5), body: CGFloat = 4, wing: CGFloat = 11
        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: a.x + u.x * along + n.x * across, y: a.y + u.y * along + n.y * across)
        }
        var path = Path()
        path.addLines([at(0, -body), at(length - head, -body), at(length - head, -wing), at(length, 0),
                       at(length - head, wing), at(length - head, body), at(0, body)])
        path.closeSubpath()
        return path
    }

    /// Bars covered by a volume profile drawing (anchored: from the anchor to the last bar).
    private func volumeRange(_ d: Drawing) -> ClosedRange<Int>? {
        guard !candles.isEmpty, let first = d.points.first else { return nil }
        let i0 = Int(index(for: first.time).rounded())
        let i1 = d.tool == .anchoredVolume || d.points.count < 2 ? candles.count - 1 : Int(index(for: d.points[1].time).rounded())
        let lo = max(0, min(i0, i1)), hi = min(candles.count - 1, max(i0, i1))
        return lo <= hi ? lo...hi : nil
    }

    /// Volume at price over the drawing's bars: 24 rows, buying (up bars) and
    /// selling (down bars) volume, and the point of control (busiest row).
    private func drawVolumeProfile(_ d: Drawing, in context: inout GraphicsContext, s: Scale, decimals: Int,
                                   color: Color, selected: Bool) {
        guard let range = volumeRange(d) else { return }
        let bars = candles[range]
        guard let low = bars.map(\.low).min(), let high = bars.map(\.high).max(), high > low else { return }
        let rows = 24
        var up = [Double](repeating: 0, count: rows), down = up
        // Without volume (some forex feeds) every bar counts once.
        let useVolume = bars.contains { $0.volume > 0 }
        for c in bars {
            let first = min(rows - 1, max(0, Int((c.low - low) / (high - low) * Double(rows))))
            let last = min(rows - 1, max(0, Int((c.high - low) / (high - low) * Double(rows))))
            let share = (useVolume ? c.volume : 1) / Double(last - first + 1)
            for r in first...last {
                if c.close >= c.open { up[r] += share } else { down[r] += share }
            }
        }
        let totals = zip(up, down).map { $0 + $1 }
        guard let busiest = totals.indices.max(by: { totals[$0] < totals[$1] }), totals[busiest] > 0 else { return }
        let left = s.x(range.lowerBound) - s.barWidth / 2
        let right = s.x(range.upperBound) + s.barWidth / 2
        let top = s.y(high), bottom = s.y(low)
        let box = CGRect(x: left, y: top, width: max(right - left, 1), height: bottom - top)
        context.fill(Path(box), with: .color(color.opacity(selected ? 0.10 : 0.05)))
        if selected { context.stroke(Path(box), with: .color(color.opacity(0.6)), lineWidth: 1) }
        let widest = max(box.width * 0.35, 60)
        let rowHeight = box.height / CGFloat(rows)
        for r in 0..<rows where totals[r] > 0 {
            let y = bottom - CGFloat(r + 1) * rowHeight
            let upWidth = CGFloat(up[r] / totals[busiest]) * widest
            let downWidth = CGFloat(down[r] / totals[busiest]) * widest
            context.fill(Path(CGRect(x: left, y: y + 0.5, width: upWidth, height: max(rowHeight - 1, 0.5))),
                         with: .color(theme.up.opacity(0.45)))
            context.fill(Path(CGRect(x: left + upWidth, y: y + 0.5, width: downWidth, height: max(rowHeight - 1, 0.5))),
                         with: .color(theme.down.opacity(0.45)))
        }
        let pocPrice = low + (Double(busiest) + 0.5) / Double(rows) * (high - low)
        let pocY = s.y(pocPrice)
        var poc = Path()
        poc.move(to: CGPoint(x: left, y: pocY))
        poc.addLine(to: CGPoint(x: right, y: pocY))
        context.stroke(poc, with: .color(DrawingPalette.colors[1]), lineWidth: 1.2)
        context.draw(Text("POC \(Self.format(pocPrice, decimals))").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DrawingPalette.colors[1]),
                     at: CGPoint(x: right - 2, y: pocY - 7), anchor: .trailing)
    }

    private func drawBubbles(in context: inout GraphicsContext, range: Range<Int>, s: Scale) {
        for bubble in bubbles where range.contains(bubble.index) && candles.indices.contains(bubble.index) {
            let c = candles[bubble.index]
            let radius = min(5 + CGFloat(bubble.ratio) * 1.6, 16)
            let x = s.x(bubble.index)
            let y = bubble.buying ? s.y(c.low) + radius + 3 : s.y(c.high) - radius - 3
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let color = bubble.buying ? theme.up : theme.down
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.35)))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1)
            if radius >= 9 {
                context.draw(Text("🦈").font(.system(size: radius)), at: CGPoint(x: x, y: y), anchor: .center)
            }
        }
    }

    /// A drawing's text, placed left / centre / right along it (TradingView's text alignment).
    private func drawText(of d: Drawing, points: [CGPoint], in context: inout GraphicsContext, layout: Layout, color: Color) {
        guard let p0 = points.first else { return }
        let text = Text(d.text).font(.system(size: 11, weight: .semibold)).foregroundColor(color)
        let anchor: UnitPoint = d.textAlign == .left ? .leading : (d.textAlign == .center ? .center : .trailing)
        func along(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
            switch d.textAlign {
            case .left: return a + 4
            case .center: return (a + b) / 2
            case .right: return b - 4
            }
        }
        switch d.tool {
        case .horizontalLine, .horizontalRay:
            let start = d.tool == .horizontalRay ? p0.x : 0
            context.draw(text, at: CGPoint(x: along(start, layout.axisX), y: p0.y - 8), anchor: anchor)
        case .verticalLine:
            let y: CGFloat
            switch d.textAlign {
            case .left: y = layout.plot.minY + 10
            case .center: y = layout.plot.midY
            case .right: y = layout.plot.maxY - 10
            }
            context.draw(text, at: CGPoint(x: p0.x + 4, y: y), anchor: .leading)
        case .trendLine, .trendRay, .arrow, .path:
            guard let last = points.last, points.count > 1 else { return }
            let t: CGFloat = d.textAlign == .left ? 0 : (d.textAlign == .center ? 0.5 : 1)
            let point = CGPoint(x: p0.x + (last.x - p0.x) * t, y: p0.y + (last.y - p0.y) * t)
            context.draw(text, at: CGPoint(x: point.x, y: point.y - 9), anchor: anchor)
        default:
            // Boxes and patterns: along the top edge of the shape (inside for boxes).
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min() else { return }
            let inside = d.tool == .rectangle || d.tool == .ellipse
            context.draw(text, at: CGPoint(x: along(minX, max(maxX, minX + 40)), y: inside ? minY + 10 : minY - 10),
                         anchor: anchor)
        }
    }

    // MARK: - Fibonacci

    /// Shown levels of a Fibonacci drawing and their prices.
    private func fibLines(_ d: Drawing) -> [(level: FibLevel, price: Double)] {
        let f = d.fibSettings
        return f.levels.filter(\.enabled).compactMap { level in
            if d.tool == .fibExtension {
                guard d.points.count > 2 else { return nil }
                let leg = d.points[1].price - d.points[0].price
                return (level, d.points[2].price + (f.reverse ? -leg : leg) * level.value)
            }
            guard d.points.count > 1 else { return nil }
            let start = d.points[0].price, end = d.points[1].price
            let value = f.reverse ? 1 - level.value : level.value
            return (level, end + (start - end) * value)
        }
    }

    /// Left and right ends of the level lines on screen.
    private func fibSpan(_ d: Drawing, points: [CGPoint], s: Scale, layout: Layout) -> (left: CGFloat, right: CGFloat)? {
        var left: CGFloat, right: CGFloat
        if d.tool == .fibExtension {
            guard points.count > 2 else { return nil }
            left = points[2].x
            right = max(left + s.barWidth * 20, points.map(\.x).max() ?? left)
        } else {
            guard points.count > 1 else { return nil }
            left = min(points[0].x, points[1].x)
            right = max(max(points[0].x, points[1].x), left + s.barWidth * 12)
        }
        let extend = d.fibSettings.extend
        if extend == .left || extend == .both { left = 0 }
        if extend == .right || extend == .both { right = layout.axisX }
        return (left, right)
    }

    private func drawFib(_ d: Drawing, points: [CGPoint], in context: inout GraphicsContext, s: Scale, layout: Layout,
                         decimals: Int, color: Color) {
        let f = d.fibSettings
        if f.showTrendLine, points.count > 1 {
            var legs = Path()
            legs.addLines(points)
            context.stroke(legs, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        guard let span = fibSpan(d, points: points, s: s, layout: layout) else { return }
        let lines = fibLines(d).sorted { $0.price > $1.price }
        func levelColor(_ level: FibLevel) -> Color {
            if let own = level.color { return own.color }
            if let single = f.singleColor { return single.color }
            let v = level.value
            if d.tool == .fibExtension { return v == 1 || v == 1.618 ? DrawingPalette.colors[3] : color }
            if v == 0 || v == 1 { return color }
            return v < 0 ? theme.up : (v >= 0.62 && v <= 0.79 ? DrawingPalette.colors[3] : color)
        }
        // Background between neighbouring levels, in the upper level's colour.
        if f.background {
            for (upper, lower) in zip(lines, lines.dropFirst()) {
                let y1 = s.y(upper.price), y2 = s.y(lower.price)
                context.fill(Path(CGRect(x: span.left, y: min(y1, y2), width: span.right - span.left, height: abs(y2 - y1))),
                             with: .color(levelColor(upper.level).opacity(f.backgroundOpacity)))
            }
        }
        if f.oteZone, d.tool == .fibRetracement, d.points.count > 1 {
            let start = d.points[0].price, end = d.points[1].price
            let value = { (v: Double) in end + (start - end) * (f.reverse ? 1 - v : v) }
            let y1 = s.y(value(0.62)), y2 = s.y(value(0.79))
            context.fill(Path(CGRect(x: span.left, y: min(y1, y2), width: span.right - span.left, height: abs(y2 - y1))),
                         with: .color(DrawingPalette.colors[3].opacity(0.16)))
        }
        for line in lines {
            let y = s.y(line.price)
            let c = levelColor(line.level)
            var path = Path()
            path.move(to: CGPoint(x: span.left, y: y))
            path.addLine(to: CGPoint(x: span.right, y: y))
            let key = line.level.value == 0.705 || (d.tool == .fibExtension && line.level.value == 1.618)
            context.stroke(path, with: .color(c),
                           style: StrokeStyle(lineWidth: CGFloat(d.lineWidth) * (key ? 0.95 : 0.7), dash: d.lineStyle.dash))
            var parts: [String] = []
            if f.showLevels {
                parts.append(line.level.value == 0.705 && d.tool == .fibRetracement ? "0.705 OTE" : String(format: "%g", line.level.value))
            }
            if f.showPrices { parts.append("(\(Self.format(line.price, decimals)))") }
            guard !parts.isEmpty else { continue }
            let text = Text(parts.joined(separator: " ")).font(.system(size: 10, weight: .semibold)).foregroundColor(c)
            if f.labelsLeft {
                context.draw(text, at: CGPoint(x: max(span.left, 0) + 3, y: y - 6), anchor: .leading)
            } else {
                context.draw(text, at: CGPoint(x: min(span.right, layout.axisX) - 3, y: y - 6), anchor: .trailing)
            }
        }
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
            case .fibRetracement, .fibExtension:
                if let span = fibSpan(d, points: points, s: s, layout: layout) {
                    let ys = fibLines(d).map { s.y($0.price) } + points.map(\.y)
                    if location.x > span.left - tolerance, location.x < span.right + tolerance,
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
            case .elliottImpulse, .elliottCorrection, .headShoulders, .trianglePattern, .brush, .arrow, .path:
                if zip(points, points.dropFirst()).contains(where: { Self.distance(from: location, toSegment: $0, $1) < tolerance }) {
                    return d
                }
            case .arrowMarker:
                if points.count > 1, Self.distance(from: location, toSegment: p0, points[1]) < tolerance + 6 { return d }
            case .ellipse:
                if points.count > 1 {
                    let rect = CGRect(x: min(p0.x, points[1].x), y: min(p0.y, points[1].y),
                                      width: abs(points[1].x - p0.x), height: abs(points[1].y - p0.y))
                    if rect.insetBy(dx: -tolerance, dy: -tolerance).contains(location) { return d }
                }
            case .fixedRangeVolume, .anchoredVolume:
                if let range = volumeRange(d) {
                    let bars = candles[range]
                    if let low = bars.map(\.low).min(), let high = bars.map(\.high).max() {
                        let box = CGRect(x: s.x(range.lowerBound) - s.barWidth / 2, y: s.y(high),
                                         width: s.x(range.upperBound) - s.x(range.lowerBound) + s.barWidth,
                                         height: s.y(low) - s.y(high))
                        if box.insetBy(dx: -tolerance, dy: -tolerance).contains(location) { return d }
                    }
                }
            case .text:
                if CGRect(x: p0.x - 6, y: p0.y - 14, width: 160, height: 28).contains(location) { return d }
            }
        }
        return nil
    }

    /// Lines of one order share the id before the last "|" (e.g. "pos|<id>").
    private static func lineGroup(_ id: String) -> String {
        id.split(separator: "|").dropLast().joined(separator: "|")
    }

    private func isLineActive(_ line: ChartPriceLine) -> Bool {
        let group = Self.lineGroup(line.id)
        // A limit order being placed is always shown fully.
        if group == "draft" { return true }
        if let dragged = draggedLine, Self.lineGroup(dragged.id) == group { return true }
        return activeLineGroup == group
    }

    /// Selects an order: its entry, SL and TP light up and only they can be dragged,
    /// until a tap on the chart away from the lines.
    private func activateLines(of id: String) {
        activeLineGroup = Self.lineGroup(id)
    }

    /// The order being placed is the only one of its kind: always draggable.
    private static func alwaysDraggable(_ group: String) -> Bool { group == "draft" || group == "ticket" }

    /// Orders under a tap, nearest first. Tapping again where several orders meet
    /// (same entry) moves on to the next one.
    private func nextLineGroup(at location: CGPoint, layout: Layout) -> String? {
        let s = scale(layout: layout)
        let near = priceLines.filter { abs(s.y($0.price) - location.y) < 16 }
            .sorted { abs(s.y($0.price) - location.y) < abs(s.y($1.price) - location.y) }
        var groups: [String] = []
        for line in near where !groups.contains(Self.lineGroup(line.id)) { groups.append(Self.lineGroup(line.id)) }
        guard let first = groups.first else { return nil }
        if let current = activeLineGroup, let index = groups.firstIndex(of: current) {
            return groups[(index + 1) % groups.count]
        }
        return first
    }

    /// The ✕ button of a closable price line, just left of the price axis.
    private func closeButtonRect(y: CGFloat, layout: Layout) -> CGRect {
        CGRect(x: layout.axisX - 30, y: y - 11, width: 22, height: 22)
    }

    /// The draggable price line nearest to `location`, within a finger's reach.
    private func hitPriceLine(at location: CGPoint, layout: Layout) -> ChartPriceLine? {
        let s = scale(layout: layout)
        return priceLines
            .filter { line in
                let group = Self.lineGroup(line.id)
                // Only the selected order's lines move (tap its entry first).
                return line.draggable && (group == activeLineGroup || Self.alwaysDraggable(group))
                    && abs(s.y(line.price) - location.y) < 16
            }
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

    /// Bar under the crosshair, or under the other chart's crosshair (compare split).
    private func crosshairIndex(layout: Layout, ownOnly: Bool = false) -> Int? {
        guard !candles.isEmpty else { return nil }
        if let point = crosshair {
            let s = scale(layout: layout)
            return min(max(s.index(atX: point.x), 0), candles.count - 1)
        }
        guard !ownOnly, let time = linkedCrosshair?.wrappedValue else { return nil }
        return min(max(Int(index(for: time).rounded()), 0), candles.count - 1)
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

    private func handleTap(at screenLocation: CGPoint, layout: Layout) {
        let location = chartLocation(screenLocation, layout: layout)
        // Taps on the reset menu belong to its buttons; a tap elsewhere closes it.
        if let point = menuPoint {
            let width = layout.axisX + axisWidth, height = layout.timeAxis.maxY
            let center = CGPoint(x: min(max(point.x, 110), width - 110), y: min(max(point.y, 70), height - 70))
            if CGRect(x: center.x - 105, y: center.y - 100, width: 210, height: 200).contains(screenLocation) { return }
            if Date().timeIntervalSince(pressEndedAt) > 0.3 {
                menuPoint = nil
                crosshair = nil
            }
            return
        }
        // The release of a long press also ends as a tap; keep that crosshair.
        guard location.x < layout.axisX, Date().timeIntervalSince(pressEndedAt) > 0.3 else { return }
        let s = scale(layout: layout)
        if let onPickBar, !candles.isEmpty {
            onPickBar(min(max(s.index(atX: location.x), 0), candles.count - 1))
            return
        }
        if let line = priceLines.first(where: {
            $0.closable && isLineActive($0)
                && closeButtonRect(y: s.y($0.price), layout: layout).insetBy(dx: -8, dy: -8).contains(location)
        }) {
            onPriceLineClose?(line.id)
            return
        }
        // Tapping a trade line selects its order (again: the next order at that price).
        if let group = nextLineGroup(at: location, layout: layout) {
            activeLineGroup = group
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        // A tap away from the lines lets the selected order go.
        activeLineGroup = nil
        if let tool = drawingTool {
            // The brush draws with a drag only.
            if tool == .brush { return }
            // A path ends when its last point is tapped again.
            if tool == .path, pendingPoints.count >= 2, let last = pendingPoints.last {
                let p = screenPoint(last, layout: layout)
                if hypot(p.x - location.x, p.y - location.y) < 24 {
                    let drawing = makeDrawing(tool, points: pendingPoints)
                    pendingPoints = []
                    onDrawingCreated?(drawing)
                    return
                }
            }
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
        onBackgroundTap?()
        if crosshairMode { crosshair = location }
    }

    /// One drag gesture for everything: on the price axis it stretches the
    /// price scale, on the selected drawing it moves the drawing, with the
    /// crosshair shown it moves the crosshair, otherwise it scrolls (and, once
    /// the price scale is manual, moves prices too).
    private func dragGesture(layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let startLocation = chartLocation(value.startLocation, layout: layout)
                let location = plotLocation(value.location)
                if dragMode == nil {
                    let range = currentPriceRange(layout: layout)
                    if startLocation.x > layout.axisX {
                        dragMode = .axis
                        dragStartRange = range
                    } else if drawingTool == nil, let line = hitPriceLine(at: startLocation, layout: layout) {
                        dragMode = .priceLine
                        draggedLine = (line.id, line.price)
                        activeLineGroup = Self.lineGroup(line.id)
                        crosshair = nil
                    } else if drawingTool != nil {
                        dragMode = .create
                        crosshair = nil
                    } else if !drawingsLocked, let hit = hitHandle(at: startLocation, layout: layout), !hit.0.locked {
                        dragMode = .moveHandle
                        movingOriginal = hit.0
                        handleIndex = hit.1
                    } else if !drawingsLocked, let id = selectedDrawingID, let hit = hitDrawing(at: startLocation, layout: layout),
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
                    let price = scale(layout: layout).price(atY: location.y)
                    draggedLine = (line.id, price)
                    onPriceLineDrag?(line.id, price, false)
                case .create:
                    guard let tool = drawingTool else { return }
                    if tool == .brush {
                        // Free hand: a point every few pixels.
                        var stroke = creatingPreview?.points ?? [chartPoint(at: startLocation, layout: layout, snap: false)]
                        if let last = stroke.last {
                            let p = screenPoint(last, layout: layout)
                            if hypot(p.x - location.x, p.y - location.y) > 3 {
                                stroke.append(chartPoint(at: location, layout: layout, snap: false))
                            }
                        }
                        creatingPreview = Drawing(tool: .brush, points: stroke)
                        guidePoint = nil
                        return
                    }
                    let end = chartPoint(at: location, layout: layout)
                    if tool.pointsNeeded == 1 {
                        creatingPreview = makeDrawing(tool, points: [end])
                    } else if tool.isMultiPoint {
                        // One drag per point: from the last placed point to the finger.
                        let placed = pendingPoints.isEmpty ? [chartPoint(at: startLocation, layout: layout)] : pendingPoints
                        creatingPreview = makeDrawing(tool, points: placed + [end])
                    } else {
                        let start = pendingPoints.first ?? chartPoint(at: startLocation, layout: layout)
                        creatingPreview = makeDrawing(tool, points: [start, end])
                    }
                    guidePoint = screenPoint(end, layout: layout)
                case .moveHandle:
                    guard let original = movingOriginal, let handle = handleIndex else { return }
                    let point = chartPoint(at: location, layout: layout)
                    movingPreview = moving(original, handle: handle, to: point)
                    guidePoint = screenPoint(point, layout: layout)
                case .crosshair:
                    crosshair = location
                case .pan:
                    let barWidth = layout.plot.width / CGFloat(max(viewport.visibleCount, 1))
                    let offset = panStartOffset + Double(value.translation.width / barWidth)
                    // Negative offsets leave empty space after the last bar, like TradingView.
                    let minOffset = -viewport.visibleCount * 0.85
                    viewport.rightOffset = min(max(offset, minOffset), Double(max(candles.count - 10, 0)))
                    if viewport.bounds(total: candles.count).start < 40 { onNeedOlder?() }
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
                let releasedLine = draggedLine
                if dragMode == .priceLine, let line = draggedLine {
                    onPriceLineDrag?(line.id, line.price, true)
                }
                draggedLine = nil
                // Keep the order highlighted for 2 s after letting go.
                if let releasedLine { activateLines(of: releasedLine.id) }
                if dragMode == .create, let created = creatingPreview {
                    if let tool = drawingTool, tool.isMultiPoint, created.points.count < tool.pointsNeeded {
                        // Not all points yet: keep them and wait for the next one.
                        pendingPoints = created.points
                    } else {
                        pendingPoints = []
                        onDrawingCreated?(created)
                    }
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
                if crosshairMode, drawingTool == nil, dragMode != .moveHandle, dragMode != .moveDrawing, dragMode != .priceLine,
                   case .second(true, let drag?) = value {
                    crosshair = plotLocation(drag.location)
                }
            }
            .onEnded { value in
                pressEndedAt = Date()
                // Held still: offer to reset the view (TradingView's chart context menu).
                if drawingTool == nil, onPickBar == nil, dragMode != .moveHandle, dragMode != .moveDrawing,
                   dragMode != .priceLine, case .second(true, let drag?) = value,
                   hypot(drag.translation.width, drag.translation.height) < 10 {
                    menuPoint = drag.location
                }
            }
    }

    /// Reset choices shown after a long press.
    private var chartMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuButton("Đặt lại thang giá", systemImage: "arrow.up.and.down") {
                viewport.manualPriceRange = nil
            }
            Divider()
            menuButton("Đặt lại biểu đồ", systemImage: "arrow.counterclockwise") {
                viewport.manualPriceRange = nil
                viewport.rightOffset = 0
                viewport.visibleCount = ChartViewport().visibleCount
            }
            Divider()
            menuButton("Về nến mới nhất", systemImage: "arrow.right.to.line") {
                viewport.rightOffset = 0
            }
            Divider()
            menuButton("Đóng", systemImage: "xmark") {}
        }
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            menuPoint = nil
            crosshair = nil
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    /// Replaces the plain title (e.g. a symbol · timeframe button).
    var titleView: AnyView? = nil
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var landscape = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if let titleView {
                    titleView
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.primaryText)
                        .lineLimit(1)
                }
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

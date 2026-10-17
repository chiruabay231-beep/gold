import SwiftUI
import Charts
import BacktestKit

/// One line drawn on a chart.
struct ChartLine: Identifiable {
    var id: String { title }
    var title: String
    var values: Series
    var color: Color
    var isHorizontal = false
}

enum ChartPalette {
    static let colors: [Color] = [.orange, .blue, .purple, .teal, .pink, .mint, .indigo, .brown, .cyan, .yellow]

    static func color(_ index: Int) -> Color { colors[index % colors.count] }

    static func lines(from plots: [Plot], offset: Int = 0) -> [ChartLine] {
        plots.enumerated().map { index, plot in
            ChartLine(title: plot.title, values: plot.values, color: color(index + offset), isHorizontal: plot.isHorizontalLine)
        }
    }
}

/// Which bars are visible: the `length` bars ending just before `end`.
struct ChartWindow: Equatable {
    var length: Int
    var end: Int

    init(total: Int, length: Int = 150) {
        self.length = min(max(total, 1), length)
        end = total
    }

    var range: Range<Int> { max(0, end - length)..<max(end, 0) }
}

struct ChartWindowControls: View {
    @Binding var window: ChartWindow
    let total: Int

    var body: some View {
        VStack(spacing: 4) {
            if total > 30 {
                HStack {
                    Text("Số nến \(window.length)")
                        .frame(width: 96, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(window.length) },
                        set: { newValue in
                            window.length = Int(newValue)
                            window.end = min(total, max(window.end, window.length))
                        }),
                        in: 30...Double(max(31, min(total, 800))), step: 10)
                }
            }
            if total > window.length {
                HStack {
                    Text("Vị trí")
                        .frame(width: 96, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(window.end) },
                        set: { window.end = Int($0) }),
                        in: Double(window.length)...Double(total), step: 1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ChartLegend: View {
    let lines: [ChartLine]

    var body: some View {
        if !lines.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lines.filter { !$0.isHorizontal }) { line in
                        HStack(spacing: 4) {
                            Circle().fill(line.color).frame(width: 8, height: 8)
                            Text(line.title)
                        }
                    }
                }
                .font(.caption2)
            }
        }
    }
}

// MARK: - Price chart

struct CandleMarks: ChartContent {
    let data: PriceData
    let indices: [Int]

    var body: some ChartContent {
        ForEach(indices, id: \.self) { i in
            let color: Color = data.close[i] >= data.open[i] ? .green : .red
            RuleMark(x: .value("Nến", i),
                     yStart: .value("Thấp", data.low[i]),
                     yEnd: .value("Cao", data.high[i]))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(color)
            RectangleMark(x: .value("Nến", i),
                          yStart: .value("Mở", data.open[i]),
                          yEnd: .value("Đóng", bodyEnd(i)),
                          width: .ratio(0.7))
                .foregroundStyle(color)
        }
    }

    private func bodyEnd(_ i: Int) -> Double {
        let open = data.open[i]
        let close = data.close[i]
        if open != close { return close }
        return close + max(abs(close) * 0.00005, 1e-9)
    }
}

struct LineMarks: ChartContent {
    let line: ChartLine
    let indices: [Int]

    var body: some ChartContent {
        if line.isHorizontal, let value = line.values.first(where: { !$0.isNaN }) {
            RuleMark(y: .value(line.title, value))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.secondary)
        } else {
            ForEach(indices.filter { !line.values[$0].isNaN }, id: \.self) { i in
                LineMark(x: .value("Nến", i),
                         y: .value(line.title, line.values[i]),
                         series: .value("Đường", line.title))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(line.color)
            }
        }
    }
}

struct TradeMarks: ChartContent {
    let trades: [Trade]

    var body: some ChartContent {
        ForEach(trades) { trade in
            let color: Color = trade.direction == .long ? .green : .red
            LineMark(x: .value("Nến", trade.entryIndex),
                     y: .value("Giá", trade.entryPrice),
                     series: .value("Lệnh", "trade-\(trade.id)"))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(trade.isWin ? Color.green : Color.red)
            LineMark(x: .value("Nến", trade.exitIndex),
                     y: .value("Giá", trade.exitPrice),
                     series: .value("Lệnh", "trade-\(trade.id)"))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(trade.isWin ? Color.green : Color.red)
            PointMark(x: .value("Nến", trade.entryIndex), y: .value("Giá", trade.entryPrice))
                .symbol(.triangle)
                .symbolSize(70)
                .foregroundStyle(color)
            PointMark(x: .value("Nến", trade.exitIndex), y: .value("Giá", trade.exitPrice))
                .symbol(.cross)
                .symbolSize(50)
                .foregroundStyle(Color.primary)
        }
    }
}

struct PriceChartView: View {
    let data: PriceData
    var lines: [ChartLine] = []
    var trades: [Trade] = []
    let range: Range<Int>

    var body: some View {
        let indices = Array(range)
        let visibleTrades = trades.filter { $0.exitIndex >= range.lowerBound && $0.entryIndex < range.upperBound }
        let domain = yDomain(indices)
        Chart {
            CandleMarks(data: data, indices: indices)
            ForEach(lines) { line in
                LineMarks(line: line, indices: indices)
            }
            TradeMarks(trades: visibleTrades)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: domain)
        .chartXAxis { indexDateAxis(data.time) }
        .chartLegend(.hidden)
    }

    private var xDomain: ClosedRange<Int> {
        let lower = range.lowerBound
        let upper = max(lower + 1, range.upperBound - 1)
        return lower...upper
    }

    private func yDomain(_ indices: [Int]) -> ClosedRange<Double> {
        var lo = Double.infinity
        var hi = -Double.infinity
        for i in indices {
            lo = min(lo, data.low[i])
            hi = max(hi, data.high[i])
        }
        for line in lines where !line.isHorizontal {
            for i in indices where !line.values[i].isNaN {
                // Ignore lines far away from price (e.g. a 0/1 flag plotted by mistake).
                let value = line.values[i]
                if value > lo * 0.5, value < hi * 1.5 {
                    lo = min(lo, value)
                    hi = max(hi, value)
                }
            }
        }
        return Self.padded(lo, hi)
    }

    static func padded(_ lo: Double, _ hi: Double) -> ClosedRange<Double> {
        guard lo.isFinite, hi.isFinite else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.04
        return (lo - pad)...(hi + pad)
    }
}

/// X axis for index-based charts, labelled with the bar's date.
func indexDateAxis(_ times: [Date]) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 4)) { value in
        AxisGridLine()
        AxisValueLabel {
            if let i = value.as(Int.self), i >= 0, i < times.count {
                Text(times[i], format: .dateTime.day().month(.defaultDigits).hour())
            }
        }
    }
}

// MARK: - Indicator pane

struct PaneChartView: View {
    let times: [Date]
    let lines: [ChartLine]
    let range: Range<Int>

    var body: some View {
        let indices = Array(range)
        Chart {
            ForEach(lines) { line in
                LineMarks(line: line, indices: indices)
            }
        }
        .chartXScale(domain: range.lowerBound...max(range.lowerBound + 1, range.upperBound - 1))
        .chartYScale(domain: yDomain(indices))
        .chartXAxis { indexDateAxis(times) }
        .chartLegend(.hidden)
    }

    private func yDomain(_ indices: [Int]) -> ClosedRange<Double> {
        var lo = Double.infinity
        var hi = -Double.infinity
        for line in lines {
            let points = line.isHorizontal ? Array(line.values.prefix(1)) : indices.map { line.values[$0] }
            for value in points where value.isFinite {
                lo = min(lo, value)
                hi = max(hi, value)
            }
        }
        return PriceChartView.padded(lo, hi)
    }
}

// MARK: - Equity

struct SeriesChartView: View {
    let title: String
    let times: [Date]
    let values: Series
    var color: Color = .accentColor
    var filled = true

    var body: some View {
        let points = downsampled
        let lo = points.map(\.value).min() ?? 0
        let hi = points.map(\.value).max() ?? 1
        Chart(points, id: \.index) { point in
            if filled {
                AreaMark(x: .value("Thời gian", point.time),
                         yStart: .value(title, lo),
                         yEnd: .value(title, point.value))
                    .foregroundStyle(color.opacity(0.15))
            }
            LineMark(x: .value("Thời gian", point.time), y: .value(title, point.value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartYScale(domain: PriceChartView.padded(lo, hi))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits).year(.twoDigits))
            }
        }
    }

    private struct Point {
        var index: Int
        var time: Date
        var value: Double
    }

    /// At most ~600 points so long histories stay smooth.
    private var downsampled: [Point] {
        let count = min(times.count, values.count)
        guard count > 0 else { return [] }
        let step = max(1, count / 600)
        var points: [Point] = []
        var i = 0
        while i < count {
            if values[i].isFinite { points.append(Point(index: i, time: times[i], value: values[i])) }
            i += step
        }
        if (count - 1) % step != 0, values[count - 1].isFinite {
            points.append(Point(index: count - 1, time: times[count - 1], value: values[count - 1]))
        }
        return points
    }
}

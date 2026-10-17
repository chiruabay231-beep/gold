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
    /// Show the line's latest value and title on the price axis (TradingView style).
    var axisLabel = false
}

enum ChartPalette {
    static let colors: [Color] = [.orange, .blue, .purple, .teal, .pink, .mint, .indigo, .brown, .cyan, .yellow]

    static func color(_ index: Int) -> Color { colors[index % colors.count] }

    static func lines(from plots: [BacktestKit.Plot], offset: Int = 0) -> [ChartLine] {
        plots.enumerated().map { index, plot in
            ChartLine(title: plot.title, values: plot.values, color: color(index + offset), isHorizontal: plot.isHorizontalLine)
        }
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

/// Price domain with 4% padding; never empty.
func paddedDomain(_ lo: Double, _ hi: Double) -> ClosedRange<Double> {
    guard lo.isFinite, hi.isFinite else { return 0...1 }
    if lo == hi { return (lo - 1)...(hi + 1) }
    let pad = (hi - lo) * 0.04
    return (lo - pad)...(hi + pad)
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
        return paddedDomain(lo, hi)
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
        .chartYScale(domain: paddedDomain(lo, hi))
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

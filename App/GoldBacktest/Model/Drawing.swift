import SwiftUI

/// A point on the chart in data coordinates, so drawings stay put when the
/// chart scrolls, zooms or receives new bars.
struct ChartPoint: Codable, Hashable {
    var time: Date
    var price: Double
}

enum DrawingTool: String, Codable, CaseIterable, Identifiable {
    case horizontalLine, horizontalRay, verticalLine, trendLine, rectangle, longPosition, shortPosition, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontalLine: return "Đường ngang"
        case .horizontalRay: return "Tia ngang"
        case .verticalLine: return "Đường dọc"
        case .trendLine: return "Đường xu hướng"
        case .rectangle: return "Hộp vùng giá"
        case .longPosition: return "Vị thế Long"
        case .shortPosition: return "Vị thế Short"
        case .text: return "Chữ"
        }
    }

    var systemImage: String {
        switch self {
        case .horizontalLine: return "minus"
        case .horizontalRay: return "arrow.right.to.line"
        case .verticalLine: return "line.diagonal"
        case .trendLine: return "chart.line.uptrend.xyaxis"
        case .rectangle: return "rectangle"
        case .longPosition: return "arrow.up.square"
        case .shortPosition: return "arrow.down.square"
        case .text: return "textformat"
        }
    }

    /// Taps needed to place the drawing. Positions: entry, then stop loss.
    var pointsNeeded: Int {
        switch self {
        case .horizontalLine, .horizontalRay, .verticalLine, .text: return 1
        case .trendLine, .rectangle, .longPosition, .shortPosition: return 2
        }
    }

    var hint: String {
        switch self {
        case .longPosition, .shortPosition: return "Chạm giá vào lệnh, rồi chạm giá cắt lỗ"
        case .trendLine: return "Chạm điểm đầu, rồi điểm cuối"
        case .rectangle: return "Chạm 2 góc đối diện của hộp"
        default: return "Chạm lên biểu đồ để đặt"
        }
    }
}

struct Drawing: Codable, Identifiable, Hashable {
    var id = UUID()
    var tool: DrawingTool
    var points: [ChartPoint]
    var text = ""
    var colorIndex = 0
    /// Target = entry ± riskReward × risk, for position tools.
    var riskReward = 2.0

    var color: Color { DrawingPalette.colors[colorIndex % DrawingPalette.colors.count] }

    /// Price levels of a position: entry, stop, target.
    var positionLevels: (entry: Double, stop: Double, target: Double)? {
        guard tool == .longPosition || tool == .shortPosition, points.count >= 2 else { return nil }
        let entry = points[0].price
        let stop = points[1].price
        return (entry, stop, entry + riskReward * (entry - stop))
    }
}

enum DrawingPalette {
    static let colors: [Color] = [
        Color(red: 0.161, green: 0.384, blue: 1.0),     // TradingView blue #2962FF
        Color(red: 0.949, green: 0.212, blue: 0.271),   // red
        Color(red: 0.031, green: 0.6, blue: 0.506),     // green
        Color(red: 1.0, green: 0.596, blue: 0.0),       // orange
        Color(red: 0.612, green: 0.153, blue: 0.69),    // purple
        Color(red: 0.471, green: 0.482, blue: 0.525),   // grey
    ]
}

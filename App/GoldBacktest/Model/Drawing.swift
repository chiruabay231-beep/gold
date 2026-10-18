import SwiftUI

/// A point on the chart in data coordinates, so drawings stay put when the
/// chart scrolls, zooms or receives new bars.
struct ChartPoint: Codable, Hashable {
    var time: Date
    var price: Double
}

enum DrawingTool: String, Codable, CaseIterable, Identifiable {
    case trendLine, trendRay, horizontalLine, horizontalRay, verticalLine
    case fibRetracement, rectangle, priceRange
    case longPosition, shortPosition, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trendLine: return "Đường xu hướng"
        case .trendRay: return "Tia xu hướng"
        case .horizontalLine: return "Đường ngang"
        case .horizontalRay: return "Tia ngang"
        case .verticalLine: return "Đường dọc"
        case .fibRetracement: return "Fibonacci (OTE)"
        case .rectangle: return "Hộp vùng giá"
        case .priceRange: return "Đo giá"
        case .longPosition: return "Vị thế Long"
        case .shortPosition: return "Vị thế Short"
        case .text: return "Chữ"
        }
    }

    var systemImage: String {
        switch self {
        case .trendLine: return "line.diagonal"
        case .trendRay: return "arrow.up.right"
        case .horizontalLine: return "minus"
        case .horizontalRay: return "arrow.right.to.line"
        case .verticalLine: return "poweron"
        case .fibRetracement: return "line.3.horizontal"
        case .rectangle: return "rectangle"
        case .priceRange: return "ruler"
        case .longPosition: return "arrow.up.square"
        case .shortPosition: return "arrow.down.square"
        case .text: return "textformat"
        }
    }

    /// Points that define the drawing. Positions: entry, then stop loss.
    var pointsNeeded: Int {
        switch self {
        case .horizontalLine, .horizontalRay, .verticalLine, .text: return 1
        default: return 2
        }
    }

    var hint: String {
        switch self {
        case .longPosition, .shortPosition: return "Kéo từ giá vào lệnh đến giá cắt lỗ"
        case .fibRetracement: return "Kéo từ đáy/đỉnh đầu sóng đến cuối sóng"
        case .rectangle: return "Kéo từ góc này sang góc đối diện"
        case .priceRange: return "Kéo từ điểm đầu đến điểm cuối để đo"
        case .trendLine, .trendRay: return "Kéo từ điểm đầu đến điểm cuối"
        default: return "Chạm hoặc kéo tới chỗ cần đặt"
        }
    }

    /// Lines whose width and dash can be changed and that can carry a label.
    var isLine: Bool {
        switch self {
        case .trendLine, .trendRay, .horizontalLine, .horizontalRay, .verticalLine, .rectangle: return true
        default: return false
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
    var lineWidth = 1.5
    var dashed = false

    init(tool: DrawingTool, points: [ChartPoint]) {
        self.tool = tool
        self.points = points
        if tool == .longPosition { colorIndex = 2 }
        if tool == .shortPosition { colorIndex = 1 }
        if tool == .fibRetracement { colorIndex = 5 }
    }

    // Fields added later are optional when reading drawings saved by older versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tool = try c.decode(DrawingTool.self, forKey: .tool)
        points = try c.decode([ChartPoint].self, forKey: .points)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        riskReward = try c.decodeIfPresent(Double.self, forKey: .riskReward) ?? 2
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 1.5
        dashed = try c.decodeIfPresent(Bool.self, forKey: .dashed) ?? false
    }

    var color: Color { DrawingPalette.colors[colorIndex % DrawingPalette.colors.count] }

    /// Price levels of a position: entry, stop, target.
    var positionLevels: (entry: Double, stop: Double, target: Double)? {
        guard tool == .longPosition || tool == .shortPosition, points.count >= 2 else { return nil }
        let entry = points[0].price
        let stop = points[1].price
        return (entry, stop, entry + riskReward * (entry - stop))
    }

    /// Fibonacci levels with ICT's OTE zone (0.62 – 0.79) and targets below 0.
    static let fibLevels: [Double] = [1, 0.79, 0.705, 0.62, 0.5, 0, -0.27, -0.62, -1]

    /// Price of a Fibonacci level: 0 at the second point, 1 at the first.
    func fibPrice(_ level: Double) -> Double? {
        guard points.count >= 2 else { return nil }
        let start = points[0].price, end = points[1].price
        return end + (start - end) * level
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

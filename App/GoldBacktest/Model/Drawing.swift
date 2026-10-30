import SwiftUI

/// A point on the chart in data coordinates, so drawings stay put when the
/// chart scrolls, zooms or receives new bars.
struct ChartPoint: Codable, Hashable {
    var time: Date
    var price: Double
}

enum DrawingTool: String, Codable, CaseIterable, Identifiable {
    case trendLine, trendRay, horizontalLine, horizontalRay, verticalLine
    case fibRetracement, fibExtension
    case elliottImpulse, elliottCorrection, headShoulders, trianglePattern
    case longPosition, shortPosition, fixedRangeVolume, anchoredVolume, priceRange
    case brush, rectangle, arrow, ellipse, path, arrowMarker
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trendLine: return "Đường xu hướng"
        case .trendRay: return "Tia xu hướng"
        case .horizontalLine: return "Đường nằm ngang"
        case .horizontalRay: return "Tia nằm ngang"
        case .verticalLine: return "Đường thẳng đứng"
        case .fibRetracement: return "Hồi quy Fib (OTE)"
        case .fibExtension: return "Phần mở rộng fib dựa trên xu hướng"
        case .elliottImpulse: return "Sóng đẩy Elliott (1·2·3·4·5)"
        case .elliottCorrection: return "Sóng điều chỉnh Elliott (A·B·C)"
        case .headShoulders: return "Mô hình Đầu Vai"
        case .trianglePattern: return "Mô hình tam giác"
        case .longPosition: return "Vị thế Mua"
        case .shortPosition: return "Vị thế Bán"
        case .fixedRangeVolume: return "Khối lượng giao dịch phạm vi cố định"
        case .anchoredVolume: return "Khối lượng giao dịch được neo"
        case .priceRange: return "Đo giá"
        case .brush: return "Cọ vẽ"
        case .rectangle: return "Hình chữ nhật"
        case .arrow: return "Mũi tên"
        case .ellipse: return "Hình elip"
        case .path: return "Đường dẫn"
        case .arrowMarker: return "Mũi tên đánh dấu"
        case .text: return "Văn bản"
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
        case .fibExtension: return "line.3.horizontal.decrease"
        case .elliottImpulse: return "chart.line.uptrend.xyaxis"
        case .elliottCorrection: return "chart.line.downtrend.xyaxis"
        case .headShoulders: return "mountain.2"
        case .trianglePattern: return "triangle"
        case .longPosition: return "arrow.up.square"
        case .shortPosition: return "arrow.down.square"
        case .fixedRangeVolume: return "align.horizontal.left"
        case .anchoredVolume: return "align.horizontal.left.fill"
        case .priceRange: return "ruler"
        case .brush: return "paintbrush.pointed"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .ellipse: return "oval"
        case .path: return "point.topleft.down.to.point.bottomright.curvepath"
        case .arrowMarker: return "arrowshape.turn.up.right"
        case .text: return "textformat"
        }
    }

    /// Points that define the drawing. Positions: entry, then stop loss.
    /// The brush takes any number (the finger's path); a path ends when its
    /// last point is tapped again or at this many points.
    var pointsNeeded: Int {
        switch self {
        case .horizontalLine, .horizontalRay, .verticalLine, .text, .anchoredVolume: return 1
        case .fibExtension: return 3
        case .elliottCorrection, .trianglePattern: return 4
        case .elliottImpulse: return 6
        case .headShoulders: return 7
        case .path: return 12
        default: return 2
        }
    }

    /// Placed point by point (taps, or one drag per point).
    var isMultiPoint: Bool { pointsNeeded > 2 }

    var hint: String {
        switch self {
        case .longPosition, .shortPosition: return "Kéo từ giá vào lệnh đến giá cắt lỗ"
        case .fibRetracement: return "Kéo từ đáy/đỉnh đầu sóng đến cuối sóng"
        case .fibExtension: return "Chạm 3 điểm: đầu sóng, cuối sóng, điểm hồi"
        case .elliottImpulse: return "Chạm 6 điểm: 0, 1, 2, 3, 4, 5"
        case .elliottCorrection: return "Chạm 4 điểm: 0, A, B, C"
        case .headShoulders: return "Chạm 7 điểm: đầu, vai trái, cổ, đầu, cổ, vai phải, cuối"
        case .trianglePattern: return "Chạm 4 điểm: A, B, C, D"
        case .fixedRangeVolume: return "Kéo từ nến đầu đến nến cuối của vùng"
        case .anchoredVolume: return "Chạm vào nến bắt đầu"
        case .rectangle, .ellipse: return "Kéo từ góc này sang góc đối diện"
        case .priceRange: return "Kéo từ điểm đầu đến điểm cuối để đo"
        case .trendLine, .trendRay, .arrow, .arrowMarker: return "Kéo từ điểm đầu đến điểm cuối"
        case .brush: return "Kéo ngón tay để vẽ"
        case .path: return "Chạm từng điểm, chạm lại điểm cuối để xong"
        default: return "Chạm hoặc kéo tới chỗ cần đặt"
        }
    }

    /// Lines whose width and dash can be changed and that can carry a label.
    var isLine: Bool {
        switch self {
        case .trendLine, .trendRay, .horizontalLine, .horizontalRay, .verticalLine, .rectangle,
             .arrow, .path, .brush, .ellipse, .elliottImpulse, .elliottCorrection, .headShoulders, .trianglePattern,
             .fibRetracement, .fibExtension, .priceRange:
            return true
        default: return false
        }
    }

    /// Sections of the drawing tools sheet, like TradingView's.
    struct Category: Identifiable {
        var id: String { title }
        var title: String
        var tools: [DrawingTool]
    }

    static let categories: [Category] = [
        Category(title: "Công cụ xu hướng", tools: [.trendLine, .trendRay, .horizontalLine, .horizontalRay, .verticalLine]),
        Category(title: "Gann và Fibonacci", tools: [.fibRetracement, .fibExtension]),
        Category(title: "Mô hình", tools: [.elliottImpulse, .elliottCorrection, .headShoulders, .trianglePattern]),
        Category(title: "Dự đoán và đo lường", tools: [.longPosition, .shortPosition, .fixedRangeVolume, .anchoredVolume, .priceRange]),
        Category(title: "Hình học", tools: [.brush, .rectangle, .arrow, .ellipse, .path, .arrowMarker]),
        Category(title: "Lưu ý", tools: [.text]),
    ]
}

enum LineStyle: String, Codable, CaseIterable {
    case solid, dashed, dotted

    var title: String {
        switch self {
        case .solid: return "Liền"
        case .dashed: return "Gạch"
        case .dotted: return "Chấm"
        }
    }

    var dash: [CGFloat] {
        switch self {
        case .solid: return []
        case .dashed: return [6, 4]
        case .dotted: return [1.5, 3]
        }
    }
}

/// Where a drawing's text sits along it.
enum TextAlign: String, Codable, CaseIterable {
    case left, center, right

    var title: String {
        switch self {
        case .left: return "Trái"
        case .center: return "Giữa"
        case .right: return "Phải"
        }
    }
}

/// One Fibonacci level: shown or not, its value and an optional own colour.
struct FibLevel: Codable, Hashable, Identifiable {
    var id = UUID()
    var value: Double
    var enabled = true
    var color: RGBAColor?
}

/// Fibonacci settings like TradingView's "Fib thoái lui" sheet.
struct FibSettings: Codable, Hashable {
    enum Extend: String, Codable, CaseIterable {
        case none, left, right, both
        var title: String {
            switch self {
            case .none: return "Đừng mở rộng"
            case .left: return "Sang trái"
            case .right: return "Sang phải"
            case .both: return "Cả hai bên"
            }
        }
    }

    var levels: [FibLevel]
    var showTrendLine = true
    var extend = Extend.none
    var background = true
    var backgroundOpacity = 0.12
    var reverse = false
    var showPrices = true
    var showLevels = true
    var labelsLeft = true
    /// One colour for every level (nil = each level's own / the default palette).
    var singleColor: RGBAColor?
    /// ICT's OTE zone (0.62–0.79) shaded on a retracement.
    var oteZone = true

    static func defaults(for tool: DrawingTool) -> FibSettings {
        if tool == .fibExtension {
            return FibSettings(levels: [0, 0.618, 1, 1.272, 1.618, 2, 2.618, 3.618].map { FibLevel(value: $0) })
        }
        // 1 = first point, 0 = second point; negative = targets beyond the second point.
        let shown: [Double] = [1, 0.79, 0.705, 0.62, 0.5, 0, -0.27, -0.62, -1]
        let all: [Double] = [1, 0.886, 0.79, 0.705, 0.62, 0.5, 0.382, 0.236, 0, -0.27, -0.62, -1, -1.618, -2.618]
        return FibSettings(levels: all.map { FibLevel(value: $0, enabled: shown.contains($0)) },
                           background: false)
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
    var lineStyle = LineStyle.solid
    /// Colour picked with the colour picker; overrides `colorIndex`.
    var customColor: RGBAColor?
    /// Locked drawings can be selected but not moved.
    var locked = false
    var textAlign = TextAlign.right
    /// Fibonacci tools: levels and look (nil = defaults).
    var fib: FibSettings?

    /// The Fibonacci settings in use.
    var fibSettings: FibSettings { fib ?? FibSettings.defaults(for: tool) }

    init(tool: DrawingTool, points: [ChartPoint]) {
        self.tool = tool
        self.points = points
        if tool == .longPosition { colorIndex = 2 }
        if tool == .shortPosition { colorIndex = 1 }
        if tool == .fibRetracement || tool == .fibExtension { colorIndex = 5 }
        if tool == .headShoulders || tool == .trianglePattern { colorIndex = 4 }
        if tool == .fixedRangeVolume || tool == .anchoredVolume { colorIndex = 0 }
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
        lineStyle = try c.decodeIfPresent(LineStyle.self, forKey: .lineStyle) ?? .solid
        customColor = try c.decodeIfPresent(RGBAColor.self, forKey: .customColor)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        textAlign = try c.decodeIfPresent(TextAlign.self, forKey: .textAlign) ?? .right
        fib = try c.decodeIfPresent(FibSettings.self, forKey: .fib)
    }

    var color: Color { customColor?.color ?? DrawingPalette.colors[colorIndex % DrawingPalette.colors.count] }

    /// A copy a few bars later, for "Nhân bản".
    func cloned(shift: TimeInterval) -> Drawing {
        var copy = self
        copy.id = UUID()
        copy.locked = false
        copy.points = points.map { ChartPoint(time: $0.time.addingTimeInterval(shift), price: $0.price) }
        return copy
    }

    /// Price levels of a position: entry, stop, target.
    var positionLevels: (entry: Double, stop: Double, target: Double)? {
        guard tool == .longPosition || tool == .shortPosition, points.count >= 2 else { return nil }
        let entry = points[0].price
        let stop = points[1].price
        return (entry, stop, entry + riskReward * (entry - stop))
    }

    /// Fibonacci levels with ICT's OTE zone (0.62 – 0.79) and targets below 0.
    static let fibLevels: [Double] = [1, 0.79, 0.705, 0.62, 0.5, 0, -0.27, -0.62, -1]

    /// Trend-based extension: levels from the third point by the first leg.
    static let fibExtensionLevels: [Double] = [0, 0.618, 1, 1.272, 1.618, 2, 2.618]

    func fibExtensionPrice(_ level: Double) -> Double? {
        guard points.count >= 3 else { return nil }
        return points[2].price + (points[1].price - points[0].price) * level
    }

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

/// The look of a drawing: kept per tool for the next drawing, and as named templates.
struct DrawingStyle: Codable, Hashable {
    var colorIndex: Int
    var customColor: RGBAColor?
    var lineWidth: Double
    var lineStyle: LineStyle
    var riskReward: Double
    var textAlign: TextAlign?
    var fib: FibSettings?
}

extension Drawing {
    var style: DrawingStyle {
        get { DrawingStyle(colorIndex: colorIndex, customColor: customColor, lineWidth: lineWidth, lineStyle: lineStyle,
                           riskReward: riskReward, textAlign: textAlign, fib: fib) }
        set {
            colorIndex = newValue.colorIndex
            customColor = newValue.customColor
            lineWidth = newValue.lineWidth
            lineStyle = newValue.lineStyle
            riskReward = newValue.riskReward
            if let align = newValue.textAlign { textAlign = align }
            // Fibonacci settings only apply between Fibonacci tools.
            if tool == .fibRetracement || tool == .fibExtension { fib = newValue.fib }
        }
    }
}

/// Last style used per tool (new drawings start with it) and named templates per tool.
enum DrawingStyles {
    struct Template: Codable, Identifiable, Hashable {
        var id = UUID()
        var name: String
        var style: DrawingStyle
    }

    private static func defaultKey(_ tool: DrawingTool) -> String { "drawing.style.\(tool.rawValue)" }
    /// Lines of every kind share their templates: one saved on a trend line serves a ray or a level too.
    private static let lineTools: [DrawingTool] = [.trendLine, .trendRay, .horizontalLine, .horizontalRay, .verticalLine, .arrow]
    private static func group(_ tool: DrawingTool) -> [DrawingTool] { lineTools.contains(tool) ? lineTools : [tool] }
    private static func templatesKey(_ tool: DrawingTool) -> String {
        lineTools.contains(tool) ? "drawing.templates.lines" : "drawing.templates.\(tool.rawValue)"
    }
    /// Templates kept per tool by earlier versions (read along with the shared ones).
    private static func legacyKeys(_ tool: DrawingTool) -> [String] {
        lineTools.contains(tool) ? lineTools.map { "drawing.templates.\($0.rawValue)" } : []
    }
    private static func read(_ key: String) -> [Template] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Template].self, from: $0) } ?? []
    }

    static func defaultStyle(for tool: DrawingTool) -> DrawingStyle? {
        UserDefaults.standard.data(forKey: defaultKey(tool)).flatMap { try? JSONDecoder().decode(DrawingStyle.self, from: $0) }
    }

    static func setDefault(_ style: DrawingStyle?, for tool: DrawingTool) {
        if let style, let data = try? JSONEncoder().encode(style) {
            UserDefaults.standard.set(data, forKey: defaultKey(tool))
        } else {
            UserDefaults.standard.removeObject(forKey: defaultKey(tool))
        }
    }

    static func templates(for tool: DrawingTool) -> [Template] {
        var list = read(templatesKey(tool))
        for key in legacyKeys(tool) {
            for t in read(key) where !list.contains(where: { $0.name == t.name }) { list.append(t) }
        }
        return list
    }

    static func saveTemplate(name: String, style: DrawingStyle, for tool: DrawingTool) {
        var list = read(templatesKey(tool)).filter { $0.name != name }
        list.insert(Template(name: name, style: style), at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: templatesKey(tool))
        for key in legacyKeys(tool) { remove(from: key) { $0.name == name } }
    }

    static func deleteTemplate(_ template: Template, for tool: DrawingTool) {
        for key in [templatesKey(tool)] + legacyKeys(tool) { remove(from: key) { $0.id == template.id || $0.name == template.name } }
    }

    private static func remove(from key: String, where match: (Template) -> Bool) {
        let list = read(key)
        guard list.contains(where: match) else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(list.filter { !match($0) }), forKey: key)
    }

    /// The template the next drawing of `tool` starts with (picked before drawing it).
    static func useForNext(_ template: Template, tool: DrawingTool) {
        var style = defaultStyle(for: tool) ?? template.style
        style.colorIndex = template.style.colorIndex
        style.customColor = template.style.customColor
        style.lineWidth = template.style.lineWidth
        style.lineStyle = template.style.lineStyle
        if group(tool).count == 1 { style = template.style }
        setDefault(style, for: tool)
    }

    /// Whether the next drawing of `tool` already starts with `template`'s look.
    static func isNext(_ template: Template, tool: DrawingTool) -> Bool {
        guard let style = defaultStyle(for: tool) else { return false }
        return style.colorIndex == template.style.colorIndex && style.customColor == template.style.customColor
            && style.lineWidth == template.style.lineWidth && style.lineStyle == template.style.lineStyle
    }
}

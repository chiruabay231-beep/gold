import SwiftUI
import UIKit

/// A colour that can be saved as JSON.
struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// The chart background chosen in Cài đặt ("" = the theme's own).
enum ChartBackground {
    static let key = "live.chartBackground"

    static func decode(_ json: String) -> Color? {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let color = try? JSONDecoder().decode(RGBAColor.self, from: data) else { return nil }
        return color.color
    }

    static func encode(_ color: Color?) -> String {
        guard let color, let data = try? JSONEncoder().encode(RGBAColor(color)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Quick picks: name, colour, for the light (true) or dark theme.
    static let presets: [(String, Color, Bool)] = [
        ("Trắng", .white, true),
        ("Kem", Color(red: 0.99, green: 0.97, blue: 0.92), true),
        ("Xám nhạt", Color(red: 0.95, green: 0.96, blue: 0.97), true),
        ("Đen", Color(red: 0.06, green: 0.07, blue: 0.08), false),
        ("Xanh đêm", Color(red: 0.07, green: 0.09, blue: 0.16), false),
        ("Xám đậm", Color(red: 0.13, green: 0.14, blue: 0.16), false),
    ]
}

/// Candle colours like TradingView's "Symbol" settings: body, border and
/// wick, each with an up and a down colour and an on/off switch.
struct CandleColors: Codable, Hashable {
    var upBody: RGBAColor
    var downBody: RGBAColor
    var upBorder: RGBAColor
    var downBorder: RGBAColor
    var upWick: RGBAColor
    var downWick: RGBAColor
    var showBody = true
    var showBorder = true
    var showWick = true
    /// Colour a bar by its close against the previous bar's close instead of its own open.
    var colorByPreviousClose = false

    static func standard(for theme: ChartTheme) -> CandleColors {
        let up = RGBAColor(theme.up), down = RGBAColor(theme.down)
        return CandleColors(upBody: up, downBody: down, upBorder: up, downBorder: down, upWick: up, downWick: down)
    }

    /// Colours offered next to the system colour picker, TradingView's palette.
    static let swatches: [Color] = [
        Color(red: 0.031, green: 0.6, blue: 0.506), Color(red: 0.949, green: 0.212, blue: 0.271),
        Color(red: 0.055, green: 0.796, blue: 0.506), Color(red: 0.965, green: 0.275, blue: 0.365),
        Color(red: 0.161, green: 0.384, blue: 1.0), Color(red: 1.0, green: 0.596, blue: 0.0),
        Color(red: 0.612, green: 0.153, blue: 0.69), Color(red: 0.941, green: 0.725, blue: 0.043),
        .black, Color(red: 0.471, green: 0.482, blue: 0.525), .white,
    ]
}

/// Lot size of a long/short position drawing from account size and risk.
struct PositionSizing: Hashable {
    var balance: Double
    var riskPercent: Double
    /// Units per lot: 100 oz for XAUUSD, 100 000 for forex.
    var contractSize: Double

    func lots(entry: Double, stop: Double) -> Double? {
        let distance = abs(entry - stop)
        guard balance > 0, riskPercent > 0, contractSize > 0, distance > 0 else { return nil }
        return balance * riskPercent / 100 / (distance * contractSize)
    }
}

/// Time zones offered in chart settings; "" follows the device.
enum ChartTimeZones {
    static let options: [(id: String, title: String)] = [
        ("", "Theo máy"),
        ("UTC", "UTC (giờ server Exness)"),
        ("Asia/Ho_Chi_Minh", "(UTC+7) Hà Nội, Bangkok"),
        ("America/New_York", "New York (giờ ICT)"),
        ("Europe/London", "London"),
        ("Asia/Tokyo", "Tokyo"),
        ("Australia/Sydney", "Sydney"),
    ]

    static func zone(_ id: String) -> TimeZone {
        id.isEmpty ? .current : (TimeZone(identifier: id) ?? .current)
    }
}

extension CandleColors {
    /// Reads colours saved as JSON in AppStorage; nil = theme default.
    static func decode(_ json: String) -> CandleColors? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CandleColors.self, from: data)
    }

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

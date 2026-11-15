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

/// Candles, indicator lines and drawings that stand out from the chart background (Cài đặt → "Nổi bật"),
/// like the website: a colour too close to the background moves away from it in lightness (its hue kept,
/// a coloured one made vivid); a body still near the background gets a dark or light edge.
enum StandOut {
    static let key = "live.standOut"

    private static var cache: [String: RGBAColor] = [:]

    static func luminance(_ c: RGBAColor) -> Double {
        func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.red) + 0.7152 * f(c.green) + 0.0722 * f(c.blue)
    }

    static func contrast(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func hsl(_ c: RGBAColor) -> (h: Double, s: Double, l: Double) {
        let mx = max(c.red, c.green, c.blue), mn = min(c.red, c.green, c.blue), l = (mx + mn) / 2, d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == c.red { h = ((c.green - c.blue) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.green { h = (c.blue - c.red) / d + 2 }
        else { h = (c.red - c.green) / d + 4 }
        h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        return (h, s, l)
    }

    static func rgb(h: Double, s: Double, l: Double, alpha: Double) -> RGBAColor {
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGBAColor(red: min(1, max(0, r + m)), green: min(1, max(0, g + m)), blue: min(1, max(0, b + m)), alpha: alpha)
    }

    /// The colour moved in lightness until its contrast with the background is at least `minimum`.
    static func adjust(_ c: RGBAColor, on bg: RGBAColor, minimum: Double = 3) -> RGBAColor {
        let solid = RGBAColor(red: c.red, green: c.green, blue: c.blue)
        if contrast(solid, bg) >= minimum { return c }
        let (h, s, l) = hsl(solid)
        let s2 = s > 0.15 ? max(s, 0.8) : s
        let ways: [Double] = luminance(solid) >= luminance(bg) ? [1, -1] : [-1, 1]
        for dir in ways {
            var t = 0.02
            while t <= 1.001 {
                let nl = l + dir * t
                if nl < 0 || nl > 1 { break }
                let m = rgb(h: h, s: s2, l: nl, alpha: c.alpha)
                if contrast(m, bg) >= minimum { return m }
                t += 0.02
            }
        }
        let white = RGBAColor(red: 1, green: 1, blue: 1), black = RGBAColor(red: 0, green: 0, blue: 0)
        var end = contrast(white, bg) > contrast(black, bg) ? white : black
        end.alpha = c.alpha
        return end
    }

    private static func key(_ c: RGBAColor, _ bg: RGBAColor, _ tag: String) -> String {
        String(format: "%@%.3f,%.3f,%.3f,%.3f|%.3f,%.3f,%.3f", tag, c.red, c.green, c.blue, c.alpha, bg.red, bg.green, bg.blue)
    }

    /// A line's colour (indicator, drawing): moved off the background, a see-through one a little stronger.
    static func line(_ color: Color, on background: Color) -> Color {
        let c = RGBAColor(color), bg = RGBAColor(background)
        guard c.alpha >= 0.2 else { return color }
        let k = key(c, bg, "l")
        if let hit = cache[k] { return hit.color }
        var out = adjust(c, on: bg)
        if out.alpha < 1 { out.alpha = min(1, out.alpha * 1.35) }
        if cache.count > 2000 { cache.removeAll() }
        cache[k] = out
        return out.color
    }

    /// The candle colours made to stand out from the background.
    static func candles(_ colors: CandleColors, on background: Color) -> CandleColors {
        let bg = RGBAColor(background)
        var out = colors
        func body(_ c: RGBAColor) -> RGBAColor {
            let k = key(c, bg, "b")
            if let hit = cache[k] { return hit }
            let v = adjust(c, on: bg)
            cache[k] = v
            return v
        }
        out.upBody = body(colors.upBody)
        out.downBody = body(colors.downBody)
        out.upWick = body(colors.upWick)
        out.downWick = body(colors.downWick)
        func edge(_ b: RGBAColor, _ border: RGBAColor) -> (RGBAColor, Bool) {
            let solid = RGBAColor(red: b.red, green: b.green, blue: b.blue)
            guard contrast(solid, bg) < 3.3 else { return (colors.showBorder ? body(border) : b, false) }
            // An edge from the end (black or white) furthest from the body, so its outline shows.
            let black = RGBAColor(red: 0, green: 0, blue: 0), white = RGBAColor(red: 1, green: 1, blue: 1)
            let to = contrast(solid, black) >= contrast(solid, white) ? black : white
            return (RGBAColor(red: b.red + (to.red - b.red) * 0.55, green: b.green + (to.green - b.green) * 0.55,
                              blue: b.blue + (to.blue - b.blue) * 0.55, alpha: b.alpha), true)
        }
        let (upEdge, upNeeds) = edge(out.upBody, colors.upBorder)
        let (downEdge, downNeeds) = edge(out.downBody, colors.downBorder)
        out.upBorder = upEdge
        out.downBorder = downEdge
        if upNeeds || downNeeds { out.showBorder = true }
        return out
    }
}

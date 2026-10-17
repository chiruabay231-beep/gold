import SwiftUI
import BacktestKit

/// ICT overlays for the live chart: key levels with price-axis labels and
/// session boxes (killzones, macros), computed from the candles in New York time.
enum ICTLayers {
    struct Options: Hashable {
        var levels = true
        var killzones = true
        var macros = true
    }

    static let midnightColor = Color(red: 1.0, green: 0.596, blue: 0.0)
    static let amOpenColor = Color(red: 0.612, green: 0.153, blue: 0.69)
    static let previousDayColor = Color(red: 0.949, green: 0.212, blue: 0.271)
    static let asiaColor = Color(red: 0.0, green: 0.588, blue: 0.533)
    static let londonColor = Color(red: 0.161, green: 0.384, blue: 1.0)
    static let newYorkColor = Color(red: 1.0, green: 0.596, blue: 0.0)
    static let macroColor = Color(red: 0.471, green: 0.482, blue: 0.525)

    static func levels(candles: [Candle]) -> [ChartLine] {
        guard candles.count > 2 else { return [] }
        let clock = ICT.NewYorkClock(time: candles.map { $0.time })
        let open = candles.map { $0.open }, high = candles.map { $0.high }, low = candles.map { $0.low }
        let previousDay = ICT.previousDay(high: high, low: low, clock: clock)
        let asia = ICT.asiaRange(high: high, low: low, clock: clock)
        let london = ICT.sessionRange(high: high, low: low, clock: clock,
                                      start: ICT.Session.london.0, end: ICT.Session.london.1)
        func line(_ title: String, _ values: Series, _ color: Color) -> ChartLine {
            ChartLine(title: title, values: values, color: color, axisLabel: true)
        }
        return [
            line("Midnight", ICT.midnightOpen(open: open, clock: clock), midnightColor),
            line("AM Open", ICT.openAt(open: open, clock: clock, hour: 9.5), amOpenColor),
            line("Prev Day High", previousDay.high, previousDayColor),
            line("Prev Day Low", previousDay.low, previousDayColor),
            line("Asian High", asia.high, asiaColor),
            line("Asian Low", asia.low, asiaColor),
            line("London High", london.high, londonColor),
            line("London Low", london.low, londonColor),
        ]
    }

    static func sessions(candles: [Candle], barInterval: TimeInterval, options: Options) -> [SessionBox] {
        guard candles.count > 2, barInterval <= 3600 else { return [] }
        let clock = ICT.NewYorkClock(time: candles.map { $0.time })
        var boxes: [SessionBox] = []
        func add(_ name: String, _ hours: (Double, Double), _ color: Color, _ style: SessionBox.Style, timeLabel: Bool) {
            for window in ICT.sessionWindows(clock: clock, start: hours.0, end: hours.1) {
                let slice = candles[window]
                guard let high = slice.map(\.high).max(), let low = slice.map(\.low).min() else { continue }
                var label = name
                if timeLabel {
                    let start = candles[window.lowerBound].time
                    let end = candles[window.upperBound].time.addingTimeInterval(barInterval)
                    label = "\(start.formatted(date: .omitted, time: .shortened)) - \(end.formatted(date: .omitted, time: .shortened))"
                }
                boxes.append(SessionBox(id: "\(name)-\(window.lowerBound)", range: window, high: high, low: low,
                                        label: label, color: color, style: style))
            }
        }
        if options.killzones {
            add("Asia", ICT.Session.asia, asiaColor, .filled, timeLabel: false)
            add("London KZ", ICT.Session.london, londonColor, .filled, timeLabel: false)
            add("NY AM KZ", ICT.Session.newYorkAM, newYorkColor, .filled, timeLabel: false)
        }
        if options.macros, barInterval <= 900 {
            for (index, macro) in ICT.Session.macros.enumerated() {
                add("Macro \(index)", macro, macroColor, .dotted, timeLabel: true)
            }
        }
        return boxes
    }
}

/// Remembers the last computed layers so they are not rebuilt on every price tick.
final class ICTLayerCache {
    private var key: String?
    private var cachedLevels: [ChartLine] = []
    private var cachedSessions: [SessionBox] = []

    func layers(candles: [Candle], barInterval: TimeInterval, options: ICTLayers.Options) -> ([ChartLine], [SessionBox]) {
        let newKey = "\(candles.count)-\(candles.first?.time.timeIntervalSince1970 ?? 0)-\(barInterval)-\(options.hashValue)"
        if newKey != key {
            key = newKey
            cachedLevels = options.levels ? ICTLayers.levels(candles: candles) : []
            cachedSessions = ICTLayers.sessions(candles: candles, barInterval: barInterval, options: options)
        }
        return (cachedLevels, cachedSessions)
    }
}

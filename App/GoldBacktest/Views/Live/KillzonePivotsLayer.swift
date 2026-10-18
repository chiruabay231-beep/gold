import SwiftUI
import BacktestKit

/// Settings of the "ICT Killzones + Pivots [TFO]" layer: the calculation
/// settings plus colours and line styles. Saved as JSON in AppStorage.
struct KillzonePivotsSettings: Codable, Hashable {
    var config = KillzonePivots.Config()
    var sessionColors: [RGBAColor] = [
        RGBAColor(red: 0.161, green: 0.384, blue: 1.0),     // Asia, blue
        RGBAColor(red: 0.949, green: 0.212, blue: 0.271),   // London, red
        RGBAColor(red: 0.031, green: 0.6, blue: 0.506),     // NY AM, green
        RGBAColor(red: 0.98, green: 0.75, blue: 0.0),       // NY Lunch, yellow
        RGBAColor(red: 0.612, green: 0.153, blue: 0.69),    // NY PM, purple
    ]
    var boxOpacity = 0.12
    var showBoxBorder = false
    var pivotWidth = 1.0
    var pivotStyle = LineStyle.solid
    var mitigatedStyle = LineStyle.dotted
    var openColors: [RGBAColor] = Array(repeating: RGBAColor(red: 0.471, green: 0.482, blue: 0.525), count: 4)
    var openStyle = LineStyle.dashed
    var timestampColor = RGBAColor(red: 0.471, green: 0.482, blue: 0.525)
    var timestampStyle = LineStyle.dotted
    var periodColor = RGBAColor(red: 0.075, green: 0.090, blue: 0.133)
    var labelColor = RGBAColor(red: 0.471, green: 0.482, blue: 0.525)

    static let storageKey = "live.killzonePivots"

    init() {}

    // Missing keys keep their defaults so saved settings survive new options.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KillzonePivotsSettings()
        config = try c.decodeIfPresent(KillzonePivots.Config.self, forKey: .config) ?? d.config
        sessionColors = try c.decodeIfPresent([RGBAColor].self, forKey: .sessionColors) ?? d.sessionColors
        boxOpacity = try c.decodeIfPresent(Double.self, forKey: .boxOpacity) ?? d.boxOpacity
        showBoxBorder = try c.decodeIfPresent(Bool.self, forKey: .showBoxBorder) ?? d.showBoxBorder
        pivotWidth = try c.decodeIfPresent(Double.self, forKey: .pivotWidth) ?? d.pivotWidth
        pivotStyle = try c.decodeIfPresent(LineStyle.self, forKey: .pivotStyle) ?? d.pivotStyle
        mitigatedStyle = try c.decodeIfPresent(LineStyle.self, forKey: .mitigatedStyle) ?? d.mitigatedStyle
        openColors = try c.decodeIfPresent([RGBAColor].self, forKey: .openColors) ?? d.openColors
        openStyle = try c.decodeIfPresent(LineStyle.self, forKey: .openStyle) ?? d.openStyle
        timestampColor = try c.decodeIfPresent(RGBAColor.self, forKey: .timestampColor) ?? d.timestampColor
        timestampStyle = try c.decodeIfPresent(LineStyle.self, forKey: .timestampStyle) ?? d.timestampStyle
        periodColor = try c.decodeIfPresent(RGBAColor.self, forKey: .periodColor) ?? d.periodColor
        labelColor = try c.decodeIfPresent(RGBAColor.self, forKey: .labelColor) ?? d.labelColor
    }

    static func decode(_ json: String) -> KillzonePivotsSettings {
        guard let data = json.data(using: .utf8), !json.isEmpty,
              let settings = try? JSONDecoder().decode(KillzonePivotsSettings.self, from: data) else { return KillzonePivotsSettings() }
        return settings
    }

    var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func sessionColor(_ index: Int) -> Color {
        sessionColors.indices.contains(index) ? sessionColors[index].color : .gray
    }

    func openColor(_ index: Int) -> Color {
        openColors.indices.contains(index) ? openColors[index].color : .gray
    }
}

/// What the chart draws for the layer.
struct KillzonePivotsLayer {
    var boxes: [SessionBox] = []
    var segments: [ChartSegment] = []
    var verticalLines: [ChartVerticalLine] = []
    var notes: [ChartNote] = []
    var output = KillzonePivots.Output()

    static let weekdays = ["", "CN", "T2", "T3", "T4", "T5", "T6", "T7"]

    init() {}

    init(candles: [Candle], barInterval: TimeInterval, settings: KillzonePivotsSettings) {
        let config = settings.config
        output = KillzonePivots.compute(candles: candles, barInterval: barInterval, config: config)
        for box in output.boxes {
            let session = config.sessions[box.session]
            boxes.append(SessionBox(id: "kz-\(box.session)-\(box.range.lowerBound)", range: box.range, high: box.high, low: box.low,
                                    label: config.showBoxLabels ? session.name : "", color: settings.sessionColor(box.session),
                                    style: .filled, fillOpacity: settings.boxOpacity, showBorder: settings.showBoxBorder))
        }
        for level in output.levels {
            var segment = ChartSegment(start: Double(level.start), end: level.end.map(Double.init), price: level.price,
                                       color: .gray, label: level.label)
            switch level.kind {
            case .pivotHigh(let s), .pivotLow(let s):
                segment.color = settings.sessionColor(s)
                segment.width = CGFloat(settings.pivotWidth)
                segment.dash = (level.mitigated ? settings.mitigatedStyle : settings.pivotStyle).dash
                if !config.showPivotLabels { segment.label = "" }
            case .midpoint(let s):
                segment.color = settings.sessionColor(s).opacity(0.8)
                segment.dash = LineStyle.dotted.dash
            case .open(let m):
                segment.color = settings.openColor(m)
                segment.dash = settings.openStyle.dash
            case .previousDay, .previousWeek, .previousMonth:
                segment.color = settings.periodColor.color
                segment.dash = LineStyle.dashed.dash
            }
            segments.append(segment)
        }
        for stamp in output.stamps {
            verticalLines.append(ChartVerticalLine(index: stamp.index, color: settings.timestampColor.color.opacity(0.8),
                                                   dash: settings.timestampStyle.dash.isEmpty ? [] : settings.timestampStyle.dash))
        }
        for label in output.dayLabels {
            notes.append(ChartNote(index: label.index, text: Self.weekdays[label.weekday], color: settings.labelColor.color))
        }
    }
}

/// Rebuilds the layer only when the bars or settings change, not on every price tick.
final class KillzonePivotsCache {
    private var key: String?
    private var cached = KillzonePivotsLayer()
    private var settingsJSON: String?
    private var cachedSettings = KillzonePivotsSettings()

    /// Decoded settings, re-read only when the saved JSON changes.
    func settings(json: String) -> KillzonePivotsSettings {
        if json != settingsJSON {
            settingsJSON = json
            cachedSettings = KillzonePivotsSettings.decode(json)
        }
        return cachedSettings
    }

    func layer(candles: [Candle], barInterval: TimeInterval, settings: KillzonePivotsSettings, enabled: Bool) -> KillzonePivotsLayer {
        guard enabled else { return KillzonePivotsLayer() }
        // The forming bar's high/low can mitigate pivots, so it is part of the key.
        let last = candles.last
        let newKey = "\(candles.count)-\(candles.first?.time.timeIntervalSince1970 ?? 0)-\(last?.high ?? 0)-\(last?.low ?? 0)-\(barInterval)-\(settings.hashValue)"
        if newKey != key {
            key = newKey
            cached = KillzonePivotsLayer(candles: candles, barInterval: barInterval, settings: settings)
        }
        return cached
    }
}

/// Session range table (TFO's range table): latest range and the average of recent sessions.
struct KillzoneRangeTable: View {
    let layer: KillzonePivotsLayer
    let settings: KillzonePivotsSettings
    let decimals: Int
    let theme: ChartTheme

    var body: some View {
        if !layer.output.ranges.isEmpty {
            Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("Phiên").gridColumnAlignment(.leading)
                    Text("Biên độ")
                    Text("TB \(settings.config.rangeAverageCount)")
                }
                .foregroundColor(theme.text)
                ForEach(layer.output.ranges, id: \.session) { stat in
                    GridRow {
                        Text(settings.config.sessions[stat.session].name)
                            .foregroundColor(settings.sessionColor(stat.session))
                            .gridColumnAlignment(.leading)
                        Text(CandleChart.format(stat.latest, decimals))
                        Text(CandleChart.format(stat.average, decimals))
                    }
                    .foregroundColor(theme.primaryText)
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .padding(6)
            .background(theme.background.opacity(0.9), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.grid, lineWidth: 1))
        }
    }
}

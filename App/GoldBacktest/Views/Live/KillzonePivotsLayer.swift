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
    var macroColor = RGBAColor(red: 0.471, green: 0.482, blue: 0.525)
    var fvgBullColor = RGBAColor(red: 0.031, green: 0.6, blue: 0.506)
    var fvgBearColor = RGBAColor(red: 0.949, green: 0.212, blue: 0.271)
    var fvgOpacity = 0.22
    /// Gaps that line up with a higher-timeframe gap: background and 50% line.
    var fvgZoneColor = RGBAColor(red: 0.55, green: 0.56, blue: 0.6)
    var fvgZoneMidColor = RGBAColor(red: 0.612, green: 0.153, blue: 0.69)
    var mssBullColor = RGBAColor(red: 0.031, green: 0.6, blue: 0.506)
    var mssBearColor = RGBAColor(red: 0.949, green: 0.212, blue: 0.271)
    var sweepColor = RGBAColor(red: 0.98, green: 0.6, blue: 0.0)
    var smtBullColor = RGBAColor(red: 0.031, green: 0.6, blue: 0.506)
    var smtBearColor = RGBAColor(red: 0.949, green: 0.212, blue: 0.271)
    /// Market compared for SMT; empty = automatic (silver for gold…).
    var smtSymbol = ""

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
        macroColor = try c.decodeIfPresent(RGBAColor.self, forKey: .macroColor) ?? d.macroColor
        fvgBullColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fvgBullColor) ?? d.fvgBullColor
        fvgBearColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fvgBearColor) ?? d.fvgBearColor
        fvgOpacity = try c.decodeIfPresent(Double.self, forKey: .fvgOpacity) ?? d.fvgOpacity
        fvgZoneColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fvgZoneColor) ?? d.fvgZoneColor
        fvgZoneMidColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fvgZoneMidColor) ?? d.fvgZoneMidColor
        mssBullColor = try c.decodeIfPresent(RGBAColor.self, forKey: .mssBullColor) ?? d.mssBullColor
        mssBearColor = try c.decodeIfPresent(RGBAColor.self, forKey: .mssBearColor) ?? d.mssBearColor
        sweepColor = try c.decodeIfPresent(RGBAColor.self, forKey: .sweepColor) ?? d.sweepColor
        smtBullColor = try c.decodeIfPresent(RGBAColor.self, forKey: .smtBullColor) ?? d.smtBullColor
        smtBearColor = try c.decodeIfPresent(RGBAColor.self, forKey: .smtBearColor) ?? d.smtBearColor
        smtSymbol = try c.decodeIfPresent(String.self, forKey: .smtSymbol) ?? d.smtSymbol
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

    init(candles: [Candle], barInterval: TimeInterval, settings: KillzonePivotsSettings, comparison: [Candle] = [],
         focusIndex: Int? = nil) {
        let config = settings.config
        output = KillzonePivots.compute(candles: candles, barInterval: barInterval, config: config, comparison: comparison,
                                        focusIndex: focusIndex)
        for box in output.boxes {
            let session = config.sessions[box.session]
            boxes.append(SessionBox(id: "kz-\(box.session)-\(box.range.lowerBound)", range: box.range, high: box.high, low: box.low,
                                    label: config.showBoxLabels ? session.name : "", color: settings.sessionColor(box.session),
                                    style: .filled, fillOpacity: settings.boxOpacity, showBorder: settings.showBoxBorder))
        }
        for (k, gap) in output.fvgs.enumerated() {
            // Edges from the gap to the candle that touched it (or the forming one);
            // a gap shared with the higher timeframe also gets a background.
            let color = (gap.bullish ? settings.fvgBullColor : settings.fvgBearColor).color.opacity(gap.touched ? 0.6 : 1)
            let start = Double(gap.start) - 0.5
            let end = Double(max(gap.start, gap.end)) + 0.5
            if gap.confluence {
                boxes.append(SessionBox(id: "fvg-\(k)-\(gap.start)", range: gap.start...max(gap.start, gap.end), high: gap.top,
                                        low: gap.bottom, label: "", color: settings.fvgZoneColor.color, style: .filled,
                                        fillOpacity: settings.fvgOpacity))
            }
            segments.append(ChartSegment(start: start, end: end, price: gap.top, color: color, width: 1.2))
            segments.append(ChartSegment(start: start, end: end, price: gap.bottom, color: color, width: 1.2))
            if config.fvgMidline {
                // 50% (consequent encroachment) line with the name in the middle.
                segments.append(ChartSegment(start: start, end: end, price: gap.mid,
                                             color: gap.confluence ? settings.fvgZoneMidColor.color : color,
                                             width: 1, dash: gap.confluence ? [5, 4] : [1.5, 3],
                                             label: "FVG", centerLabel: true))
            }
        }
        for brk in output.breaks {
            let color = (brk.bullish ? settings.mssBullColor : settings.mssBearColor).color
            segments.append(ChartSegment(start: Double(brk.start), end: Double(brk.end), price: brk.price, color: color,
                                         width: brk.shift ? 1.4 : 1, dash: brk.shift ? [] : [4, 3],
                                         label: brk.shift ? "MSS" : "BOS"))
        }
        for sweep in output.sweeps {
            // A short dashed line from the level to the bar that took it.
            segments.append(ChartSegment(start: Double(max(sweep.levelStart, sweep.index - 12)), end: Double(sweep.index) + 0.5,
                                         price: sweep.price, color: settings.sweepColor.color, width: 1.2, dash: [2, 2],
                                         label: "$ \(sweep.label)"))
        }
        for div in output.smt {
            let color = (div.bullish ? settings.smtBullColor : settings.smtBearColor).color
            segments.append(ChartSegment(start: Double(div.start), end: Double(div.end), price: div.startPrice, color: color,
                                         width: 1.4, label: "SMT", endPrice: div.endPrice))
        }
        for box in output.macroBoxes {
            let macro = config.macros[box.macro]
            let label = config.macroTimeLabels
                ? "\(KillzonePivotsSettingsView.clock(macro.start))–\(KillzonePivotsSettingsView.clock(macro.end))"
                : macro.name
            boxes.append(SessionBox(id: "macro-\(box.macro)-\(box.range.lowerBound)", range: box.range, high: box.high,
                                    low: box.low, label: label, color: settings.macroColor.color, style: .dotted))
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

    /// `focusIndex`: right edge of the screen when scrolled back, so the "days to show"
    /// follow the bars being looked at. It only changes the key every few hours of bars,
    /// so scrolling doesn't recompute on every frame.
    func layer(candles: [Candle], barInterval: TimeInterval, settings: KillzonePivotsSettings, enabled: Bool,
               comparison: [Candle] = [], focusIndex: Int? = nil) -> KillzonePivotsLayer {
        guard enabled else { return KillzonePivotsLayer() }
        let focus = focusIndex.flatMap { candles.indices.contains($0) ? $0 : nil }
        let focusBucket = focus.map { Int(candles[$0].time.timeIntervalSince1970 / 21_600) } ?? -1
        // The forming bar's high/low can mitigate pivots, so it is part of the key.
        let last = candles.last
        let other = comparison.last
        let newKey = "\(candles.count)-\(candles.first?.time.timeIntervalSince1970 ?? 0)-\(last?.high ?? 0)-\(last?.low ?? 0)-\(barInterval)-\(settings.hashValue)"
            + "-\(comparison.count)-\(other?.time.timeIntervalSince1970 ?? 0)-\(other?.high ?? 0)-\(other?.low ?? 0)-\(focusBucket)"
        if newKey != key {
            key = newKey
            cached = KillzonePivotsLayer(candles: candles, barInterval: barInterval, settings: settings, comparison: comparison,
                                         focusIndex: focus)
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


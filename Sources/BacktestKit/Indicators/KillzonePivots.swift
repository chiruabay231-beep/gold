import Foundation

/// ICT killzones with session pivots, modelled on the "ICT Killzones + Pivots"
/// TradingView indicator: session boxes, session highs/lows extended until
/// price trades through them, opening-price lines, vertical timestamps, a
/// daily cutoff time, previous day/week/month highs and lows, day-of-week
/// labels, session range statistics and ICT macro windows. All times are
/// in `timeZoneID`.
public enum KillzonePivots {
    public struct Session: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var name: String
        /// Hours of day, e.g. 9.5 = 09:30. A start after the end wraps past midnight.
        public var start: Double
        public var end: Double
        public var highLabel: String
        public var lowLabel: String

        public init(enabled: Bool = true, name: String, start: Double, end: Double, highLabel: String, lowLabel: String) {
            self.enabled = enabled
            self.name = name
            self.start = start
            self.end = end
            self.highLabel = highLabel
            self.lowLabel = lowLabel
        }
    }

    /// A short ICT "macro" window, drawn as a dotted box on low timeframes.
    public struct Macro: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var name: String
        public var start: Double
        public var end: Double

        public init(enabled: Bool = true, name: String, start: Double, end: Double) {
            self.enabled = enabled
            self.name = name
            self.start = start
            self.end = end
        }
    }

    /// An opening-price line or a vertical timestamp at a time of day.
    public struct TimeMark: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var hour: Double
        public var label: String

        public init(enabled: Bool, hour: Double, label: String) {
            self.enabled = enabled
            self.hour = hour
            self.label = label
        }
    }

    public enum PivotExtension: String, Codable, CaseIterable, Sendable {
        /// The line stops at the bar that trades through it.
        case untilMitigated
        /// The line keeps going and is drawn as mitigated.
        case pastMitigation
    }

    public struct Config: Codable, Hashable, Sendable {
        public var timeZoneID = "America/New_York"
        /// Nothing is drawn on bars longer than this many minutes.
        public var timeframeLimitMinutes = 30.0
        /// Days of history to draw.
        public var maxDays = 3

        public var sessions: [Session] = [
            Session(name: "Asia", start: 20, end: 24, highLabel: "AS.H", lowLabel: "AS.L"),
            Session(name: "London", start: 2, end: 5, highLabel: "LO.H", lowLabel: "LO.L"),
            Session(name: "NY AM", start: 9.5, end: 11, highLabel: "NYAM.H", lowLabel: "NYAM.L"),
            Session(name: "NY Lunch", start: 12, end: 13, highLabel: "NYL.H", lowLabel: "NYL.L"),
            Session(name: "NY PM", start: 13.5, end: 16, highLabel: "NYPM.H", lowLabel: "NYPM.L"),
        ]
        public var showBoxes = true
        public var showBoxLabels = true
        public var showPivots = true
        public var showPivotLabels = true
        public var pivotExtension = PivotExtension.untilMitigated
        public var showMitigated = true
        /// Draw the high/low of a session that is still open, moving with price until it closes.
        public var livePivots = true
        public var showMidpoints = false

        public var opens: [TimeMark] = [
            TimeMark(enabled: true, hour: 0, label: "DO"),
            TimeMark(enabled: false, hour: 8.5, label: "08:30"),
            TimeMark(enabled: true, hour: 9.5, label: "09:30"),
            TimeMark(enabled: false, hour: 13.5, label: "13:30"),
        ]
        public var timestamps: [TimeMark] = [
            TimeMark(enabled: true, hour: 0, label: "00:00"),
            TimeMark(enabled: false, hour: 8.5, label: "08:30"),
            TimeMark(enabled: false, hour: 10, label: "10:00"),
            TimeMark(enabled: false, hour: 14, label: "14:00"),
        ]

        public var cutoffEnabled = false
        public var cutoffHour = 15.0

        public var showPreviousDay = false
        public var showPreviousWeek = false
        public var showPreviousMonth = false
        public var showDayOfWeek = false
        public var showRangeTable = false
        /// Sessions averaged in the range table.
        public var rangeAverageCount = 5

        public var showMacros = true
        /// Macros are only drawn on bars of at most this many minutes.
        public var macroTimeframeLimitMinutes = 15.0
        /// Label macro boxes with their times (true) or names (false).
        public var macroTimeLabels = true
        public var macros: [Macro] = [
            Macro(name: "London 1", start: 2 + 33.0 / 60, end: 3),
            Macro(name: "London 2", start: 4 + 3.0 / 60, end: 4.5),
            Macro(name: "NY AM 1", start: 8 + 50.0 / 60, end: 9 + 10.0 / 60),
            Macro(name: "NY AM 2", start: 9 + 50.0 / 60, end: 10 + 10.0 / 60),
            Macro(name: "NY AM 3", start: 10 + 50.0 / 60, end: 11 + 10.0 / 60),
            Macro(name: "NY Lunch", start: 11 + 50.0 / 60, end: 12 + 10.0 / 60),
            Macro(name: "NY PM", start: 13 + 10.0 / 60, end: 13 + 40.0 / 60),
            Macro(name: "Last Hour", start: 15.25, end: 15.75),
        ]

        /// Fair value gaps (3-candle imbalances): two edge lines and a 50% line,
        /// running from the gap until a candle touches it (or to the last bar).
        public var showFVG = true
        /// FVGs on chart timeframes from … to … minutes (M1 to D1 by default).
        public var fvgFromMinutes = 1.0
        public var fvgToMinutes = 1440.0
        /// Marks gaps that overlap a gap of the next higher timeframe (drawn filled).
        public var fvgConfluence = true
        /// Gaps smaller than this fraction of the average bar range are skipped.
        public var fvgMinSize = 0.0
        /// Hide gaps a candle has already touched.
        public var fvgHideFilled = false
        public var fvgMidline = true
        /// Most recent FVGs kept.
        public var fvgCount = 40
        /// Only gaps made by a strong displacement candle: its body at least
        /// `fvgDisplacement` × the average body of the 20 bars before, in the
        /// gap's direction and at least half of its range.
        public var fvgStrongOnly = true
        public var fvgDisplacement = 1.5

        /// Volume imbalances: two candles in the same direction whose bodies
        /// leave a gap while their wicks overlap. Drawn like FVGs, until touched.
        public var showVI = true
        public var viCount = 20
        public var viHideTouched = false

        /// Market structure: MSS (break against the trend) and optionally BOS.
        public var showMSS = true
        public var showBOS = false
        /// Bars left and right of a swing high/low.
        public var swingLength = 5
        /// Most recent breaks kept.
        public var structureCount = 20

        /// Liquidity sweeps: a wick through a session high/low or the previous
        /// day's high/low that closes back on the other side.
        public var showSweeps = true
        /// Most recent sweeps kept.
        public var sweepCount = 20

        /// SMT divergence against a correlated market (gold vs silver): one makes
        /// a higher high / lower low and the other does not.
        public var showSMT = true
        /// The other market moves the opposite way (e.g. DXY against gold).
        public var smtInverse = false
        /// Bars left and right of a swing used for SMT.
        public var smtSwingLength = 3
        /// The two swings compared are at most this many bars apart.
        public var smtLookback = 60
        /// Most recent divergences kept.
        public var smtCount = 10

        public init() {}

        // Missing keys keep their defaults, so settings saved by an older
        // version still load after new options are added.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Config()
            timeZoneID = try c.decodeIfPresent(String.self, forKey: .timeZoneID) ?? d.timeZoneID
            timeframeLimitMinutes = try c.decodeIfPresent(Double.self, forKey: .timeframeLimitMinutes) ?? d.timeframeLimitMinutes
            maxDays = try c.decodeIfPresent(Int.self, forKey: .maxDays) ?? d.maxDays
            sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? d.sessions
            showBoxes = try c.decodeIfPresent(Bool.self, forKey: .showBoxes) ?? d.showBoxes
            showBoxLabels = try c.decodeIfPresent(Bool.self, forKey: .showBoxLabels) ?? d.showBoxLabels
            showPivots = try c.decodeIfPresent(Bool.self, forKey: .showPivots) ?? d.showPivots
            showPivotLabels = try c.decodeIfPresent(Bool.self, forKey: .showPivotLabels) ?? d.showPivotLabels
            pivotExtension = try c.decodeIfPresent(PivotExtension.self, forKey: .pivotExtension) ?? d.pivotExtension
            showMitigated = try c.decodeIfPresent(Bool.self, forKey: .showMitigated) ?? d.showMitigated
            livePivots = try c.decodeIfPresent(Bool.self, forKey: .livePivots) ?? d.livePivots
            showMidpoints = try c.decodeIfPresent(Bool.self, forKey: .showMidpoints) ?? d.showMidpoints
            opens = try c.decodeIfPresent([TimeMark].self, forKey: .opens) ?? d.opens
            timestamps = try c.decodeIfPresent([TimeMark].self, forKey: .timestamps) ?? d.timestamps
            cutoffEnabled = try c.decodeIfPresent(Bool.self, forKey: .cutoffEnabled) ?? d.cutoffEnabled
            cutoffHour = try c.decodeIfPresent(Double.self, forKey: .cutoffHour) ?? d.cutoffHour
            showPreviousDay = try c.decodeIfPresent(Bool.self, forKey: .showPreviousDay) ?? d.showPreviousDay
            showPreviousWeek = try c.decodeIfPresent(Bool.self, forKey: .showPreviousWeek) ?? d.showPreviousWeek
            showPreviousMonth = try c.decodeIfPresent(Bool.self, forKey: .showPreviousMonth) ?? d.showPreviousMonth
            showDayOfWeek = try c.decodeIfPresent(Bool.self, forKey: .showDayOfWeek) ?? d.showDayOfWeek
            showRangeTable = try c.decodeIfPresent(Bool.self, forKey: .showRangeTable) ?? d.showRangeTable
            rangeAverageCount = try c.decodeIfPresent(Int.self, forKey: .rangeAverageCount) ?? d.rangeAverageCount
            showMacros = try c.decodeIfPresent(Bool.self, forKey: .showMacros) ?? d.showMacros
            macroTimeframeLimitMinutes = try c.decodeIfPresent(Double.self, forKey: .macroTimeframeLimitMinutes) ?? d.macroTimeframeLimitMinutes
            macroTimeLabels = try c.decodeIfPresent(Bool.self, forKey: .macroTimeLabels) ?? d.macroTimeLabels
            macros = try c.decodeIfPresent([Macro].self, forKey: .macros) ?? d.macros
            showFVG = try c.decodeIfPresent(Bool.self, forKey: .showFVG) ?? d.showFVG
            fvgFromMinutes = try c.decodeIfPresent(Double.self, forKey: .fvgFromMinutes) ?? d.fvgFromMinutes
            fvgToMinutes = try c.decodeIfPresent(Double.self, forKey: .fvgToMinutes) ?? d.fvgToMinutes
            fvgConfluence = try c.decodeIfPresent(Bool.self, forKey: .fvgConfluence) ?? d.fvgConfluence
            fvgMinSize = try c.decodeIfPresent(Double.self, forKey: .fvgMinSize) ?? d.fvgMinSize
            fvgHideFilled = try c.decodeIfPresent(Bool.self, forKey: .fvgHideFilled) ?? d.fvgHideFilled
            fvgMidline = try c.decodeIfPresent(Bool.self, forKey: .fvgMidline) ?? d.fvgMidline
            fvgCount = try c.decodeIfPresent(Int.self, forKey: .fvgCount) ?? d.fvgCount
            fvgStrongOnly = try c.decodeIfPresent(Bool.self, forKey: .fvgStrongOnly) ?? d.fvgStrongOnly
            fvgDisplacement = try c.decodeIfPresent(Double.self, forKey: .fvgDisplacement) ?? d.fvgDisplacement
            showVI = try c.decodeIfPresent(Bool.self, forKey: .showVI) ?? d.showVI
            viCount = try c.decodeIfPresent(Int.self, forKey: .viCount) ?? d.viCount
            viHideTouched = try c.decodeIfPresent(Bool.self, forKey: .viHideTouched) ?? d.viHideTouched
            showMSS = try c.decodeIfPresent(Bool.self, forKey: .showMSS) ?? d.showMSS
            showBOS = try c.decodeIfPresent(Bool.self, forKey: .showBOS) ?? d.showBOS
            swingLength = try c.decodeIfPresent(Int.self, forKey: .swingLength) ?? d.swingLength
            structureCount = try c.decodeIfPresent(Int.self, forKey: .structureCount) ?? d.structureCount
            showSweeps = try c.decodeIfPresent(Bool.self, forKey: .showSweeps) ?? d.showSweeps
            sweepCount = try c.decodeIfPresent(Int.self, forKey: .sweepCount) ?? d.sweepCount
            showSMT = try c.decodeIfPresent(Bool.self, forKey: .showSMT) ?? d.showSMT
            smtInverse = try c.decodeIfPresent(Bool.self, forKey: .smtInverse) ?? d.smtInverse
            smtSwingLength = try c.decodeIfPresent(Int.self, forKey: .smtSwingLength) ?? d.smtSwingLength
            smtLookback = try c.decodeIfPresent(Int.self, forKey: .smtLookback) ?? d.smtLookback
            smtCount = try c.decodeIfPresent(Int.self, forKey: .smtCount) ?? d.smtCount
        }
    }

    public struct Box: Hashable, Sendable {
        public var session: Int
        public var range: ClosedRange<Int>
        public var high: Double
        public var low: Double
    }

    /// A horizontal line from `start` to `end` (bar indexes); `end == nil`
    /// extends to the right edge of the chart.
    public struct Level: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case pivotHigh(session: Int)
            case pivotLow(session: Int)
            case midpoint(session: Int)
            case open(mark: Int)
            case previousDay, previousWeek, previousMonth
        }

        public var kind: Kind
        public var price: Double
        public var start: Int
        public var end: Int?
        public var label: String
        public var mitigated: Bool
    }

    public struct MacroBox: Hashable, Sendable {
        public var macro: Int
        public var range: ClosedRange<Int>
        public var high: Double
        public var low: Double
    }

    public struct Stamp: Hashable, Sendable {
        public var mark: Int
        public var index: Int
    }

    public struct DayLabel: Hashable, Sendable {
        public var index: Int
        /// 1 = Sunday … 7 = Saturday.
        public var weekday: Int
    }

    public struct RangeStat: Hashable, Sendable {
        public var session: Int
        /// Range of the latest session (running if it is in progress).
        public var latest: Double
        public var average: Double
    }

    /// A fair value gap between the high and low of the candles around `index`.
    public struct FairValueGap: Hashable, Sendable {
        public var bullish: Bool
        public var top: Double
        public var bottom: Double
        /// Bar where the lines start (the middle, displacement candle).
        public var start: Int
        /// The bar that first touched the gap, or the last bar while untouched.
        public var end: Int
        /// A candle after the gap traded into it.
        public var touched = false
        /// That candle went through the whole gap.
        public var filled = false
        /// The gap overlaps a same-direction gap of the next higher timeframe.
        public var confluence = false
        public var mid: Double { (top + bottom) / 2 }
    }

    /// A close through the last swing high/low. `shift` = against the previous trend (MSS).
    public struct StructureBreak: Hashable, Sendable {
        public var bullish: Bool
        public var shift: Bool
        public var price: Double
        /// Swing bar and breaking bar.
        public var start: Int
        public var end: Int
    }

    /// Price wicked through a liquidity level at `index` and closed back.
    /// `bullish` = sell-side liquidity (a low) was taken.
    public struct Sweep: Hashable, Sendable {
        public var bullish: Bool
        public var price: Double
        /// Bar that formed the level and the sweeping bar.
        public var levelStart: Int
        public var index: Int
        public var label: String
    }

    /// Divergence between two swing highs (bearish) or lows (bullish) of this
    /// market and the comparison market.
    public struct SMTDivergence: Hashable, Sendable {
        public var bullish: Bool
        public var start: Int
        public var end: Int
        public var startPrice: Double
        public var endPrice: Double
    }

    public struct Output: Sendable {
        public var sweeps: [Sweep] = []
        public var smt: [SMTDivergence] = []
        public var fvgs: [FairValueGap] = []
        public var volumeImbalances: [FairValueGap] = []
        public var breaks: [StructureBreak] = []
        public var boxes: [Box] = []
        public var macroBoxes: [MacroBox] = []
        public var levels: [Level] = []
        public var stamps: [Stamp] = []
        public var dayLabels: [DayLabel] = []
        public var ranges: [RangeStat] = []
        /// True when the chart timeframe is above the limit and the killzones are not drawn.
        public var hiddenByTimeframe = false

        public init() {}
    }

    /// `comparison` holds the bars of the SMT market (same timeframe); empty = no SMT.
    /// `focusIndex` is the bar the "days to show" count back from (the right edge of
    /// the screen when scrolled into history); nil = the last bar.
    public static func compute(candles: [Candle], barInterval: TimeInterval, config: Config,
                               comparison: [Candle] = [], focusIndex: Int? = nil) -> Output {
        var output = Output()
        guard candles.count > 2 else { return output }
        if config.showSMT, !comparison.isEmpty {
            output.smt = smtDivergences(candles, comparison, config: config)
        }
        // FVG and structure have their own timeframe rules.
        if config.showFVG, barInterval >= config.fvgFromMinutes * 60 - 1, barInterval <= config.fvgToMinutes * 60 + 1 {
            output.fvgs = fairValueGaps(candles, barInterval: barInterval, config: config)
            if config.showVI { output.volumeImbalances = volumeImbalances(candles, config: config) }
        }
        if config.showMSS || config.showBOS {
            output.breaks = structureBreaks(candles, config: config)
        }
        guard barInterval <= config.timeframeLimitMinutes * 60 else {
            output.hiddenByTimeframe = true
            return output
        }
        let zone = TimeZone(identifier: config.timeZoneID) ?? TimeZone(identifier: "America/New_York")!
        let clock = ICT.NewYorkClock(time: candles.map(\.time), zone: zone)
        let n = candles.count
        let lastDay = clock.day[min(max(focusIndex ?? n - 1, 0), n - 1)]
        let firstDay = lastDay - max(config.maxDays, 1) + 1
        let cutoffs = config.cutoffEnabled ? cutoffIndexes(clock: clock, hour: config.cutoffHour) : []

        /// First cutoff bar after `index`, if the cutoff is on.
        func cutoff(after index: Int) -> Int? {
            cutoffs.first { $0 > index }
        }

        // Sessions: boxes, pivots, midpoints, range statistics.
        for (s, session) in config.sessions.enumerated() where session.enabled {
            let windows = ICT.sessionWindows(clock: clock, start: session.start, end: session.end)
            var ranges: [Double] = []
            for window in windows {
                var high = -Double.infinity, low = Double.infinity
                var highIndex = window.lowerBound, lowIndex = window.lowerBound
                for i in window {
                    if candles[i].high > high { high = candles[i].high; highIndex = i }
                    if candles[i].low < low { low = candles[i].low; lowIndex = i }
                }
                ranges.append(high - low)
                guard clock.day[window.upperBound] >= firstDay else { continue }
                if config.showBoxes {
                    output.boxes.append(Box(session: s, range: window, high: high, low: low))
                }
                // Pivots are fixed once the session has closed; while it is open
                // they can follow its running high/low.
                let closed = window.upperBound < n - 1
                guard closed else {
                    if config.showPivots && config.livePivots {
                        output.levels.append(Level(kind: .pivotHigh(session: s), price: high, start: highIndex, end: nil,
                                                   label: session.highLabel, mitigated: false))
                        output.levels.append(Level(kind: .pivotLow(session: s), price: low, start: lowIndex, end: nil,
                                                   label: session.lowLabel, mitigated: false))
                    }
                    if config.showMidpoints && config.livePivots {
                        output.levels.append(Level(kind: .midpoint(session: s), price: (high + low) / 2, start: window.lowerBound,
                                                   end: window.upperBound, label: "", mitigated: false))
                    }
                    continue
                }
                for isHigh in [true, false] {
                    let price = isHigh ? high : low
                    let mitigation = firstBreak(candles, price: price, isHigh: isHigh, from: window.upperBound + 1)
                    if config.showSweeps, let j = mitigation, isHigh ? candles[j].close < price : candles[j].close > price {
                        output.sweeps.append(Sweep(bullish: !isHigh, price: price, levelStart: isHigh ? highIndex : lowIndex,
                                                   index: j, label: isHigh ? session.highLabel : session.lowLabel))
                    }
                    if config.showPivots {
                        if mitigation != nil && !config.showMitigated { continue }
                        var end: Int? = config.pivotExtension == .untilMitigated ? mitigation : nil
                        if let cut = cutoff(after: window.upperBound), end.map({ cut < $0 }) ?? true { end = cut }
                        output.levels.append(Level(kind: isHigh ? .pivotHigh(session: s) : .pivotLow(session: s), price: price,
                                                   start: isHigh ? highIndex : lowIndex, end: end,
                                                   label: isHigh ? session.highLabel : session.lowLabel,
                                                   mitigated: mitigation != nil))
                    }
                }
                if config.showMidpoints {
                    output.levels.append(Level(kind: .midpoint(session: s), price: (high + low) / 2, start: window.lowerBound,
                                               end: window.upperBound, label: "", mitigated: false))
                }
            }
            if let latest = ranges.last {
                let recent = ranges.suffix(max(config.rangeAverageCount, 1))
                output.ranges.append(RangeStat(session: s, latest: latest, average: recent.reduce(0, +) / Double(recent.count)))
            }
        }

        // Macros: dotted boxes over their few bars, on low timeframes only.
        if config.showMacros, barInterval <= config.macroTimeframeLimitMinutes * 60 {
            for (m, macro) in config.macros.enumerated() where macro.enabled {
                for window in ICT.sessionWindows(clock: clock, start: macro.start, end: macro.end)
                where clock.day[window.upperBound] >= firstDay {
                    let bars = candles[window]
                    output.macroBoxes.append(MacroBox(macro: m, range: window, high: bars.map(\.high).max() ?? 0,
                                                      low: bars.map(\.low).min() ?? 0))
                }
            }
        }

        // Opening prices: from the first bar at or after the time, until the cutoff or the next day's open.
        for (m, mark) in config.opens.enumerated() where mark.enabled {
            let starts = markIndexes(clock: clock, hour: mark.hour, firstDay: firstDay)
            for (k, start) in starts.enumerated() {
                var end: Int? = k + 1 < starts.count ? starts[k + 1] - 1 : nil
                if let cut = cutoff(after: start), end.map({ cut < $0 }) ?? true { end = cut }
                output.levels.append(Level(kind: .open(mark: m), price: candles[start].open, start: start, end: end,
                                           label: mark.label, mitigated: false))
            }
        }

        for (m, mark) in config.timestamps.enumerated() where mark.enabled {
            for index in markIndexes(clock: clock, hour: mark.hour, firstDay: firstDay) {
                output.stamps.append(Stamp(mark: m, index: index))
            }
        }

        // Previous day / week / month highs and lows, drawn across the current period.
        /// High/low of the period before the current one and the first bar of the current period.
        func previousRange(_ id: (Int) -> Int) -> (start: Int, high: Double, highIndex: Int, low: Double, lowIndex: Int)? {
            let current = id(n - 1)
            guard let start = (0..<n).first(where: { id($0) == current }), start > 0 else { return nil }
            let previous = id(start - 1)
            var high = -Double.infinity, low = Double.infinity
            var highIndex = start - 1, lowIndex = start - 1
            var i = start - 1
            while i >= 0, id(i) == previous {
                if candles[i].high > high { high = candles[i].high; highIndex = i }
                if candles[i].low < low { low = candles[i].low; lowIndex = i }
                i -= 1
            }
            guard high.isFinite, low.isFinite else { return nil }
            return (start, high, highIndex, low, lowIndex)
        }
        func previousPeriod(_ id: (Int) -> Int, kind: Level.Kind, labels: (String, String)) {
            guard let range = previousRange(id) else { return }
            output.levels.append(Level(kind: kind, price: range.high, start: range.start, end: nil, label: labels.0, mitigated: false))
            output.levels.append(Level(kind: kind, price: range.low, start: range.start, end: nil, label: labels.1, mitigated: false))
        }
        // Sweeps of the previous day's high/low (the classic ICT liquidity), shown with or without its lines.
        if config.showSweeps, let range = previousRange({ clock.day[$0] }) {
            for isHigh in [true, false] {
                let price = isHigh ? range.high : range.low
                if let j = firstBreak(candles, price: price, isHigh: isHigh, from: range.start),
                   isHigh ? candles[j].close < price : candles[j].close > price {
                    output.sweeps.append(Sweep(bullish: !isHigh, price: price, levelStart: isHigh ? range.highIndex : range.lowIndex,
                                               index: j, label: isHigh ? "PDH" : "PDL"))
                }
            }
        }
        if config.showPreviousDay { previousPeriod({ clock.day[$0] }, kind: .previousDay, labels: ("PDH", "PDL")) }
        if config.showPreviousWeek { previousPeriod({ clock.week[$0] }, kind: .previousWeek, labels: ("PWH", "PWL")) }
        if config.showPreviousMonth {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let months = candles.map { c -> Int in
                let parts = calendar.dateComponents([.year, .month], from: c.time)
                return (parts.year ?? 0) * 12 + (parts.month ?? 0)
            }
            previousPeriod({ months[$0] }, kind: .previousMonth, labels: ("PMH", "PML"))
        }

        if config.showDayOfWeek {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            for index in markIndexes(clock: clock, hour: 12, firstDay: firstDay) {
                output.dayLabels.append(DayLabel(index: index, weekday: calendar.component(.weekday, from: candles[index].time)))
            }
        }
        output.sweeps = Array(output.sweeps.sorted { $0.index < $1.index }.suffix(max(config.sweepCount, 1)))
        return output
    }

    /// First bar from `from` that trades beyond `price`.
    static func firstBreak(_ c: [Candle], price: Double, isHigh: Bool, from: Int) -> Int? {
        guard from < c.count else { return nil }
        return (from..<c.count).first { isHigh ? c[$0].high > price : c[$0].low < price }
    }

    /// SMT divergences between `a` (the chart) and `b` (the comparison market),
    /// matched bar by bar on time. Swings are confirmed `smtSwingLength` bars later.
    public static func smtDivergences(_ a: [Candle], _ b: [Candle], config: Config) -> [SMTDivergence] {
        let length = max(config.smtSwingLength, 1)
        let n = a.count
        guard n > length * 2 + 2, !b.isEmpty else { return [] }
        let other = Dictionary(b.map { ($0.time, $0) }, uniquingKeysWith: { _, new in new })
        // The other market's extreme on the bar and its neighbours, so a swing one bar apart still matches.
        func otherExtreme(_ p: Int, high: Bool) -> Double? {
            let values = (max(0, p - 1)...min(n - 1, p + 1)).compactMap { other[a[$0].time] }.map { high ? $0.high : $0.low }
            return high ? values.max() : values.min()
        }
        var highs: [Int] = [], lows: [Int] = []
        for p in length..<(n - length) {
            let window = (p - length)...(p + length)
            if window.allSatisfy({ $0 == p || a[$0].high < a[p].high }) { highs.append(p) }
            if window.allSatisfy({ $0 == p || a[$0].low > a[p].low }) { lows.append(p) }
        }
        var result: [SMTDivergence] = []
        // Highs: inverse markets are compared at their lows.
        for (i1, i2) in zip(highs, highs.dropFirst()) where i2 - i1 <= config.smtLookback {
            guard let b1 = otherExtreme(i1, high: !config.smtInverse), let b2 = otherExtreme(i2, high: !config.smtInverse) else { continue }
            let higher = a[i2].high > a[i1].high
            let otherHigher = config.smtInverse ? b2 < b1 : b2 > b1
            if higher != otherHigher {
                result.append(SMTDivergence(bullish: false, start: i1, end: i2, startPrice: a[i1].high, endPrice: a[i2].high))
            }
        }
        for (i1, i2) in zip(lows, lows.dropFirst()) where i2 - i1 <= config.smtLookback {
            guard let b1 = otherExtreme(i1, high: config.smtInverse), let b2 = otherExtreme(i2, high: config.smtInverse) else { continue }
            let lower = a[i2].low < a[i1].low
            let otherLower = config.smtInverse ? b2 > b1 : b2 < b1
            if lower != otherLower {
                result.append(SMTDivergence(bullish: true, start: i1, end: i2, startPrice: a[i1].low, endPrice: a[i2].low))
            }
        }
        return Array(result.sorted { $0.end < $1.end }.suffix(max(config.smtCount, 1)))
    }

    /// 3-candle imbalances: a bullish gap when a candle's low is above the high two
    /// candles before, a bearish one the other way round. Each runs until a later
    /// candle touches it; `confluence` when it overlaps a gap of the next timeframe.
    static func fairValueGaps(_ c: [Candle], barInterval: TimeInterval = 0, config: Config) -> [FairValueGap] {
        let n = c.count
        guard n > 3 else { return [] }
        let count = max(config.fvgCount, 1)
        var gaps: [FairValueGap] = []
        // Newest first, so only the gaps that are kept are followed to their touch.
        let displacement = config.fvgStrongOnly ? max(config.fvgDisplacement, 0) : nil
        for raw in rawGaps(c, minSize: config.fvgMinSize, displacement: displacement).reversed() {
            let gap = followed(raw, start: raw.start, formed: raw.start + 1, in: c)
            if gap.touched && config.fvgHideFilled { continue }
            gaps.append(gap)
            if gaps.count == count { break }
        }
        gaps.reverse()
        if config.fvgConfluence, !gaps.isEmpty, let seconds = higherTimeframe(barInterval) {
            let (bars, first) = aggregate(c, seconds: seconds)
            let earliest = gaps[0].start
            var higher: [FairValueGap] = []
            for raw in rawGaps(bars, minSize: config.fvgMinSize) {
                // First chart bar of the middle candle; last chart bar of the third one.
                let start = first[raw.start]
                let formed = raw.start + 3 < first.count ? first[raw.start + 3] - 1 : n - 1
                let gap = followed(raw, start: start, formed: formed, in: c)
                if gap.end >= earliest { higher.append(gap) }
            }
            for k in gaps.indices {
                let g = gaps[k]
                gaps[k].confluence = higher.contains { h in
                    h.bullish == g.bullish && h.bottom < g.top && g.bottom < h.top && h.start <= g.end && g.start <= h.end
                }
            }
        }
        return gaps
    }

    /// Gaps on `c` (bar indexes of `c`): middle candle and zone. With
    /// `displacement`, only gaps whose middle candle is a strong move (see Config.fvgStrongOnly).
    private static func rawGaps(_ c: [Candle], minSize: Double, displacement: Double? = nil) -> [FairValueGap] {
        let n = c.count
        guard n > 2 else { return [] }
        let averageRange = c.suffix(100).reduce(0) { $0 + ($1.high - $1.low) } / Double(min(n, 100))
        let minimum = averageRange * max(minSize, 0)
        // Running sums of bodies for the average body before each bar.
        var bodySums = [0.0]
        for bar in c { bodySums.append(bodySums[bodySums.count - 1] + abs(bar.close - bar.open)) }
        func strong(_ m: Int, bullish: Bool) -> Bool {
            guard let displacement else { return true }
            let bar = c[m]
            let body = abs(bar.close - bar.open)
            guard (bar.close > bar.open) == bullish, body >= (bar.high - bar.low) * 0.5 else { return false }
            let from = max(0, m - 20)
            guard m > from else { return true }
            let average = (bodySums[m] - bodySums[from]) / Double(m - from)
            return body >= average * displacement
        }
        var gaps: [FairValueGap] = []
        for i in 2..<n {
            if c[i].low > c[i - 2].high, c[i].low - c[i - 2].high > minimum, strong(i - 1, bullish: true) {
                gaps.append(FairValueGap(bullish: true, top: c[i].low, bottom: c[i - 2].high, start: i - 1, end: i - 1))
            } else if c[i].high < c[i - 2].low, c[i - 2].low - c[i].high > minimum, strong(i - 1, bullish: false) {
                gaps.append(FairValueGap(bullish: false, top: c[i - 2].low, bottom: c[i].high, start: i - 1, end: i - 1))
            }
        }
        return gaps
    }

    /// Volume imbalances: a bullish one when two up candles leave a gap between the
    /// first close and the second open while their wicks overlap (bearish the other way).
    /// Each runs from the first candle until a later wick touches it.
    static func volumeImbalances(_ c: [Candle], config: Config) -> [FairValueGap] {
        let n = c.count
        guard n > 2 else { return [] }
        let averageRange = c.suffix(100).reduce(0) { $0 + ($1.high - $1.low) } / Double(min(n, 100))
        // Ignore gaps of a tick or two.
        let minimum = averageRange * 0.03
        var found: [FairValueGap] = []
        for i in stride(from: n - 1, through: 1, by: -1) {
            let a = c[i - 1], b = c[i]
            var raw: FairValueGap?
            if a.close > a.open, b.close > b.open, b.open - a.close > minimum, b.low <= a.high {
                raw = FairValueGap(bullish: true, top: b.open, bottom: a.close, start: i - 1, end: i - 1)
            } else if a.close < a.open, b.close < b.open, a.close - b.open > minimum, b.high >= a.low {
                raw = FairValueGap(bullish: false, top: a.close, bottom: b.open, start: i - 1, end: i - 1)
            }
            guard let raw else { continue }
            let gap = followed(raw, start: i - 1, formed: i, in: c)
            if gap.touched && config.viHideTouched { continue }
            found.append(gap)
            if found.count >= max(config.viCount, 1) { break }
        }
        return found.reversed()
    }

    /// The gap placed on the chart bars `c` from `start`, ending at the first bar
    /// after `formed` (the gap's third candle) whose wick reaches it.
    private static func followed(_ raw: FairValueGap, start: Int, formed: Int, in c: [Candle]) -> FairValueGap {
        var gap = raw
        gap.start = start
        gap.end = c.count - 1
        var j = formed + 1
        while j < c.count {
            if raw.bullish ? c[j].low <= raw.top : c[j].high >= raw.bottom {
                gap.touched = true
                gap.filled = raw.bullish ? c[j].low <= raw.bottom : c[j].high >= raw.top
                gap.end = j
                break
            }
            j += 1
        }
        return gap
    }

    /// The timeframe whose gaps are compared with the chart's (M1 → M5, M5 → M15,
    /// M15 → H1, M30 → H4, H1 → H4, H4 → D1, D1 → W1).
    static func higherTimeframe(_ barInterval: TimeInterval) -> TimeInterval? {
        switch barInterval {
        case 59...61: return 300
        case 299...301: return 900
        case 899...901: return 3600
        case 1799...1801: return 14_400
        case 3599...3601: return 14_400
        case 14_399...14_401: return 86_400
        case 86_399...86_401: return 604_800
        default: return nil
        }
    }

    /// Bars of `seconds` built from `c` (UTC buckets; weeks start Monday) and the
    /// index in `c` of each one's first bar.
    static func aggregate(_ c: [Candle], seconds: TimeInterval) -> (bars: [Candle], first: [Int]) {
        // 1970-01-01 was a Thursday: shift weeks by 4 days so they start on Monday.
        let shift: TimeInterval = seconds >= 604_800 ? 345_600 : 0
        var bars: [Candle] = []
        var first: [Int] = []
        var bucket = -Double.infinity
        for (i, bar) in c.enumerated() {
            let b = ((bar.time.timeIntervalSince1970 - shift) / seconds).rounded(.down)
            if b != bucket {
                bucket = b
                bars.append(bar)
                first.append(i)
            } else {
                var last = bars[bars.count - 1]
                last.high = max(last.high, bar.high)
                last.low = min(last.low, bar.low)
                last.close = bar.close
                last.volume += bar.volume
                bars[bars.count - 1] = last
            }
        }
        return (bars, first)
    }

    /// Breaks of swing highs/lows by a close. MSS when the break goes against the
    /// trend set by the previous break, BOS when it continues it.
    public static func structureBreaks(_ c: [Candle], config: Config) -> [StructureBreak] {
        let length = max(config.swingLength, 1)
        let n = c.count
        guard n > length * 2 + 1 else { return [] }
        var activeHigh: (price: Double, index: Int)?
        var activeLow: (price: Double, index: Int)?
        var trend = 0
        var breaks: [StructureBreak] = []
        for i in 0..<n {
            // A swing is confirmed `length` bars after it.
            let p = i - length
            if p >= length {
                let window = (p - length)...(p + length)
                if window.allSatisfy({ $0 == p || c[$0].high < c[p].high }) { activeHigh = (c[p].high, p) }
                if window.allSatisfy({ $0 == p || c[$0].low > c[p].low }) { activeLow = (c[p].low, p) }
            }
            if let high = activeHigh, c[i].close > high.price {
                let shift = trend == -1
                if shift ? config.showMSS : config.showBOS {
                    breaks.append(StructureBreak(bullish: true, shift: shift, price: high.price, start: high.index, end: i))
                }
                trend = 1
                activeHigh = nil
            }
            if let low = activeLow, c[i].close < low.price {
                let shift = trend == 1
                if shift ? config.showMSS : config.showBOS {
                    breaks.append(StructureBreak(bullish: false, shift: shift, price: low.price, start: low.index, end: i))
                }
                trend = -1
                activeLow = nil
            }
        }
        return Array(breaks.suffix(max(config.structureCount, 1)))
    }

    /// First bar of each day (from `firstDay`) at or after `hour`.
    static func markIndexes(clock: ICT.NewYorkClock, hour: Double, firstDay: Int) -> [Int] {
        var result: [Int] = []
        var lastDay = Int.min
        for i in clock.hour.indices where i > 0 && clock.day[i] >= firstDay && clock.day[i] != lastDay && clock.hour[i] >= hour {
            lastDay = clock.day[i]
            // The bar must be at the mark: either the clock crossed it today, or the day
            // starts within an hour of it (not e.g. Sunday's 18:00 open for a 09:30 mark).
            let crossedToday = clock.day[i - 1] == clock.day[i] && clock.hour[i - 1] < hour
            let dayStartsAtMark = clock.day[i - 1] != clock.day[i] && clock.hour[i] < hour + 1
            if crossedToday || dayStartsAtMark { result.append(i) }
        }
        return result
    }

    /// Bars where the clock first reaches the cutoff hour each day.
    static func cutoffIndexes(clock: ICT.NewYorkClock, hour: Double) -> [Int] {
        var result: [Int] = []
        for i in 1..<clock.hour.count where clock.hour[i] >= hour {
            if clock.day[i] != clock.day[i - 1] || clock.hour[i - 1] < hour { result.append(i) }
        }
        return result
    }
}

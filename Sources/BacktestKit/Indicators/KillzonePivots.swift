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

        /// Fair value gaps (3-candle imbalances), drawn as short boxes with a 50% line.
        public var showFVG = true
        /// FVGs only on bars of at least this many minutes (e.g. 5 = M5 and higher).
        public var fvgMinTimeframeMinutes = 5.0
        /// Box length in bars, starting at the candle that makes the gap.
        public var fvgBoxBars = 2
        /// Gaps smaller than this fraction of the average bar range are skipped.
        public var fvgMinSize = 0.0
        public var fvgHideFilled = false
        public var fvgMidline = true
        /// Most recent FVGs kept.
        public var fvgCount = 40

        /// Market structure: MSS (break against the trend) and optionally BOS.
        public var showMSS = true
        public var showBOS = false
        /// Bars left and right of a swing high/low.
        public var swingLength = 5
        /// Most recent breaks kept.
        public var structureCount = 20

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
            fvgMinTimeframeMinutes = try c.decodeIfPresent(Double.self, forKey: .fvgMinTimeframeMinutes) ?? d.fvgMinTimeframeMinutes
            fvgBoxBars = try c.decodeIfPresent(Int.self, forKey: .fvgBoxBars) ?? d.fvgBoxBars
            fvgMinSize = try c.decodeIfPresent(Double.self, forKey: .fvgMinSize) ?? d.fvgMinSize
            fvgHideFilled = try c.decodeIfPresent(Bool.self, forKey: .fvgHideFilled) ?? d.fvgHideFilled
            fvgMidline = try c.decodeIfPresent(Bool.self, forKey: .fvgMidline) ?? d.fvgMidline
            fvgCount = try c.decodeIfPresent(Int.self, forKey: .fvgCount) ?? d.fvgCount
            showMSS = try c.decodeIfPresent(Bool.self, forKey: .showMSS) ?? d.showMSS
            showBOS = try c.decodeIfPresent(Bool.self, forKey: .showBOS) ?? d.showBOS
            swingLength = try c.decodeIfPresent(Int.self, forKey: .swingLength) ?? d.swingLength
            structureCount = try c.decodeIfPresent(Int.self, forKey: .structureCount) ?? d.structureCount
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
        /// Bar where the box starts (the middle, displacement candle).
        public var start: Int
        public var end: Int
        /// Price later traded through the whole gap.
        public var filled: Bool
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

    public struct Output: Sendable {
        public var fvgs: [FairValueGap] = []
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

    public static func compute(candles: [Candle], barInterval: TimeInterval, config: Config) -> Output {
        var output = Output()
        guard candles.count > 2 else { return output }
        // FVG and structure have their own timeframe rules.
        if config.showFVG, barInterval >= config.fvgMinTimeframeMinutes * 60 - 1 {
            output.fvgs = fairValueGaps(candles, config: config)
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
        let lastDay = clock.day[n - 1]
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
                if config.showPivots {
                    for isHigh in [true, false] {
                        let price = isHigh ? high : low
                        var mitigation: Int?
                        for j in (window.upperBound + 1)..<n where isHigh ? candles[j].high > price : candles[j].low < price {
                            mitigation = j
                            break
                        }
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
        func previousPeriod(_ id: (Int) -> Int, kind: Level.Kind, labels: (String, String)) {
            let current = id(n - 1)
            guard let start = (0..<n).first(where: { id($0) == current }), start > 0 else { return }
            let previous = id(start - 1)
            var high = -Double.infinity, low = Double.infinity
            var i = start - 1
            while i >= 0, id(i) == previous {
                high = max(high, candles[i].high)
                low = min(low, candles[i].low)
                i -= 1
            }
            guard high.isFinite, low.isFinite else { return }
            output.levels.append(Level(kind: kind, price: high, start: start, end: nil, label: labels.0, mitigated: false))
            output.levels.append(Level(kind: kind, price: low, start: start, end: nil, label: labels.1, mitigated: false))
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
        return output
    }

    /// 3-candle imbalances: a bullish gap when a candle's low is above the high two
    /// candles before, a bearish one the other way round.
    static func fairValueGaps(_ c: [Candle], config: Config) -> [FairValueGap] {
        let n = c.count
        guard n > 3 else { return [] }
        let averageRange = c.suffix(100).reduce(0) { $0 + ($1.high - $1.low) } / Double(min(n, 100))
        let minimum = averageRange * max(config.fvgMinSize, 0)
        var gaps: [FairValueGap] = []
        for i in 2..<n {
            var gap: FairValueGap?
            if c[i].low > c[i - 2].high, c[i].low - c[i - 2].high > minimum {
                gap = FairValueGap(bullish: true, top: c[i].low, bottom: c[i - 2].high, start: i - 1,
                                   end: min(n - 1, i - 1 + max(config.fvgBoxBars, 1) - 1), filled: false)
            } else if c[i].high < c[i - 2].low, c[i - 2].low - c[i].high > minimum {
                gap = FairValueGap(bullish: false, top: c[i - 2].low, bottom: c[i].high, start: i - 1,
                                   end: min(n - 1, i - 1 + max(config.fvgBoxBars, 1) - 1), filled: false)
            }
            guard var found = gap else { continue }
            if i + 1 < n {
                for j in (i + 1)..<n where found.bullish ? c[j].low <= found.bottom : c[j].high >= found.top {
                    found.filled = true
                    break
                }
            }
            if found.filled && config.fvgHideFilled { continue }
            gaps.append(found)
        }
        return Array(gaps.suffix(max(config.fvgCount, 1)))
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

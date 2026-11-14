import Foundation

/// ICT killzones with session pivots, modelled on the "ICT Killzones + Pivots"
/// TradingView indicator: session boxes, session highs/lows extended until
/// price trades through them, opening-price lines, vertical timestamps, a
/// daily cutoff time, previous day/week/month highs and lows, day-of-week
/// labels, session range statistics and ICT macro windows. All times are
/// in `timeZoneID`.
public enum KillzonePivots {
    /// Day, week or month of the D/W/M lines.
    public enum Period: Int, CaseIterable, Codable, Hashable, Sendable {
        case day, week, month

        /// Names on the chart: open, high, low, middle ("DO", "PDH", "PDL", "PDM").
        public var labels: (open: String, high: String, low: String, middle: String) {
            switch self {
            case .day: return ("DO", "PDH", "PDL", "PDM")
            case .week: return ("WO", "PWH", "PWL", "PWM")
            case .month: return ("MO", "PMH", "PML", "PMM")
            }
        }

        /// Shortest length; the lines show on charts with smaller bars.
        public var seconds: TimeInterval {
            switch self {
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 28 * 86_400
            }
        }
    }

    /// What is drawn for one of day / week / month.
    public struct PeriodLines: Codable, Hashable, Sendable {
        /// Open of the current period.
        public var open: Bool
        /// High and low of the period before.
        public var highLow: Bool
        /// Middle of that high and low.
        public var midline: Bool
        /// A vertical line where each period starts.
        public var divider: Bool

        public init(open: Bool, highLow: Bool, midline: Bool, divider: Bool) {
            self.open = open
            self.highLow = highLow
            self.midline = midline
            self.divider = divider
        }
    }

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

        /// Day / week / month: this period's open, the last period's high / low and middle, a line at each start.
        public var dayLines = PeriodLines(open: true, highLow: true, midline: true, divider: false)
        public var weekLines = PeriodLines(open: false, highLow: true, midline: true, divider: false)
        public var monthLines = PeriodLines(open: false, highLow: false, midline: false, divider: false)
        /// PDH / PWL… end at the candle that crosses them (off: carried to the right edge).
        public var periodUntilBroken = true
        /// Tell the user when the newest candle crosses PDH / PDL / PWH… (the app sends the notice).
        public var alertPeriodBreaks = false
        /// High and low of each of the last days, drawn until a candle reaches them.
        public var showDailyLevels = true
        public var dailyLevelDays = 5
        /// A daily high/low price has reached stops at that candle and is drawn
        /// dotted; off, it is no longer drawn.
        public var dailyLevelsKeepTouched = true
        /// Days of the daily highs/lows as Exness counts them (its server runs on UTC, a day from 00:00 UTC),
        /// like the D1 candles there; off, days in the indicator's time zone.
        public var dailyLevelsExnessDay = true
        public var showDayOfWeek = false
        /// Weekday names over the chart instead of under it.
        public var dayOfWeekOnTop = false
        /// At each day's midday instead of its start (midnight).
        public var dayOfWeekAtMidday = false
        public var hideWeekendLabels = false
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

        /// Each week's first FVG made on Monday after 09:30 Vietnam time, carried to the end of the week.
        public var showWeekFVG = true
        /// Newest weeks shown.
        public var weekFVGWeeks = 4
        /// From this hour on Monday (9.5 = 09:30) in this time zone (New York, or Asia/Ho_Chi_Minh).
        public var weekFVGHour = 9.5
        public var weekFVGZoneID = "America/New_York"

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
        /// A touched FVG / VI that held (price bounced) stays this many minutes after
        /// the touch, then goes; one that price trades through goes at once.
        public var gapKeepMinutes = 15.0

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
        /// Bars left and right of a swing used for SMT (bigger = only the main highs / lows).
        public var smtSwingLength = 5
        /// The two swings compared are at most this many bars apart.
        public var smtLookback = 60
        /// Most recent divergences kept.
        public var smtCount = 5
        /// 3 = paired swings of both markets. Settings saved before had 3-bar swings and
        /// kept 10 (or 3 in v2); they are moved to the new defaults on load.
        public var smtVersion = 3

        public init() {}

        public func lines(_ period: Period) -> PeriodLines {
            switch period {
            case .day: return dayLines
            case .week: return weekLines
            case .month: return monthLines
            }
        }

        /// Keys of settings saved before D/W/M replaced them.
        private enum LegacyKeys: String, CodingKey { case showPreviousDay, showPreviousWeek, showPreviousMonth }

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
            dayLines = try c.decodeIfPresent(PeriodLines.self, forKey: .dayLines) ?? d.dayLines
            weekLines = try c.decodeIfPresent(PeriodLines.self, forKey: .weekLines) ?? d.weekLines
            monthLines = try c.decodeIfPresent(PeriodLines.self, forKey: .monthLines) ?? d.monthLines
            if !c.contains(.weekLines) {
                // Saved with the old PWH / PMH switches: keep what was turned on.
                let legacy = try decoder.container(keyedBy: LegacyKeys.self)
                if try legacy.decodeIfPresent(Bool.self, forKey: .showPreviousWeek) == true { weekLines.highLow = true }
                if try legacy.decodeIfPresent(Bool.self, forKey: .showPreviousMonth) == true { monthLines.highLow = true }
            }
            periodUntilBroken = try c.decodeIfPresent(Bool.self, forKey: .periodUntilBroken) ?? d.periodUntilBroken
            alertPeriodBreaks = try c.decodeIfPresent(Bool.self, forKey: .alertPeriodBreaks) ?? d.alertPeriodBreaks
            showDailyLevels = try c.decodeIfPresent(Bool.self, forKey: .showDailyLevels) ?? d.showDailyLevels
            dailyLevelDays = try c.decodeIfPresent(Int.self, forKey: .dailyLevelDays) ?? d.dailyLevelDays
            dailyLevelsKeepTouched = try c.decodeIfPresent(Bool.self, forKey: .dailyLevelsKeepTouched) ?? d.dailyLevelsKeepTouched
            dailyLevelsExnessDay = try c.decodeIfPresent(Bool.self, forKey: .dailyLevelsExnessDay) ?? d.dailyLevelsExnessDay
            showDayOfWeek = try c.decodeIfPresent(Bool.self, forKey: .showDayOfWeek) ?? d.showDayOfWeek
            dayOfWeekOnTop = try c.decodeIfPresent(Bool.self, forKey: .dayOfWeekOnTop) ?? d.dayOfWeekOnTop
            dayOfWeekAtMidday = try c.decodeIfPresent(Bool.self, forKey: .dayOfWeekAtMidday) ?? d.dayOfWeekAtMidday
            hideWeekendLabels = try c.decodeIfPresent(Bool.self, forKey: .hideWeekendLabels) ?? d.hideWeekendLabels
            showRangeTable = try c.decodeIfPresent(Bool.self, forKey: .showRangeTable) ?? d.showRangeTable
            rangeAverageCount = try c.decodeIfPresent(Int.self, forKey: .rangeAverageCount) ?? d.rangeAverageCount
            showMacros = try c.decodeIfPresent(Bool.self, forKey: .showMacros) ?? d.showMacros
            macroTimeframeLimitMinutes = try c.decodeIfPresent(Double.self, forKey: .macroTimeframeLimitMinutes) ?? d.macroTimeframeLimitMinutes
            macroTimeLabels = try c.decodeIfPresent(Bool.self, forKey: .macroTimeLabels) ?? d.macroTimeLabels
            macros = try c.decodeIfPresent([Macro].self, forKey: .macros) ?? d.macros
            showFVG = try c.decodeIfPresent(Bool.self, forKey: .showFVG) ?? d.showFVG
            showWeekFVG = try c.decodeIfPresent(Bool.self, forKey: .showWeekFVG) ?? d.showWeekFVG
            weekFVGWeeks = try c.decodeIfPresent(Int.self, forKey: .weekFVGWeeks) ?? d.weekFVGWeeks
            weekFVGHour = try c.decodeIfPresent(Double.self, forKey: .weekFVGHour) ?? d.weekFVGHour
            weekFVGZoneID = try c.decodeIfPresent(String.self, forKey: .weekFVGZoneID) ?? d.weekFVGZoneID
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
            gapKeepMinutes = try c.decodeIfPresent(Double.self, forKey: .gapKeepMinutes) ?? d.gapKeepMinutes
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
            let savedVersion = try c.decodeIfPresent(Int.self, forKey: .smtVersion)
            if savedVersion == nil {
                if smtSwingLength == 3 { smtSwingLength = d.smtSwingLength }
                if smtCount == 10 { smtCount = d.smtCount }
            } else if savedVersion == 2, smtCount == 3 {
                smtCount = d.smtCount
            }
            smtVersion = d.smtVersion
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
            /// D/W/M: the current period's open, the last one's high / low / middle.
            case period(Period, part: PeriodPart)
            /// High / low of one finished day; weekday 1 = Sunday … 7 = Saturday.
            case dayHigh(weekday: Int), dayLow(weekday: Int)
        }

        public var kind: Kind
        public var price: Double
        public var start: Int
        public var end: Int?
        public var label: String
        public var mitigated: Bool
    }

    public enum PeriodPart: Hashable, Sendable { case open, high, low, middle }

    /// The first fair value gap of a week's Monday after 09:30 Vietnam time.
    public struct WeekFVG: Hashable, Sendable {
        public var bullish: Bool
        public var top: Double
        public var bottom: Double
        /// The gap's middle candle.
        public var start: Int
        /// The week's last bar; nil while the week is running (to the right edge).
        public var end: Int?
        /// A later candle of the week came back into it.
        public var touched: Bool
    }

    /// Where a day / week / month starts.
    public struct Divider: Hashable, Sendable {
        public var period: Period
        public var index: Int
    }

    /// The newest candle crossed a D/W/M high / low ("Báo khi giá phá High/Low").
    public struct PeriodBreak: Hashable, Sendable {
        public var label: String
        public var price: Double
        public var high: Bool
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
        /// The comparison market's high / low (low / high when inverse) at the two swings, and the bars they are on.
        public var otherStart: Int = 0
        public var otherEnd: Int = 0
        public var otherStartPrice: Double = 0
        public var otherEndPrice: Double = 0
        /// True when this chart made the higher high (lower low) and the other market the lower one.
        public var chartHigher: Bool = true

        public init(bullish: Bool, start: Int, end: Int, startPrice: Double, endPrice: Double) {
            self.bullish = bullish
            self.start = start
            self.end = end
            self.startPrice = startPrice
            self.endPrice = endPrice
        }
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
        public var dividers: [Divider] = []
        public var periodBreaks: [PeriodBreak] = []
        /// Monday's first FVG after 09:30 (VN) of the newest weeks.
        public var weekFVGs: [WeekFVG] = []
        public var ranges: [RangeStat] = []
        /// True when the chart timeframe is above the limit and the killzones are not drawn.
        public var hiddenByTimeframe = false

        public init() {}
    }

    /// `comparison` holds the bars of the SMT market (same timeframe); empty = no SMT.
    /// `focusIndex` is the bar the "days to show" count back from (the right edge of
    /// the screen when scrolled into history); nil = the last bar.
    /// `minuteBars`: 1-minute bars around each Monday 09:30 (VN) for the Monday FVG (a 1-minute chart's own
    /// bars without them).
    public static func compute(candles: [Candle], barInterval: TimeInterval, config: Config,
                               comparison: [Candle] = [], focusIndex: Int? = nil, minuteBars: [Candle] = []) -> Output {
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
        // Day highs/lows on intraday charts, whatever the killzone timeframe limit.
        if config.showDailyLevels, barInterval < 86_400 {
            output.levels += dailyLevels(candles, config: config)
        }
        let zone = TimeZone(identifier: config.timeZoneID) ?? TimeZone(identifier: "America/New_York")!
        let clock = ICT.NewYorkClock(time: candles.map(\.time), zone: zone)
        periodLevels(candles, clock: clock, zone: zone, barInterval: barInterval, config: config, into: &output)
        if config.showWeekFVG, barInterval < 86_400 {
            let minutes = !minuteBars.isEmpty ? minuteBars : (barInterval == 60 ? candles : [])
            output.weekFVGs = mondayFVGs(candles, minutes: minutes, weeks: config.weekFVGWeeks, hour: config.weekFVGHour,
                                         zone: TimeZone(identifier: config.weekFVGZoneID) ?? TimeZone(identifier: "America/New_York")!)
        }
        guard barInterval <= config.timeframeLimitMinutes * 60 else {
            output.hiddenByTimeframe = true
            return output
        }
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

        // Sweeps of the previous day's high/low (the classic ICT liquidity), shown with or without its lines.
        if config.showSweeps, let range = previousPeriod(candles, id: { clock.day[$0] }) {
            for isHigh in [true, false] {
                let price = isHigh ? range.high : range.low
                if let j = firstBreak(candles, price: price, isHigh: isHigh, from: range.start),
                   isHigh ? candles[j].close < price : candles[j].close > price {
                    output.sweeps.append(Sweep(bullish: !isHigh, price: price, levelStart: isHigh ? range.highIndex : range.lowIndex,
                                               index: j, label: isHigh ? "PDH" : "PDL"))
                }
            }
        }
        output.sweeps = Array(output.sweeps.sorted { $0.index < $1.index }.suffix(max(config.sweepCount, 1)))
        return output
    }

    /// Each week's first M1 FVG made on Monday from `hour` (09:30 by default) in `zone` (New York with its
    /// summer time, or Vietnam): the gap's three 1-minute candles (`minutes`) from that time on, all on that
    /// Monday there. Laid on the chart's bars `c`: from the bar holding its middle candle to the week's last
    /// bar. Gaps after the chart's last bar are left out (replay). The newest `weeks`.
    static func mondayFVGs(_ c: [Candle], minutes m: [Candle], weeks: Int, hour: Double = 9.5,
                           zone: TimeZone = TimeZone(identifier: "America/New_York")!) -> [WeekFVG] {
        let n = c.count
        guard n > 0, m.count > 2 else { return [] }
        func local(_ date: Date) -> Double { date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date)) }
        func day(_ date: Date) -> Int { Int(floor(local(date) / 86_400)) }
        // Weeks from Sunday (gold's week opens Sunday evening in New York, Monday morning in Vietnam).
        func week(_ date: Date) -> Int { Int(floor(Double(day(date) + 4) / 7)) }
        func mondayAfterOpen(_ date: Date) -> Bool {
            let d = day(date)
            return (d + 4) % 7 == 1 && local(date) - Double(d) * 86_400 >= hour * 3600
        }
        /// The chart bar holding a time (the last one starting at or before it).
        func bar(at time: Date) -> Int? {
            guard time >= c[0].time else { return nil }
            var lo = 0, hi = n - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if c[mid].time <= time { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }
        let lastBarLength = n > 1 ? c[n - 1].time.timeIntervalSince(c[n - 2].time) : 60
        var result: [WeekFVG] = []
        var done = Set<Int>()
        for i in 2..<m.count {
            let a = m[i - 2], b = m[i]
            // Not past the chart's last bar.
            if b.time.timeIntervalSince(c[n - 1].time) > max(lastBarLength, 60) { break }
            let wk = week(b.time)
            guard !done.contains(wk), mondayAfterOpen(a.time), day(b.time) == day(a.time) else { continue }
            let bullish = b.low > a.high
            let bearish = b.high < a.low
            guard bullish || bearish else { continue }
            done.insert(wk)
            guard let start = bar(at: m[i - 1].time) else { continue }
            var end = start
            while end + 1 < n, week(c[end + 1].time) == wk { end += 1 }
            let top = bullish ? b.low : a.low
            let bottom = bullish ? a.high : b.high
            let after = max(start + 1, bar(at: b.time.addingTimeInterval(60)) ?? (end + 1))
            let touched = after <= end && (after...end).contains { c[$0].low <= top && c[$0].high >= bottom }
            result.append(WeekFVG(bullish: bullish, top: top, bottom: bottom, start: start,
                                  end: end == n - 1 ? nil : end, touched: touched))
        }
        return Array(result.suffix(max(weeks, 1)))
    }

    /// High/low of the period before the newest bar's one (`id` per bar) and the first bar of the current one.
    static func previousPeriod(_ c: [Candle], id: (Int) -> Int)
        -> (start: Int, high: Double, highIndex: Int, low: Double, lowIndex: Int)? {
        let n = c.count
        guard n > 1 else { return nil }
        let current = id(n - 1)
        var start = n - 1
        while start > 0, id(start - 1) == current { start -= 1 }
        guard start > 0 else { return nil }
        let previous = id(start - 1)
        var high = -Double.infinity, low = Double.infinity
        var highIndex = start - 1, lowIndex = start - 1
        var i = start - 1
        while i >= 0, id(i) == previous {
            if c[i].high > high { high = c[i].high; highIndex = i }
            if c[i].low < low { low = c[i].low; lowIndex = i }
            i -= 1
        }
        return (start, high, highIndex, low, lowIndex)
    }

    /// Day / week / month lines on charts with bars shorter than the period: the current period's open,
    /// the last one's high / low (ending at the candle that crosses it, with `periodUntilBroken`) and middle,
    /// a divider at each start; and the weekday labels.
    static func periodLevels(_ c: [Candle], clock: ICT.NewYorkClock, zone: TimeZone, barInterval: TimeInterval,
                             config: Config, into output: inout Output) {
        let n = c.count
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        for period in Period.allCases {
            let lines = config.lines(period)
            guard barInterval < period.seconds, lines.open || lines.highLow || lines.midline || lines.divider else { continue }
            let ids: [Int]
            switch period {
            case .day: ids = clock.day
            case .week: ids = clock.week
            case .month:
                ids = c.map { bar in
                    let parts = calendar.dateComponents([.year, .month], from: bar.time)
                    return (parts.year ?? 0) * 12 + (parts.month ?? 0)
                }
            }
            let names = period.labels
            if lines.divider {
                for i in 1..<n where ids[i] != ids[i - 1] { output.dividers.append(Divider(period: period, index: i)) }
            }
            if lines.open {
                var start = n - 1
                while start > 0, ids[start - 1] == ids[n - 1] { start -= 1 }
                if start > 0 {
                    output.levels.append(Level(kind: .period(period, part: .open), price: c[start].open, start: start, end: nil,
                                               label: names.open, mitigated: false))
                }
            }
            guard let range = previousPeriod(c, id: { ids[$0] }) else { continue }
            if lines.highLow {
                for isHigh in [true, false] {
                    let price = isHigh ? range.high : range.low
                    let j = firstBreak(c, price: price, isHigh: isHigh, from: range.start)
                    if j == n - 1 { output.periodBreaks.append(PeriodBreak(label: isHigh ? names.high : names.low, price: price, high: isHigh)) }
                    output.levels.append(Level(kind: .period(period, part: isHigh ? .high : .low), price: price, start: range.start,
                                               end: config.periodUntilBroken ? j : nil, label: isHigh ? names.high : names.low,
                                               mitigated: j != nil))
                }
            }
            if lines.midline {
                output.levels.append(Level(kind: .period(period, part: .middle), price: (range.high + range.low) / 2,
                                           start: range.start, end: nil, label: names.middle, mitigated: false))
            }
        }
        // Weekday names at each day's start (or midday), weekends left out on request.
        guard config.showDayOfWeek, barInterval < 86_400 else { return }
        let hour = config.dayOfWeekAtMidday ? 12.0 : 0
        for i in 0..<n {
            let newDay = i == 0 || clock.day[i] != clock.day[i - 1]
            let crossed = !newDay && clock.hour[i - 1] < hour && clock.hour[i] >= hour
            guard crossed || (newDay && clock.hour[i] >= hour) else { continue }
            let weekday = calendar.component(.weekday, from: c[i].time)
            if config.hideWeekendLabels, weekday == 1 || weekday == 7 { continue }
            output.dayLabels.append(DayLabel(index: i, weekday: weekday))
        }
    }

    /// The high and low of each of the last `dailyLevelDays` finished days (Exness days, from
    /// 00:00 UTC, or days in the indicator's time zone), from the bar that made them to the right
    /// edge; once a later candle reaches one it ends at that candle (mitigated).
    static func dailyLevels(_ c: [Candle], config: Config) -> [Level] {
        let zone = config.dailyLevelsExnessDay ? TimeZone(identifier: "UTC")!
            : TimeZone(identifier: config.timeZoneID) ?? TimeZone(identifier: "America/New_York")!
        let days = ICT.NewYorkClock(time: c.map(\.time), zone: zone).day
        guard let today = days.last else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // Bars of each day, newest first, the running day left out.
        var ranges: [(day: Int, range: ClosedRange<Int>)] = []
        var end = c.count - 1
        while end >= 0, days[end] == today { end -= 1 }
        while end >= 0, ranges.count < max(config.dailyLevelDays, 1) {
            var start = end
            while start > 0, days[start - 1] == days[end] { start -= 1 }
            ranges.append((days[end], start...end))
            end = start - 1
        }
        var levels: [Level] = []
        for (_, range) in ranges.reversed() {
            let bars = range.map { ($0, c[$0]) }
            guard let high = bars.max(by: { $0.1.high < $1.1.high }), let low = bars.min(by: { $0.1.low < $1.1.low }) else { continue }
            let weekday = calendar.component(.weekday, from: c[range.lowerBound].time)
            for (isHigh, start, price) in [(true, high.0, high.1.high), (false, low.0, low.1.low)] {
                let touch = firstTouch(c, price: price, isHigh: isHigh, from: range.upperBound + 1)
                if touch != nil && !config.dailyLevelsKeepTouched { continue }
                levels.append(Level(kind: isHigh ? .dayHigh(weekday: weekday) : .dayLow(weekday: weekday), price: price,
                                    start: start, end: touch, label: "", mitigated: touch != nil))
            }
        }
        return levels
    }

    /// First bar from `from` that reaches `price`.
    static func firstTouch(_ c: [Candle], price: Double, isHigh: Bool, from: Int) -> Int? {
        guard from < c.count else { return nil }
        return (from..<c.count).first { isHigh ? c[$0].high >= price : c[$0].low <= price }
    }

    /// First bar from `from` that trades beyond `price`.
    static func firstBreak(_ c: [Candle], price: Double, isHigh: Bool, from: Int) -> Int? {
        guard from < c.count else { return nil }
        return (from..<c.count).first { isHigh ? c[$0].high > price : c[$0].low < price }
    }

    /// `other` laid on `main`'s bars: one bar per main bar, at the same time, so two charts scrolled by bar
    /// number show the same candles. A main bar the other market has no bar for gets a flat bar at its last
    /// close (at the first open before it starts); other bars with no main bar are left out.
    public static func aligned(_ other: [Candle], to main: [Candle]) -> [Candle] {
        guard let first = other.first else { return [] }
        let byTime = Dictionary(other.map { ($0.time, $0) }, uniquingKeysWith: { _, new in new })
        var last: Double = first.open
        return main.map { bar in
            if let o = byTime[bar.time] {
                last = o.close
                return o
            }
            return Candle(time: bar.time, open: last, high: last, low: last, close: last)
        }
    }

    /// SMT divergence: two swing highs (or two swing lows) in a row, on the same stretch of candles in
    /// `a` (the chart) and `b` (the comparison market, matched on time), where one market's second high is
    /// higher and the other's is lower (lows: one lower, one higher).
    ///  - Swings are `smtSwingLength` bars each side, in each market on its own; the other market's swing
    ///    must be within `smtSwingLength` bars of ours (the nearest one).
    ///  - The two swings are the top (bottom) of the stretch between them in both markets, so a line never
    ///    crosses a bigger high, and they are at most `smtLookback` bars apart.
    ///  - Two SMTs that share a swing (a chain) keep only the newer.
    /// With `smtInverse` (DXY) our highs pair with its lows. Confirmed `smtSwingLength` bars later.
    public static func smtDivergences(_ a: [Candle], _ b: [Candle], config: Config) -> [SMTDivergence] {
        let length = max(config.smtSwingLength, 1)
        // The other market's swing may come a few bars before or after ours (up to one swing length).
        let near = length
        let n = a.count
        guard n > length * 2 + 2, !b.isEmpty else { return [] }
        let other = Dictionary(b.map { ($0.time, $0) }, uniquingKeysWith: { _, new in new })
        let matched = a.map { other[$0.time] }
        // Swings: `length` bars each side less extreme (`more`: higher for highs, lower for lows).
        func pivots(_ value: (Int) -> Double?, _ more: (Double, Double) -> Bool) -> [Int] {
            (length..<(n - length)).filter { p in
                guard let v = value(p) else { return false }
                return ((p - length)...(p + length)).allSatisfy { j in
                    guard j != p, let w = value(j) else { return true }
                    return more(v, w)
                }
            }
        }
        var result: [SMTDivergence] = []
        for high in [true, false] {
            let otherHigh = high != config.smtInverse
            let valueA: (Int) -> Double? = { high ? a[$0].high : a[$0].low }
            let valueB: (Int) -> Double? = { i in matched[i].map { otherHigh ? $0.high : $0.low } }
            let moreA: (Double, Double) -> Bool = { high ? $0 > $1 : $0 < $1 }
            let moreB: (Double, Double) -> Bool = { otherHigh ? $0 > $1 : $0 < $1 }
            let swingsB = pivots(valueB, moreB)
            // Our swings that the other market also made (its nearest swing within `near` bars).
            let pairs: [(Int, Int)] = pivots(valueA, moreA).compactMap { i in
                swingsB.filter { abs($0 - i) <= near }.min { abs($0 - i) < abs($1 - i) }.map { (i, $0) }
            }
            for ((i1, j1), (i2, j2)) in zip(pairs, pairs.dropFirst()) where i2 - i1 <= config.smtLookback && j2 > j1 {
                guard let a1 = valueA(i1), let a2 = valueA(i2), let b1 = valueB(j1), let b2 = valueB(j2),
                      a1 != a2, b1 != b2 else { continue }
                let chartHigher = moreA(a2, a1)
                guard chartHigher != moreB(b2, b1) else { continue }
                // Nothing between the two swings beyond them, in either market.
                let topA = moreA(a1, a2) ? a1 : a2, topB = moreB(b1, b2) ? b1 : b2
                let between = (min(i1, j1) + 1)..<max(i2, j2)
                let clean = between.allSatisfy { j in
                    if j != i1, j != i2, let v = valueA(j), moreA(v, topA) { return false }
                    if j != j1, j != j2, let v = valueB(j), moreB(v, topB) { return false }
                    return true
                }
                guard clean else { continue }
                // Chained with the one before (its second swing is this one's first): keep only the newer,
                // so the lines never zigzag from swing to swing.
                if let last = result.last, last.bullish == !high, last.end == i1 { result.removeLast() }
                var div = SMTDivergence(bullish: !high, start: i1, end: i2, startPrice: a1, endPrice: a2)
                div.otherStart = j1
                div.otherEnd = j2
                div.otherStartPrice = b1
                div.otherEndPrice = b2
                div.chartHigher = chartHigher
                result.append(div)
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
            if !stillShown(gap, in: c, keepMinutes: config.gapKeepMinutes) { continue }
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
            if !stillShown(gap, in: c, keepMinutes: config.gapKeepMinutes) { continue }
            found.append(gap)
            if found.count >= max(config.viCount, 1) { break }
        }
        return found.reversed()
    }

    /// An untouched gap stays. A touched one stays while price has not traded through
    /// it (beyond its far edge) and for `keepMinutes` after the touch.
    static func stillShown(_ gap: FairValueGap, in c: [Candle], keepMinutes: Double) -> Bool {
        guard gap.touched, gap.end < c.count else { return true }
        for j in gap.end..<c.count where gap.bullish ? c[j].low < gap.bottom : c[j].high > gap.top {
            return false
        }
        guard let last = c.last else { return true }
        return last.time.timeIntervalSince(c[gap.end].time) <= keepMinutes * 60
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

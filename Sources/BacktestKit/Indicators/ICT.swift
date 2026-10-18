import Foundation

/// ICT (Inner Circle Trader) concepts as stateful, bar-by-bar calculations:
/// New York killzones, market structure (BOS / MSS), liquidity sweeps,
/// fair value gaps, order blocks, dealing range and key session levels.
///
/// Every value at bar `i` uses bars `0...i` only. Swing points come from
/// `TA.pivothigh` / `TA.pivotlow`, so they appear `right` bars after the
/// actual swing, exactly when they would have been known live.
public enum ICT {
    // MARK: - New York clock

    /// Session times in ICT are New York times. Converting through the
    /// `America/New_York` zone handles EDT/EST changes automatically.
    public struct NewYorkClock {
        /// Fractional hour of day in New York (14.5 = 14:30).
        public var hour: Series
        /// Days since 1970-01-01 in New York local time.
        public var day: [Int]
        /// Weeks (starting Sunday) since 1970 in New York local time.
        public var week: [Int]

        public init(time: [Date]) {
            self.init(time: time, zone: TimeZone(identifier: "America/New_York")!)
        }

        /// The same clock in another time zone (hours, days and weeks are local to `zone`).
        public init(time: [Date], zone: TimeZone) {
            var hour = Series(repeating: 0, count: time.count)
            var day = [Int](repeating: 0, count: time.count)
            var week = [Int](repeating: 0, count: time.count)
            for (i, date) in time.enumerated() {
                let local = date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date))
                let d = Int(floor(local / 86_400))
                day[i] = d
                // 1970-01-01 was a Thursday, so (d + 4) / 7 changes on Sundays.
                week[i] = Int(floor(Double(d + 4) / 7))
                hour[i] = (local - Double(d) * 86_400) / 3600
            }
            self.hour = hour
            self.day = day
            self.week = week
        }

        /// 1 when the New York hour is in `[start, end)`; wraps past midnight.
        public func session(_ start: Double, _ end: Double) -> Series {
            hour.map { h in
                let inside = start <= end ? (h >= start && h < end) : (h >= start || h < end)
                return inside ? 1 : 0
            }
        }
    }

    /// Killzones and macro windows, in New York time.
    public enum Session {
        public static let asia = (20.0, 24.0)
        public static let london = (2.0, 5.0)
        public static let newYorkAM = (7.0, 10.0)
        public static let londonClose = (10.0, 12.0)
        public static let silverBulletLondon = (3.0, 4.0)
        public static let silverBulletAM = (10.0, 11.0)
        public static let silverBulletPM = (14.0, 15.0)
        /// ICT "macro" windows (NY time): 02:33–03:00, 04:03–04:30, 08:50–09:10,
        /// 09:50–10:10, 10:50–11:10, 11:50–12:10, 13:10–13:40, 15:15–15:45.
        public static let macros: [(Double, Double)] = [
            (2 + 33.0 / 60, 3), (4 + 3.0 / 60, 4.5), (8 + 50.0 / 60, 9 + 10.0 / 60),
            (9 + 50.0 / 60, 10 + 10.0 / 60), (10 + 50.0 / 60, 11 + 10.0 / 60),
            (11 + 50.0 / 60, 12 + 10.0 / 60), (13 + 10.0 / 60, 13 + 40.0 / 60), (15.25, 15.75),
        ]
    }

    /// Open of the first bar at or after New York midnight, held all day.
    public static func midnightOpen(open: Series, clock: NewYorkClock) -> Series {
        var level = Double.nan
        return open.indices.map { i in
            if i == 0 || clock.day[i] != clock.day[i - 1] { level = open[i] }
            return level
        }
    }

    public struct Range {
        public var high: Series
        public var low: Series
    }

    /// High/low of the most recently *completed* Asia session (20:00–00:00 NY).
    public static func asiaRange(high: Series, low: Series, clock: NewYorkClock) -> Range {
        sessionRange(high: high, low: low, clock: clock, start: Session.asia.0, end: Session.asia.1)
    }

    /// High/low of the most recently completed session `[start, end)` (NY hours),
    /// held from the end of that session until the next one ends.
    public static func sessionRange(high: Series, low: Series, clock: NewYorkClock, start: Double, end: Double) -> Range {
        let n = high.count
        let inSession = clock.session(start, end)
        var outHigh = Series(repeating: .nan, count: n)
        var outLow = Series(repeating: .nan, count: n)
        var completedHigh = Double.nan, completedLow = Double.nan
        var runningHigh = -Double.infinity, runningLow = Double.infinity
        var active = false
        for i in 0..<n {
            if inSession[i] == 1 {
                if !active {
                    runningHigh = -.infinity
                    runningLow = .infinity
                    active = true
                }
                runningHigh = max(runningHigh, high[i])
                runningLow = min(runningLow, low[i])
            } else if active {
                completedHigh = runningHigh
                completedLow = runningLow
                active = false
            }
            outHigh[i] = completedHigh
            outLow[i] = completedLow
        }
        return Range(high: outHigh, low: outLow)
    }

    /// Open of the first bar at or after `hour` (NY) each New York day, held
    /// until the next day's. `openAt(hour: 9.5)` is the 09:30 equity open.
    public static func openAt(open: Series, clock: NewYorkClock, hour: Double) -> Series {
        var level = Double.nan
        var day = Int.min
        return open.indices.map { i in
            if clock.day[i] != day, clock.hour[i] >= hour {
                day = clock.day[i]
                level = open[i]
            }
            return level
        }
    }

    /// High/low of the previous New York calendar day.
    public static func previousDay(high: Series, low: Series, clock: NewYorkClock) -> Range {
        let n = high.count
        var outHigh = Series(repeating: .nan, count: n)
        var outLow = Series(repeating: .nan, count: n)
        var previousHigh = Double.nan, previousLow = Double.nan
        var runningHigh = -Double.infinity, runningLow = Double.infinity
        for i in 0..<n {
            if i > 0, clock.day[i] != clock.day[i - 1] {
                previousHigh = runningHigh
                previousLow = runningLow
                runningHigh = -.infinity
                runningLow = .infinity
            }
            runningHigh = max(runningHigh, high[i])
            runningLow = min(runningLow, low[i])
            outHigh[i] = previousHigh
            outLow[i] = previousLow
        }
        return Range(high: outHigh, low: outLow)
    }

    /// Contiguous runs of bars inside `[start, end)` NY hours, as closed index ranges.
    public static func sessionWindows(clock: NewYorkClock, start: Double, end: Double) -> [ClosedRange<Int>] {
        let inSession = clock.session(start, end)
        var windows: [ClosedRange<Int>] = []
        var first: Int?
        for i in inSession.indices {
            if inSession[i] == 1 {
                if first == nil { first = i }
            } else if let f = first {
                windows.append(f...(i - 1))
                first = nil
            }
        }
        if let f = first { windows.append(f...(inSession.count - 1)) }
        return windows
    }

    /// High/low of the previous New York week.
    public static func previousWeek(high: Series, low: Series, clock: NewYorkClock) -> Range {
        let n = high.count
        var outHigh = Series(repeating: .nan, count: n)
        var outLow = Series(repeating: .nan, count: n)
        var previousHigh = Double.nan, previousLow = Double.nan
        var runningHigh = -Double.infinity, runningLow = Double.infinity
        for i in 0..<n {
            if i > 0, clock.week[i] != clock.week[i - 1] {
                previousHigh = runningHigh
                previousLow = runningLow
                runningHigh = -.infinity
                runningLow = .infinity
            }
            runningHigh = max(runningHigh, high[i])
            runningLow = min(runningLow, low[i])
            outHigh[i] = previousHigh
            outLow[i] = previousLow
        }
        return Range(high: outHigh, low: outLow)
    }

    // MARK: - Market structure

    public struct Structure {
        /// 1 after a bullish break, -1 after a bearish one, NaN before any.
        public var trend: Series
        /// Close broke above the last unbroken swing high (BOS or MSS).
        public var bullBreak: [Bool]
        public var bearBreak: [Bool]
        /// Break against the previous trend (market structure shift / CHoCH).
        public var bullShift: [Bool]
        public var bearShift: [Bool]
        /// Wick through an unbroken swing low/high with the close back inside:
        /// sell-side (SSL) or buy-side (BSL) liquidity taken.
        public var sellSideSweep: [Bool]
        public var buySideSweep: [Bool]
        /// Last confirmed swing high/low, held until the next one.
        public var swingHigh: Series
        public var swingLow: Series
    }

    public static func structure(high: Series, low: Series, close: Series, left: Int, right: Int) -> Structure {
        let n = close.count
        let pivotHighs = TA.pivothigh(high, left: left, right: right)
        let pivotLows = TA.pivotlow(low, left: left, right: right)
        var result = Structure(trend: Series(repeating: .nan, count: n),
                               bullBreak: Array(repeating: false, count: n),
                               bearBreak: Array(repeating: false, count: n),
                               bullShift: Array(repeating: false, count: n),
                               bearShift: Array(repeating: false, count: n),
                               sellSideSweep: Array(repeating: false, count: n),
                               buySideSweep: Array(repeating: false, count: n),
                               swingHigh: Series(repeating: .nan, count: n),
                               swingLow: Series(repeating: .nan, count: n))
        var activeHigh = Double.nan, activeLow = Double.nan
        var lastHigh = Double.nan, lastLow = Double.nan
        var trend = 0.0
        for i in 0..<n {
            if !pivotHighs[i].isNaN {
                activeHigh = pivotHighs[i]
                lastHigh = pivotHighs[i]
            }
            if !pivotLows[i].isNaN {
                activeLow = pivotLows[i]
                lastLow = pivotLows[i]
            }
            if !activeHigh.isNaN, high[i] > activeHigh, close[i] <= activeHigh {
                result.buySideSweep[i] = true
            }
            if !activeLow.isNaN, low[i] < activeLow, close[i] >= activeLow {
                result.sellSideSweep[i] = true
            }
            if !activeHigh.isNaN, close[i] > activeHigh {
                result.bullBreak[i] = true
                result.bullShift[i] = trend == -1
                trend = 1
                activeHigh = .nan
            }
            if !activeLow.isNaN, close[i] < activeLow {
                result.bearBreak[i] = true
                result.bearShift[i] = trend == 1
                trend = -1
                activeLow = .nan
            }
            result.trend[i] = trend == 0 ? .nan : trend
            result.swingHigh[i] = lastHigh
            result.swingLow[i] = lastLow
        }
        return result
    }

    // MARK: - PD arrays

    public struct Zones {
        public var bullTop: Series
        public var bullBottom: Series
        public var bearTop: Series
        public var bearBottom: Series
    }

    /// Most recent fair value gaps that have not been completely filled.
    ///
    /// Bullish FVG on candles n1, n2, n3: `high(n1) < low(n3)`, zone
    /// `[high(n1), low(n3)]`; removed once a later low trades to its bottom.
    /// Bearish FVG: `low(n1) > high(n3)`, zone `[high(n3), low(n1)]`; removed
    /// once a later high trades to its top.
    public static func fairValueGaps(high: Series, low: Series, minSize: Double = 0) -> Zones {
        let n = high.count
        var zones = Zones(bullTop: Series(repeating: .nan, count: n), bullBottom: Series(repeating: .nan, count: n),
                          bearTop: Series(repeating: .nan, count: n), bearBottom: Series(repeating: .nan, count: n))
        var bullTop = Double.nan, bullBottom = Double.nan
        var bearTop = Double.nan, bearBottom = Double.nan
        for i in 0..<n {
            if !bullBottom.isNaN, low[i] <= bullBottom {
                bullTop = .nan
                bullBottom = .nan
            }
            if !bearTop.isNaN, high[i] >= bearTop {
                bearTop = .nan
                bearBottom = .nan
            }
            if i >= 2 {
                if low[i] - high[i - 2] > minSize {
                    bullTop = low[i]
                    bullBottom = high[i - 2]
                }
                if low[i - 2] - high[i] > minSize {
                    bearTop = low[i - 2]
                    bearBottom = high[i]
                }
            }
            zones.bullTop[i] = bullTop
            zones.bullBottom[i] = bullBottom
            zones.bearTop[i] = bearTop
            zones.bearBottom[i] = bearBottom
        }
        return zones
    }

    /// Order blocks: the last opposite-colour candle within `lookback` bars
    /// before a structure break. A bullish OB is invalidated by a close below
    /// its low, a bearish OB by a close above its high.
    public static func orderBlocks(open: Series, high: Series, low: Series, close: Series,
                                   structure: Structure, lookback: Int = 20) -> Zones {
        let n = close.count
        var zones = Zones(bullTop: Series(repeating: .nan, count: n), bullBottom: Series(repeating: .nan, count: n),
                          bearTop: Series(repeating: .nan, count: n), bearBottom: Series(repeating: .nan, count: n))
        var bullTop = Double.nan, bullBottom = Double.nan
        var bearTop = Double.nan, bearBottom = Double.nan
        for i in 0..<n {
            if !bullBottom.isNaN, close[i] < bullBottom {
                bullTop = .nan
                bullBottom = .nan
            }
            if !bearTop.isNaN, close[i] > bearTop {
                bearTop = .nan
                bearBottom = .nan
            }
            if structure.bullBreak[i] {
                for j in stride(from: i - 1, through: max(0, i - lookback), by: -1) where close[j] < open[j] {
                    bullTop = high[j]
                    bullBottom = low[j]
                    break
                }
            }
            if structure.bearBreak[i] {
                for j in stride(from: i - 1, through: max(0, i - lookback), by: -1) where close[j] > open[j] {
                    bearTop = high[j]
                    bearBottom = low[j]
                    break
                }
            }
            zones.bullTop[i] = bullTop
            zones.bullBottom[i] = bullBottom
            zones.bearTop[i] = bearTop
            zones.bearBottom[i] = bearBottom
        }
        return zones
    }
}

/// Script functions for the ICT toolkit.
public enum ICTFunctions {
    public static let category = "ICT"

    public static var all: [ScriptFunction] {
        sessionFunctions + levelFunctions + structureFunctions + zoneFunctions
    }

    private static func flags(_ values: [Bool]) -> Value {
        .series(values.map { $0 ? 1 : 0 })
    }

    private static func clock(_ args: CallArguments) -> ICT.NewYorkClock {
        ICT.NewYorkClock(time: args.data.time)
    }

    private static let swingParameters = [FunctionParameter.length("left", default: 5), .length("right", default: 5)]

    private static func structure(_ args: CallArguments) throws -> ICT.Structure {
        let d = args.data
        return ICT.structure(high: d.high, low: d.low, close: d.close,
                             left: try args.length(0), right: try args.length(1))
    }

    // MARK: Sessions

    static var sessionFunctions: [ScriptFunction] {
        func window(_ name: String, _ hours: (Double, Double), _ summary: String) -> ScriptFunction {
            ScriptFunction(name, [], category: category, summary: summary) { args in
                .series(clock(args).session(hours.0, hours.1))
            }
        }
        return [
            ScriptFunction("ny_session", [FunctionParameter("start", .number), FunctionParameter("end", .number)],
                           category: category,
                           summary: "1 khi giờ New York trong [start, end), tự đổi EDT/EST. Ví dụ ny_session(8.5, 11)") { args in
                .series(clock(args).session(args.number(0), args.number(1)))
            },
            window("kz_asia", ICT.Session.asia, "Phiên Á 20:00–00:00 NY (07–11h VN mùa hè, 08–12h mùa đông)"),
            window("kz_london", ICT.Session.london, "London Killzone 02:00–05:00 NY (13–16h / 14–17h VN)"),
            window("kz_ny_am", ICT.Session.newYorkAM, "New York AM Killzone 07:00–10:00 NY (18–21h / 19–22h VN)"),
            window("kz_london_close", ICT.Session.londonClose, "London Close 10:00–12:00 NY"),
            window("silver_bullet_london", ICT.Session.silverBulletLondon, "London Silver Bullet 03:00–04:00 NY"),
            window("silver_bullet", ICT.Session.silverBulletAM, "AM Silver Bullet 10:00–11:00 NY (21–22h / 22–23h VN)"),
            window("silver_bullet_pm", ICT.Session.silverBulletPM, "PM Silver Bullet 14:00–15:00 NY"),
        ]
    }

    // MARK: Levels

    static var levelFunctions: [ScriptFunction] {
        [
            ScriptFunction("ny_midnight_open", [], category: category,
                           summary: "Giá mở cửa lúc 00:00 New York, giữ nguyên cả ngày (trên = premium, dưới = discount)") { args in
                .series(ICT.midnightOpen(open: args.data.open, clock: clock(args)))
            },
            ScriptFunction("asia_high", [], category: category, summary: "Đỉnh phiên Á gần nhất đã kết thúc (thanh khoản BSL)") { args in
                .series(ICT.asiaRange(high: args.data.high, low: args.data.low, clock: clock(args)).high)
            },
            ScriptFunction("asia_low", [], category: category, summary: "Đáy phiên Á gần nhất đã kết thúc (thanh khoản SSL)") { args in
                .series(ICT.asiaRange(high: args.data.high, low: args.data.low, clock: clock(args)).low)
            },
            ScriptFunction("london_high", [], category: category, summary: "Đỉnh phiên London gần nhất đã kết thúc (02:00–05:00 NY)") { args in
                .series(ICT.sessionRange(high: args.data.high, low: args.data.low, clock: clock(args),
                                         start: ICT.Session.london.0, end: ICT.Session.london.1).high)
            },
            ScriptFunction("london_low", [], category: category, summary: "Đáy phiên London gần nhất đã kết thúc (02:00–05:00 NY)") { args in
                .series(ICT.sessionRange(high: args.data.high, low: args.data.low, clock: clock(args),
                                         start: ICT.Session.london.0, end: ICT.Session.london.1).low)
            },
            ScriptFunction("am_open", [], category: category, summary: "Giá mở cửa 09:30 New York (mở cửa chứng khoán Mỹ), giữ cả ngày") { args in
                .series(ICT.openAt(open: args.data.open, clock: clock(args), hour: 9.5))
            },
            ScriptFunction("ny_pdh", [], category: category, summary: "Đỉnh ngày hôm trước theo ngày New York") { args in
                .series(ICT.previousDay(high: args.data.high, low: args.data.low, clock: clock(args)).high)
            },
            ScriptFunction("ny_pdl", [], category: category, summary: "Đáy ngày hôm trước theo ngày New York") { args in
                .series(ICT.previousDay(high: args.data.high, low: args.data.low, clock: clock(args)).low)
            },
            ScriptFunction("prev_week_high", [], category: category, summary: "Đỉnh tuần trước (PWH, theo giờ New York)") { args in
                .series(ICT.previousWeek(high: args.data.high, low: args.data.low, clock: clock(args)).high)
            },
            ScriptFunction("prev_week_low", [], category: category, summary: "Đáy tuần trước (PWL, theo giờ New York)") { args in
                .series(ICT.previousWeek(high: args.data.high, low: args.data.low, clock: clock(args)).low)
            },
        ]
    }

    // MARK: Structure

    static var structureFunctions: [ScriptFunction] {
        func flag(_ name: String, _ summary: String, _ pick: @escaping (ICT.Structure) -> [Bool]) -> ScriptFunction {
            ScriptFunction(name, swingParameters, category: category, summary: summary) { args in
                flags(pick(try structure(args)))
            }
        }
        func level(_ name: String, _ summary: String, _ pick: @escaping (ICT.Structure) -> Series) -> ScriptFunction {
            ScriptFunction(name, swingParameters, category: category, summary: summary) { args in
                .series(pick(try structure(args)))
            }
        }
        return [
            level("structure", "Cấu trúc: 1 = tăng (HH/HL), −1 = giảm (LH/LL), theo đỉnh/đáy swing left/right") { $0.trend },
            flag("bos_bull", "1 khi đóng cửa phá đỉnh swing (BOS hoặc MSS tăng)") { $0.bullBreak },
            flag("bos_bear", "1 khi đóng cửa phá đáy swing (BOS hoặc MSS giảm)") { $0.bearBreak },
            flag("mss_bull", "Market structure shift tăng: phá đỉnh swing khi đang cấu trúc giảm") { $0.bullShift },
            flag("mss_bear", "Market structure shift giảm: phá đáy swing khi đang cấu trúc tăng") { $0.bearShift },
            flag("sweep_ssl", "Quét thanh khoản bên bán: râu xuống dưới đáy swing rồi đóng cửa trở lại trên") { $0.sellSideSweep },
            flag("sweep_bsl", "Quét thanh khoản bên mua: râu lên trên đỉnh swing rồi đóng cửa trở lại dưới") { $0.buySideSweep },
            level("dr_high", "Đỉnh dealing range (đỉnh swing gần nhất)") { $0.swingHigh },
            level("dr_low", "Đáy dealing range (đáy swing gần nhất)") { $0.swingLow },
            level("equilibrium", "Equilibrium = (đỉnh + đáy dealing range) / 2; trên là premium, dưới là discount") { s in
                zip(s.swingHigh, s.swingLow).map { ($0 + $1) / 2 }
            },
        ]
    }

    // MARK: Zones

    static var zoneFunctions: [ScriptFunction] {
        func fvg(_ name: String, _ summary: String, _ pick: @escaping (ICT.Zones) -> Series) -> ScriptFunction {
            ScriptFunction(name, [FunctionParameter("min_size", .number, default: 0)], category: category, summary: summary) { args in
                .series(pick(ICT.fairValueGaps(high: args.data.high, low: args.data.low, minSize: args.number(0))))
            }
        }
        func orderBlock(_ name: String, _ summary: String, _ pick: @escaping (ICT.Zones) -> Series) -> ScriptFunction {
            ScriptFunction(name, swingParameters + [.length("lookback", default: 20)], category: category, summary: summary) { args in
                let d = args.data
                let s = try structure(args)
                return .series(pick(ICT.orderBlocks(open: d.open, high: d.high, low: d.low, close: d.close,
                                                    structure: s, lookback: try args.length(2))))
            }
        }
        return [
            fvg("bull_fvg_top", "Cạnh trên FVG tăng gần nhất chưa bị lấp hết") { $0.bullTop },
            fvg("bull_fvg_bottom", "Cạnh dưới FVG tăng gần nhất chưa bị lấp hết") { $0.bullBottom },
            fvg("bull_fvg_ce", "CE (50%) của FVG tăng gần nhất") { z in zip(z.bullTop, z.bullBottom).map { ($0 + $1) / 2 } },
            fvg("bear_fvg_top", "Cạnh trên FVG giảm gần nhất chưa bị lấp hết") { $0.bearTop },
            fvg("bear_fvg_bottom", "Cạnh dưới FVG giảm gần nhất chưa bị lấp hết") { $0.bearBottom },
            fvg("bear_fvg_ce", "CE (50%) của FVG giảm gần nhất") { z in zip(z.bearTop, z.bearBottom).map { ($0 + $1) / 2 } },
            orderBlock("bull_ob_top", "Đỉnh order block tăng (nến giảm cuối trước cú phá cấu trúc tăng)") { $0.bullTop },
            orderBlock("bull_ob_bottom", "Đáy order block tăng; mất hiệu lực khi đóng cửa dưới đáy") { $0.bullBottom },
            orderBlock("bear_ob_top", "Đỉnh order block giảm; mất hiệu lực khi đóng cửa trên đỉnh") { $0.bearTop },
            orderBlock("bear_ob_bottom", "Đáy order block giảm (nến tăng cuối trước cú phá cấu trúc giảm)") { $0.bearBottom },
        ]
    }
}

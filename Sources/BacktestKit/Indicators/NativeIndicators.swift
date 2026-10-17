import Foundation

/// Indicators written in Swift instead of the script language.
///
/// Use this for logic that is stateful bar-by-bar (trailing stops, state
/// machines, order-block tracking…) or simply too slow as a script. Every
/// function registered here can be called from any script or strategy just
/// like a built-in, e.g. `supertrend(10, 3)`.
///
/// To add your own:
/// 1. Write a `ScriptFunction` like the examples below.
/// 2. Append it to `NativeIndicators.all`.
///
/// ```swift
/// ScriptFunction("my_indicator", [.source(), .length(default: 14)],
///                category: NativeIndicators.category,
///                summary: "Mô tả ngắn") { args in
///     let source = args.series(0)        // series argument (numbers are broadcast)
///     let length = try args.length(1)    // constant >= 1
///     var out = Series(repeating: .nan, count: args.count)
///     for i in length..<args.count { out[i] = source[i] - source[i - length] }
///     return .series(out)
/// }
/// ```
public enum NativeIndicators {
    public static let category = "Native (Swift)"

    public static var all: [ScriptFunction] {
        [supertrend, supertrendDirection, fairValueGapBull, fairValueGapBear, swingHighLevel, swingLowLevel]
    }

    public static var supertrend: ScriptFunction {
        ScriptFunction("supertrend", [.length(default: 10), FunctionParameter("mult", .number, default: 3)],
                       category: category, summary: "Đường Supertrend (ATR trailing stop)") { args in
            let d = args.data
            return .series(TA.supertrend(high: d.high, low: d.low, close: d.close,
                                         length: try args.length(0), multiplier: args.number(1)).line)
        }
    }

    public static var supertrendDirection: ScriptFunction {
        ScriptFunction("supertrend_dir", [.length(default: 10), FunctionParameter("mult", .number, default: 3)],
                       category: category, summary: "Hướng Supertrend: 1 = tăng, −1 = giảm") { args in
            let d = args.data
            return .series(TA.supertrend(high: d.high, low: d.low, close: d.close,
                                         length: try args.length(0), multiplier: args.number(1)).direction)
        }
    }

    /// Bullish fair value gap (ICT): `low` of the current bar above `high` two
    /// bars back. Returns the gap size, 0 when there is none.
    public static var fairValueGapBull: ScriptFunction {
        ScriptFunction("fvg_bull", [FunctionParameter("min_size", .number, default: 0)],
                       category: category, summary: "FVG tăng: kích thước khoảng trống low − high[2], 0 nếu không có") { args in
            let d = args.data
            let minimum = args.number(0)
            return .series(d.close.indices.map { i in
                guard i >= 2 else { return 0 }
                let gap = d.low[i] - d.high[i - 2]
                return gap > minimum ? gap : 0
            })
        }
    }

    public static var fairValueGapBear: ScriptFunction {
        ScriptFunction("fvg_bear", [FunctionParameter("min_size", .number, default: 0)],
                       category: category, summary: "FVG giảm: kích thước khoảng trống low[2] − high, 0 nếu không có") { args in
            let d = args.data
            let minimum = args.number(0)
            return .series(d.close.indices.map { i in
                guard i >= 2 else { return 0 }
                let gap = d.low[i - 2] - d.high[i]
                return gap > minimum ? gap : 0
            })
        }
    }

    /// Price of the most recent confirmed swing high, held until the next one
    /// (useful as a buy-side liquidity level).
    public static var swingHighLevel: ScriptFunction {
        ScriptFunction("swing_high", [.length("left", default: 5), .length("right", default: 5)],
                       category: category, summary: "Mức đỉnh swing gần nhất đã xác nhận (thanh khoản phía mua)") { args in
            let pivots = TA.pivothigh(args.data.high, left: try args.length(0), right: try args.length(1))
            return .series(holdLast(pivots))
        }
    }

    public static var swingLowLevel: ScriptFunction {
        ScriptFunction("swing_low", [.length("left", default: 5), .length("right", default: 5)],
                       category: category, summary: "Mức đáy swing gần nhất đã xác nhận (thanh khoản phía bán)") { args in
            let pivots = TA.pivotlow(args.data.low, left: try args.length(0), right: try args.length(1))
            return .series(holdLast(pivots))
        }
    }

    static func holdLast(_ series: Series) -> Series {
        var last = Double.nan
        return series.map { value in
            if !value.isNaN { last = value }
            return last
        }
    }
}

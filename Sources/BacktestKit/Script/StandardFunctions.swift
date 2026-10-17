import Foundation

/// Built-in functions of the script language.
enum StandardFunctions {
    static let movingAverages = "Trung bình động"
    static let oscillators = "Dao động"
    static let volatility = "Biến động"
    static let trend = "Xu hướng"
    static let volumeCategory = "Khối lượng"
    static let events = "Tín hiệu & sự kiện"
    static let statistics = "Thống kê"
    static let math = "Toán học"
    static let sessions = "Thời gian & phiên"

    static var all: [ScriptFunction] {
        movingAverageFunctions + oscillatorFunctions + volatilityFunctions + trendFunctions
            + volumeFunctions + eventFunctions + statisticsFunctions + mathFunctions + sessionFunctions
    }

    /// `name(source, length)` functions backed by a TA routine.
    private static func sourceLength(_ name: String, _ category: String, _ summary: String,
                                     defaultLength: Double? = nil,
                                     _ compute: @escaping (Series, Int) -> Series) -> ScriptFunction {
        ScriptFunction(name, [.source(), .length(default: defaultLength)], category: category, summary: summary) { args in
            .series(compute(args.series(0), try args.length(1)))
        }
    }

    // MARK: Moving averages

    static var movingAverageFunctions: [ScriptFunction] {
        [
            sourceLength("sma", movingAverages, "Trung bình cộng đơn giản", TA.sma),
            sourceLength("ema", movingAverages, "Trung bình hàm mũ", TA.ema),
            sourceLength("rma", movingAverages, "Trung bình Wilder (dùng trong RSI, ATR)", TA.rma),
            sourceLength("wma", movingAverages, "Trung bình có trọng số tuyến tính", TA.wma),
            sourceLength("hma", movingAverages, "Hull moving average", TA.hma),
            ScriptFunction("vwma", [.source(), .length()], category: movingAverages,
                           summary: "Trung bình gia quyền theo khối lượng") { args in
                .series(TA.vwma(args.series(0), args.data.volume, try args.length(1)))
            },
            ScriptFunction("kama", [.source(), .length(default: 10), .length("fast", default: 2), .length("slow", default: 30)],
                           category: movingAverages, summary: "Kaufman adaptive moving average") { args in
                .series(TA.kama(args.series(0), try args.length(1), fast: try args.length(2), slow: try args.length(3)))
            },
        ]
    }

    // MARK: Oscillators

    static var oscillatorFunctions: [ScriptFunction] {
        [
            sourceLength("rsi", oscillators, "Relative Strength Index (0–100)", defaultLength: 14, TA.rsi),
            ScriptFunction("macd", [.source(), .length("fast", default: 12), .length("slow", default: 26), .length("signal", default: 9)],
                           category: oscillators, summary: "Đường MACD = EMA nhanh − EMA chậm") { args in
                .series(try macd(args).line)
            },
            ScriptFunction("macd_signal", [.source(), .length("fast", default: 12), .length("slow", default: 26), .length("signal", default: 9)],
                           category: oscillators, summary: "Đường tín hiệu MACD") { args in
                .series(try macd(args).signal)
            },
            ScriptFunction("macd_hist", [.source(), .length("fast", default: 12), .length("slow", default: 26), .length("signal", default: 9)],
                           category: oscillators, summary: "Histogram MACD = MACD − tín hiệu") { args in
                .series(try macd(args).histogram)
            },
            ScriptFunction("stoch", [.length(default: 14), .length("smooth", default: 1)],
                           category: oscillators, summary: "Stochastic %K (0–100) trên high/low/close") { args in
                let d = args.data
                return .series(TA.stoch(high: d.high, low: d.low, close: d.close, length: try args.length(0), smooth: try args.length(1)))
            },
            ScriptFunction("cci", [.length(default: 20)], category: oscillators, summary: "Commodity Channel Index") { args in
                let d = args.data
                return .series(TA.cci(high: d.high, low: d.low, close: d.close, length: try args.length(0)))
            },
            sourceLength("roc", oscillators, "Tốc độ thay đổi (%) so với length nến trước", TA.roc),
            ScriptFunction("mom", [.source(), .length(default: 10)], category: oscillators,
                           summary: "Động lượng = source − source[length]") { args in
                .series(TA.change(args.series(0), try args.length(1)))
            },
        ]
    }

    private static func macd(_ args: CallArguments) throws -> TA.MACD {
        TA.macd(args.series(0), fast: try args.length(1), slow: try args.length(2), signal: try args.length(3))
    }

    // MARK: Volatility

    static var volatilityFunctions: [ScriptFunction] {
        [
            ScriptFunction("tr", [], category: volatility, summary: "True range") { args in
                let d = args.data
                return .series(TA.trueRange(high: d.high, low: d.low, close: d.close))
            },
            ScriptFunction("atr", [.length(default: 14)], category: volatility, summary: "Average True Range") { args in
                let d = args.data
                return .series(TA.atr(high: d.high, low: d.low, close: d.close, length: try args.length(0)))
            },
            bandFunction("bb_upper", "Dải trên Bollinger") { $0.upper },
            bandFunction("bb_mid", "Dải giữa Bollinger (SMA)") { $0.middle },
            bandFunction("bb_lower", "Dải dưới Bollinger") { $0.lower },
            keltnerFunction("kc_upper", "Dải trên Keltner (EMA + mult × ATR)") { $0.upper },
            keltnerFunction("kc_lower", "Dải dưới Keltner (EMA − mult × ATR)") { $0.lower },
        ]
    }

    private static func bandFunction(_ name: String, _ summary: String, _ pick: @escaping (TA.Bands) -> Series) -> ScriptFunction {
        ScriptFunction(name, [.source(), .length(default: 20), FunctionParameter("mult", .number, default: 2)],
                       category: volatility, summary: summary) { args in
            .series(pick(TA.bollinger(args.series(0), length: try args.length(1), multiplier: args.number(2))))
        }
    }

    private static func keltnerFunction(_ name: String, _ summary: String, _ pick: @escaping (TA.Bands) -> Series) -> ScriptFunction {
        ScriptFunction(name, [.length(default: 20), FunctionParameter("mult", .number, default: 2)],
                       category: volatility, summary: summary) { args in
            let d = args.data
            return .series(pick(TA.keltner(high: d.high, low: d.low, close: d.close, length: try args.length(0), multiplier: args.number(1))))
        }
    }

    // MARK: Trend

    static var trendFunctions: [ScriptFunction] {
        func dmi(_ name: String, _ summary: String, _ pick: @escaping (TA.DirectionalMovement) -> Series) -> ScriptFunction {
            ScriptFunction(name, [.length(default: 14)], category: trend, summary: summary) { args in
                let d = args.data
                return .series(pick(TA.dmi(high: d.high, low: d.low, close: d.close, length: try args.length(0))))
            }
        }
        return [
            dmi("adx", "Average Directional Index (sức mạnh xu hướng)") { $0.adx },
            dmi("plus_di", "+DI") { $0.plusDI },
            dmi("minus_di", "−DI") { $0.minusDI },
            sourceLength("highest", trend, "Giá trị lớn nhất trong length nến", TA.highest),
            sourceLength("lowest", trend, "Giá trị nhỏ nhất trong length nến", TA.lowest),
            ScriptFunction("pivothigh", [.source(), .length("left", default: 5), .length("right", default: 5)],
                           category: trend,
                           summary: "Đỉnh swing; báo tại nến xác nhận (sau right nến), NaN nếu không có") { args in
                .series(TA.pivothigh(args.series(0), left: try args.length(1), right: try args.length(2)))
            },
            ScriptFunction("pivotlow", [.source(), .length("left", default: 5), .length("right", default: 5)],
                           category: trend,
                           summary: "Đáy swing; báo tại nến xác nhận (sau right nến), NaN nếu không có") { args in
                .series(TA.pivotlow(args.series(0), left: try args.length(1), right: try args.length(2)))
            },
        ]
    }

    // MARK: Volume

    static var volumeFunctions: [ScriptFunction] {
        [
            ScriptFunction("obv", [], category: volumeCategory, summary: "On-Balance Volume") { args in
                .series(TA.obv(close: args.data.close, volume: args.data.volume))
            },
            ScriptFunction("vwap", [], category: volumeCategory, summary: "VWAP reset mỗi ngày (theo múi giờ đã chọn)") { args in
                let d = args.data
                return .series(TA.vwap(high: d.high, low: d.low, close: d.close, volume: d.volume,
                                       time: d.time, timeZone: args.context.timeZone))
            },
        ]
    }

    // MARK: Events

    static var eventFunctions: [ScriptFunction] {
        [
            ScriptFunction("crossover", [.source("a"), .source("b")], category: events,
                           summary: "1 khi a cắt lên trên b") { args in
                .series(TA.crossover(args.series(0), args.series(1)))
            },
            ScriptFunction("crossunder", [.source("a"), .source("b")], category: events,
                           summary: "1 khi a cắt xuống dưới b") { args in
                .series(TA.crossunder(args.series(0), args.series(1)))
            },
            ScriptFunction("cross", [.source("a"), .source("b")], category: events,
                           summary: "1 khi a cắt b theo bất kỳ hướng nào") { args in
                let up = TA.crossover(args.series(0), args.series(1))
                let down = TA.crossunder(args.series(0), args.series(1))
                return .series(zip(up, down).map { $0 + $1 > 0 ? 1 : 0 })
            },
            sourceLength("rising", events, "1 khi source cao hơn mọi giá trị của length nến trước", TA.rising),
            sourceLength("falling", events, "1 khi source thấp hơn mọi giá trị của length nến trước", TA.falling),
            ScriptFunction("barssince", [.source("condition")], category: events,
                           summary: "Số nến kể từ lần gần nhất condition đúng") { args in
                .series(TA.barssince(args.series(0)))
            },
            ScriptFunction("valuewhen", [.source("condition"), .source(), FunctionParameter("occurrence", .number, default: 0)],
                           category: events, summary: "Giá trị source tại lần thứ occurrence (0 = gần nhất) condition đúng") { args in
                .series(TA.valuewhen(args.series(0), args.series(1), try args.integer(2)))
            },
            ScriptFunction("change", [.source(), .length(default: 1)], category: events,
                           summary: "source − source[length]") { args in
                .series(TA.change(args.series(0), try args.length(1)))
            },
        ]
    }

    // MARK: Statistics

    static var statisticsFunctions: [ScriptFunction] {
        [
            sourceLength("stdev", statistics, "Độ lệch chuẩn (population)", TA.stdev),
            sourceLength("variance", statistics, "Phương sai", TA.variance),
            sourceLength("sum", statistics, "Tổng length giá trị gần nhất", TA.sum),
            ScriptFunction("cum", [.source()], category: statistics, summary: "Tổng tích luỹ từ đầu dữ liệu") { args in
                .series(TA.cum(args.series(0)))
            },
            ScriptFunction("zscore", [.source(), .length(default: 20)], category: statistics,
                           summary: "(source − SMA) / stdev") { args in
                let s = args.series(0)
                let n = try args.length(1)
                let mean = TA.sma(s, n)
                let deviation = TA.stdev(s, n)
                return .series(s.indices.map { deviation[$0] == 0 ? .nan : (s[$0] - mean[$0]) / deviation[$0] })
            },
        ]
    }

    // MARK: Math

    static var mathFunctions: [ScriptFunction] {
        func unary(_ name: String, _ summary: String, _ f: @escaping (Double) -> Double) -> ScriptFunction {
            ScriptFunction(name, [.source("x")], category: math, summary: summary) { args in
                Value.map(args.values[0], f)
            }
        }
        func reduce(_ name: String, _ summary: String, _ f: @escaping ([Double]) -> Double) -> ScriptFunction {
            ScriptFunction(name, [.source("a"), .source("b")], category: math, summary: summary, isVariadic: true) { args in
                if args.allScalar {
                    return .scalar(f(args.values.map { $0.value(at: 0) }))
                }
                let columns = args.values.map { $0.series(count: args.count) }
                return .series((0..<args.count).map { i in f(columns.map { $0[i] }) })
            }
        }
        return [
            unary("abs", "Giá trị tuyệt đối", Swift.abs),
            unary("sqrt", "Căn bậc hai") { $0.squareRoot() },
            unary("log", "Logarit tự nhiên", Foundation.log),
            unary("log10", "Logarit cơ số 10", Foundation.log10),
            unary("exp", "e mũ x", Foundation.exp),
            unary("floor", "Làm tròn xuống", Foundation.floor),
            unary("ceil", "Làm tròn lên", Foundation.ceil),
            unary("sign", "Dấu: −1, 0 hoặc 1") { $0.isNaN ? .nan : ($0 > 0 ? 1 : ($0 < 0 ? -1 : 0)) },
            unary("na", "1 nếu x là NaN (chưa có giá trị)") { $0.isNaN ? 1 : 0 },
            ScriptFunction("round", [.source("x"), FunctionParameter("decimals", .number, default: 0)],
                           category: math, summary: "Làm tròn tới decimals chữ số") { args in
                let factor = pow(10, args.number(1))
                return Value.map(args.values[0]) { ($0 * factor).rounded() / factor }
            },
            ScriptFunction("pow", [.source("x"), .source("y")], category: math, summary: "x mũ y") { args in
                Value.combine(args.values[0], args.values[1], count: args.count, Foundation.pow)
            },
            ScriptFunction("nz", [.source("x"), FunctionParameter("replacement", .series, default: 0)],
                           category: math, summary: "Thay NaN bằng replacement (mặc định 0)") { args in
                let replacement = args.values.count > 1 ? args.values[1] : .scalar(0)
                return Value.combine(args.values[0], replacement, count: args.count) { $0.isNaN ? $1 : $0 }
            },
            ScriptFunction("iff", [.source("condition"), .source("a"), .source("b")], category: math,
                           summary: "a nếu condition đúng, ngược lại b (giống condition ? a : b)") { args in
                let c = args.series(0), a = args.series(1), b = args.series(2)
                return .series((0..<args.count).map { c[$0].isTruthy ? a[$0] : b[$0] })
            },
            ScriptFunction("clamp", [.source("x"), .source("lo"), .source("hi")], category: math,
                           summary: "Giới hạn x trong [lo, hi]") { args in
                let x = args.series(0), lo = args.series(1), hi = args.series(2)
                return .series((0..<args.count).map { Swift.min(Swift.max(x[$0], lo[$0]), hi[$0]) })
            },
            reduce("max", "Giá trị lớn nhất của các tham số") { values in
                values.contains(where: \.isNaN) ? .nan : values.max() ?? .nan
            },
            reduce("min", "Giá trị nhỏ nhất của các tham số") { values in
                values.contains(where: \.isNaN) ? .nan : values.min() ?? .nan
            },
            reduce("avg", "Trung bình các tham số") { values in
                values.reduce(0, +) / Double(values.count)
            },
        ]
    }

    // MARK: Sessions

    static var sessionFunctions: [ScriptFunction] {
        [
            ScriptFunction("session", [FunctionParameter("start", .number), FunctionParameter("end", .number)],
                           category: sessions,
                           summary: "1 khi giờ nến trong [start, end), giờ thập phân theo múi giờ đã chọn, ví dụ session(14, 17) hoặc session(19.5, 22)") { args in
                let start = args.number(0)
                let end = args.number(1)
                return .series(args.context.hourOfDay.map { hour in
                    let inside = start <= end ? (hour >= start && hour < end) : (hour >= start || hour < end)
                    return inside ? 1 : 0
                })
            },
            ScriptFunction("newday", [], category: sessions, summary: "1 tại nến đầu tiên của mỗi ngày") { args in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = args.context.timeZone
                let days = args.data.time.map { calendar.ordinality(of: .day, in: .era, for: $0) ?? 0 }
                return .series(days.indices.map { $0 == 0 || days[$0] != days[$0 - 1] ? 1 : 0 })
            },
            ScriptFunction("daily_high", [], category: sessions, summary: "Đỉnh của ngày hôm trước (PDH)") { args in
                .series(previousDay(args, { $0.max() ?? .nan }, source: args.data.high))
            },
            ScriptFunction("daily_low", [], category: sessions, summary: "Đáy của ngày hôm trước (PDL)") { args in
                .series(previousDay(args, { $0.min() ?? .nan }, source: args.data.low))
            },
        ]
    }

    /// For every bar, `reduce` applied to `source` over the previous calendar day.
    private static func previousDay(_ args: CallArguments, _ reduce: ([Double]) -> Double, source: Series) -> Series {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = args.context.timeZone
        let days = args.data.time.map { calendar.ordinality(of: .day, in: .era, for: $0) ?? 0 }
        var out = Series(repeating: .nan, count: args.count)
        var previousValue = Double.nan
        var currentBucket: [Double] = []
        for i in 0..<args.count {
            if i > 0, days[i] != days[i - 1] {
                previousValue = reduce(currentBucket)
                currentBucket = []
            }
            currentBucket.append(source[i])
            out[i] = previousValue
        }
        return out
    }
}

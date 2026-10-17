import Foundation

/// Shared state for one evaluation over one data set: the price data, the
/// functions that can be called, and caches reused by nested indicator calls.
public final class EvaluationContext {
    public let data: PriceData
    public let library: FunctionLibrary
    public let timeZone: TimeZone
    var depth = 0
    var callCache: [String: Value] = [:]
    private var variableCache: [String: Value] = [:]

    static let maxDepth = 16

    public init(data: PriceData, library: FunctionLibrary = .standard, timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
        self.data = data
        self.library = library
        self.timeZone = timeZone
    }

    public var count: Int { data.count }

    /// Price and time variables available in every script.
    public static let builtinVariables: [(name: String, summary: String)] = [
        ("open", "Giá mở cửa"),
        ("high", "Giá cao nhất"),
        ("low", "Giá thấp nhất"),
        ("close", "Giá đóng cửa"),
        ("volume", "Khối lượng"),
        ("hl2", "(high + low) / 2"),
        ("hlc3", "(high + low + close) / 3"),
        ("ohlc4", "(open + high + low + close) / 4"),
        ("hlcc4", "(high + low + 2 × close) / 4"),
        ("bar_index", "Số thứ tự nến, bắt đầu từ 0"),
        ("time", "Thời gian mở nến (unix giây)"),
        ("year", "Năm"),
        ("month", "Tháng (1–12)"),
        ("dayofmonth", "Ngày trong tháng"),
        ("dayofweek", "Thứ trong tuần: 1 = Chủ nhật … 7 = Thứ bảy"),
        ("hour", "Giờ (0–23) theo múi giờ đã chọn"),
        ("minute", "Phút (0–59)"),
        ("na", "Giá trị rỗng (NaN)"),
        ("pi", "Số π"),
    ]

    func builtinVariable(_ name: String) -> Value? {
        if let cached = variableCache[name] { return cached }
        let d = data
        let value: Value
        switch name {
        case "open": value = .series(d.open)
        case "high": value = .series(d.high)
        case "low": value = .series(d.low)
        case "close": value = .series(d.close)
        case "volume": value = .series(d.volume)
        case "hl2": value = .series(d.close.indices.map { (d.high[$0] + d.low[$0]) / 2 })
        case "hlc3": value = .series(TA.typicalPrice(high: d.high, low: d.low, close: d.close))
        case "ohlc4": value = .series(d.close.indices.map { (d.open[$0] + d.high[$0] + d.low[$0] + d.close[$0]) / 4 })
        case "hlcc4": value = .series(d.close.indices.map { (d.high[$0] + d.low[$0] + 2 * d.close[$0]) / 4 })
        case "bar_index": value = .series(d.close.indices.map(Double.init))
        case "time": value = .series(d.time.map(\.timeIntervalSince1970))
        case "year": value = calendarSeries(.year)
        case "month": value = calendarSeries(.month)
        case "dayofmonth": value = calendarSeries(.day)
        case "dayofweek": value = calendarSeries(.weekday)
        case "hour": value = calendarSeries(.hour)
        case "minute": value = calendarSeries(.minute)
        case "na": value = .scalar(.nan)
        case "pi": value = .scalar(Double.pi)
        default: return nil
        }
        variableCache[name] = value
        return value
    }

    private func calendarSeries(_ component: Calendar.Component) -> Value {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return .series(data.time.map { Double(calendar.component(component, from: $0)) })
    }

    /// Fractional hour of day (e.g. 14.5 for 14:30) for every bar.
    lazy var hourOfDay: Series = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return data.time.map {
            let c = calendar.dateComponents([.hour, .minute], from: $0)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
    }()
}

/// Runs a parsed program, statement by statement, over whole series at once.
public struct Evaluator {
    public let context: EvaluationContext
    private(set) var variables: [String: Value]
    private var plots: [Plot] = []

    public init(context: EvaluationContext, bindings: [String: Value] = [:]) {
        self.context = context
        variables = bindings
    }

    public static func run(_ source: String, context: EvaluationContext, bindings: [String: Value] = [:]) throws -> ScriptResult {
        try run(Parser.parse(source), context: context, bindings: bindings)
    }

    public static func run(_ program: Program, context: EvaluationContext, bindings: [String: Value] = [:]) throws -> ScriptResult {
        var evaluator = Evaluator(context: context, bindings: bindings)
        return try evaluator.run(program)
    }

    public mutating func run(_ program: Program) throws -> ScriptResult {
        var last: Value?
        for statement in program.statements {
            switch statement {
            case .assign(let name, let expr, let location):
                let value = try evaluate(expr)
                if case .text = value {
                    throw ScriptError("Không thể gán chuỗi ký tự cho biến \"\(name)\"", at: location)
                }
                variables[name] = value
            case .expression(let expr):
                last = try evaluate(expr)
            }
        }
        return ScriptResult(variables: variables, plots: plots, lastValue: last)
    }

    mutating func evaluate(_ expr: Expr) throws -> Value {
        let count = context.count
        switch expr {
        case .number(let v):
            return .scalar(v)

        case .string(let s):
            return .text(s)

        case .variable(let name, let location):
            if let value = variables[name] { return value }
            if let value = context.builtinVariable(name) { return value }
            if let function = context.library.function(named: name),
               function.parameters.allSatisfy({ $0.defaultValue != nil }) {
                // Allow calling zero-argument functions without parentheses, e.g. `atr`.
                return try call(name, [], location)
            }
            throw ScriptError("Không biết biến \"\(name)\"", at: location)

        case .unary(let op, let operand, let location):
            let value = try evaluate(operand)
            try requireNumeric(value, location)
            switch op {
            case "-": return Value.map(value) { -$0 }
            case "not": return Value.map(value) { $0.isTruthy ? 0 : 1 }
            default: throw ScriptError("Toán tử không hợp lệ \(op)", at: location)
            }

        case .binary(let op, let lhs, let rhs, let location):
            let a = try evaluate(lhs)
            let b = try evaluate(rhs)
            try requireNumeric(a, location)
            try requireNumeric(b, location)
            guard let function = Self.binaryOperators[op] else {
                throw ScriptError("Toán tử không hợp lệ \(op)", at: location)
            }
            return Value.combine(a, b, count: count, function)

        case .ternary(let condition, let whenTrue, let whenFalse, let location):
            let c = try evaluate(condition)
            let a = try evaluate(whenTrue)
            let b = try evaluate(whenFalse)
            for v in [c, a, b] { try requireNumeric(v, location) }
            if case .scalar(let flag) = c { return flag.isTruthy ? a : b }
            let cs = c.series(count: count)
            let av = a.series(count: count)
            let bv = b.series(count: count)
            return .series((0..<count).map { cs[$0].isTruthy ? av[$0] : bv[$0] })

        case .history(let base, let offsetExpr, let location):
            let value = try evaluate(base)
            let offset = try evaluate(offsetExpr)
            try requireNumeric(value, location)
            switch offset {
            case .scalar(let n):
                guard n >= 0, n == n.rounded() else {
                    throw ScriptError("Chỉ số lịch sử [\(n)] phải là số nguyên ≥ 0 (không được nhìn vào tương lai)", at: location)
                }
                if case .scalar = value { return value }
                return .series(TA.shift(value.series(count: count), Int(n)))
            case .series(let offsets):
                let s = value.series(count: count)
                return .series((0..<count).map { i in
                    let n = offsets[i]
                    guard !n.isNaN, n >= 0 else { return .nan }
                    let j = i - Int(n)
                    return j >= 0 ? s[j] : .nan
                })
            case .text:
                throw ScriptError("Chỉ số lịch sử phải là số", at: location)
            }

        case .call(let name, let argExprs, let location):
            if name == "plot" || name == "hline" {
                return try plot(name, argExprs, location)
            }
            let args = try argExprs.map { try evaluate($0) }
            return try call(name, args, location)
        }
    }

    private func call(_ name: String, _ args: [Value], _ location: SourceLocation) throws -> Value {
        guard let function = context.library.function(named: name) else {
            throw ScriptError("Không biết hàm \"\(name)\"", at: location)
        }
        let arguments = try CallArguments(function: function, values: args, context: context, location: location)
        do {
            return try function.body(arguments)
        } catch var error as ScriptError {
            if error.location == nil { error.location = location }
            throw error
        }
    }

    private mutating func plot(_ name: String, _ argExprs: [Expr], _ location: SourceLocation) throws -> Value {
        guard let first = argExprs.first else {
            throw ScriptError("\(name)() cần ít nhất 1 tham số", at: location)
        }
        let value = try evaluate(first)
        try requireNumeric(value, location)
        var title = name == "hline" ? first.description : "Plot \(plots.count + 1)"
        if argExprs.count > 1 {
            guard case .text(let text) = try evaluate(argExprs[1]) else {
                throw ScriptError("Tham số thứ 2 của \(name)() phải là tên trong dấu nháy, ví dụ \"EMA nhanh\"", at: location)
            }
            title = text
        } else if case .variable(let variable, _) = first {
            title = variable
        }
        plots.append(Plot(title: title, values: value.series(count: context.count), isHorizontalLine: name == "hline"))
        return value
    }

    private func requireNumeric(_ value: Value, _ location: SourceLocation) throws {
        if case .text = value {
            throw ScriptError("Không dùng chuỗi ký tự trong phép tính", at: location)
        }
    }

    static let binaryOperators: [String: (Double, Double) -> Double] = [
        "+": (+),
        "-": (-),
        "*": (*),
        "/": { $1 == 0 ? .nan : $0 / $1 },
        "%": { $1 == 0 ? .nan : $0.truncatingRemainder(dividingBy: $1) },
        "^": { pow($0, $1) },
        "<": { $0.isNaN || $1.isNaN ? 0 : ($0 < $1 ? 1 : 0) },
        "<=": { $0.isNaN || $1.isNaN ? 0 : ($0 <= $1 ? 1 : 0) },
        ">": { $0.isNaN || $1.isNaN ? 0 : ($0 > $1 ? 1 : 0) },
        ">=": { $0.isNaN || $1.isNaN ? 0 : ($0 >= $1 ? 1 : 0) },
        "==": { $0.isNaN || $1.isNaN ? 0 : ($0 == $1 ? 1 : 0) },
        "!=": { $0.isNaN || $1.isNaN ? 0 : ($0 != $1 ? 1 : 0) },
        "and": { $0.isTruthy && $1.isTruthy ? 1 : 0 },
        "or": { $0.isTruthy || $1.isTruthy ? 1 : 0 },
    ]
}

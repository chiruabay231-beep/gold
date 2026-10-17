import Foundation

/// Runtime value of the script language.
public enum Value: Equatable {
    case scalar(Double)
    case series(Series)
    case text(String)

    public func series(count: Int) -> Series {
        switch self {
        case .scalar(let v): return Series(repeating: v, count: count)
        case .series(let s): return s
        case .text: return Series(repeating: .nan, count: count)
        }
    }

    /// Value at bar `index` (scalars are the same on every bar).
    public func value(at index: Int) -> Double {
        switch self {
        case .scalar(let v): return v
        case .series(let s): return index < s.count ? s[index] : .nan
        case .text: return .nan
        }
    }

    var typeName: String {
        switch self {
        case .scalar: return "số"
        case .series: return "chuỗi dữ liệu (series)"
        case .text: return "chuỗi ký tự"
        }
    }

    static func map(_ value: Value, _ transform: (Double) -> Double) -> Value {
        switch value {
        case .scalar(let v): return .scalar(transform(v))
        case .series(let s): return .series(s.map(transform))
        case .text: return value
        }
    }

    static func combine(_ a: Value, _ b: Value, count: Int, _ op: (Double, Double) -> Double) -> Value {
        if case .scalar(let x) = a, case .scalar(let y) = b { return .scalar(op(x, y)) }
        let left = a.series(count: count)
        let right = b.series(count: count)
        var out = Series(repeating: .nan, count: count)
        for i in 0..<count { out[i] = op(left[i], right[i]) }
        return .series(out)
    }
}

/// A line produced by `plot()` / `hline()` in a script.
public struct Plot: Equatable {
    public var title: String
    public var values: Series
    public var isHorizontalLine: Bool

    public init(title: String, values: Series, isHorizontalLine: Bool = false) {
        self.title = title
        self.values = values
        self.isHorizontalLine = isHorizontalLine
    }
}

/// Everything a script run produced.
public struct ScriptResult {
    /// Final value of every assigned variable.
    public var variables: [String: Value]
    /// Plots in call order.
    public var plots: [Plot]
    /// Value of the last expression statement, if any.
    public var lastValue: Value?

    /// The indicator's outputs: explicit plots, or the last expression.
    public func outputs(defaultTitle: String, count: Int) -> [Plot] {
        if !plots.isEmpty { return plots }
        if let lastValue { return [Plot(title: defaultTitle, values: lastValue.series(count: count))] }
        return []
    }
}

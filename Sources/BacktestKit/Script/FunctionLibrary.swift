import Foundation

public struct FunctionParameter: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A series; a plain number is broadcast to every bar.
        case series
        /// A constant number such as a length or multiplier.
        case number
    }

    public var name: String
    public var kind: Kind
    public var defaultValue: Double?

    public init(_ name: String, _ kind: Kind = .series, default defaultValue: Double? = nil) {
        self.name = name
        self.kind = kind
        self.defaultValue = defaultValue
    }

    public static func source(_ name: String = "source") -> FunctionParameter {
        FunctionParameter(name, .series)
    }

    public static func length(_ name: String = "length", default value: Double? = nil) -> FunctionParameter {
        FunctionParameter(name, .number, default: value)
    }
}

/// Arguments of one call, already evaluated and checked against the signature.
public struct CallArguments {
    public let function: ScriptFunction
    public let values: [Value]
    public let context: EvaluationContext
    public let location: SourceLocation

    init(function: ScriptFunction, values: [Value], context: EvaluationContext, location: SourceLocation) throws {
        let required = function.parameters.filter { $0.defaultValue == nil }.count
        if values.count < required || (!function.isVariadic && values.count > function.parameters.count) {
            let expected = function.isVariadic ? "ít nhất \(required)" :
                (required == function.parameters.count ? "\(required)" : "\(required)–\(function.parameters.count)")
            throw ScriptError("\(function.name)() cần \(expected) tham số, nhận \(values.count)", at: location)
        }
        for (index, value) in values.enumerated() {
            let parameter = function.parameters[min(index, function.parameters.count - 1)]
            if case .text = value {
                throw ScriptError("Tham số \(parameter.name) của \(function.name)() không nhận chuỗi ký tự", at: location)
            }
            if parameter.kind == .number, case .series = value {
                throw ScriptError("Tham số \(parameter.name) của \(function.name)() phải là hằng số (ví dụ 14), không phải series", at: location)
            }
        }
        self.function = function
        self.values = values
        self.context = context
        self.location = location
    }

    public var data: PriceData { context.data }
    public var count: Int { context.count }

    /// Argument `index` as a series, falling back to the parameter default.
    public func series(_ index: Int) -> Series {
        if index < values.count { return values[index].series(count: count) }
        let fallback = function.parameters[index].defaultValue ?? .nan
        return Series(repeating: fallback, count: count)
    }

    public func number(_ index: Int) -> Double {
        if index < values.count, case .scalar(let v) = values[index] { return v }
        return function.parameters[index].defaultValue ?? .nan
    }

    /// A positive integer argument such as a period length.
    public func length(_ index: Int) throws -> Int {
        let value = number(index)
        guard value.isFinite, value >= 1 else {
            throw ScriptError("Tham số \(function.parameters[index].name) của \(function.name)() phải ≥ 1", at: location)
        }
        return Int(value.rounded())
    }

    public func integer(_ index: Int, minimum: Int = 0) throws -> Int {
        let value = number(index)
        guard value.isFinite, value >= Double(minimum) else {
            throw ScriptError("Tham số \(function.parameters[index].name) của \(function.name)() phải ≥ \(minimum)", at: location)
        }
        return Int(value.rounded())
    }

    /// True when every argument is a constant, so the result is a constant.
    public var allScalar: Bool {
        values.allSatisfy { if case .scalar = $0 { return true } else { return false } }
    }
}

/// A function callable from scripts.
public struct ScriptFunction {
    public var name: String
    public var parameters: [FunctionParameter]
    public var category: String
    public var summary: String
    /// When true, the last parameter may repeat (e.g. `max(a, b, c)`).
    public var isVariadic: Bool
    public var body: (CallArguments) throws -> Value

    public init(_ name: String,
                _ parameters: [FunctionParameter],
                category: String,
                summary: String,
                isVariadic: Bool = false,
                body: @escaping (CallArguments) throws -> Value) {
        self.name = name
        self.parameters = parameters
        self.category = category
        self.summary = summary
        self.isVariadic = isVariadic
        self.body = body
    }

    /// e.g. `ema(source, length)` or `rsi(source, length = 14)`.
    public var signature: String {
        let params = parameters.map { p -> String in
            guard let d = p.defaultValue else { return p.name }
            let text = d == d.rounded() ? String(Int(d)) : String(d)
            return "\(p.name) = \(text)"
        }
        return "\(name)(\(params.joined(separator: ", "))\(isVariadic ? ", …" : ""))"
    }
}

/// The set of functions a script can call. Start from `.standard` and
/// `register` your own native (Swift) indicators on a copy.
///
/// Marked `@unchecked Sendable` so a finished library can be handed to a
/// background task; don't register functions while it is in use elsewhere.
public final class FunctionLibrary: @unchecked Sendable {
    private var functions: [String: ScriptFunction]

    public init(_ functions: [ScriptFunction] = []) {
        self.functions = [:]
        for function in functions { self.functions[function.name] = function }
    }

    public func register(_ function: ScriptFunction) {
        functions[function.name] = function
    }

    public func unregister(_ name: String) {
        functions[name] = nil
    }

    /// Looks a function up by name. Pine-style `ta.` / `math.` prefixes are accepted.
    public func function(named name: String) -> ScriptFunction? {
        if let f = functions[name] { return f }
        for prefix in ["ta.", "math."] where name.hasPrefix(prefix) {
            return functions[String(name.dropFirst(prefix.count))]
        }
        return nil
    }

    public var all: [ScriptFunction] {
        functions.values.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    public func copy() -> FunctionLibrary {
        FunctionLibrary(Array(functions.values))
    }

    /// Built-in functions plus the native example indicators.
    public static var standard: FunctionLibrary {
        let library = FunctionLibrary(StandardFunctions.all)
        for function in NativeIndicators.all { library.register(function) }
        return library
    }
}

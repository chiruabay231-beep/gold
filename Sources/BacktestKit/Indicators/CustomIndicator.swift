import Foundation

/// A tunable input of an indicator or strategy script (e.g. `length = 14`).
public struct ScriptParameter: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var defaultValue: Double
    public var minValue: Double?
    public var maxValue: Double?
    public var step: Double?

    public init(id: UUID = UUID(), name: String, defaultValue: Double,
                minValue: Double? = nil, maxValue: Double? = nil, step: Double? = nil) {
        self.id = id
        self.name = name
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
    }
}

/// Where a chart draws an indicator.
public enum IndicatorPlacement: String, Codable, CaseIterable, Sendable {
    /// On top of the price chart (moving averages, bands…).
    case overlay
    /// In its own panel below the price (RSI, MACD…).
    case pane
}

/// A user-defined indicator written in the script language. Once added to a
/// library it can be called by `name` from other scripts, with its
/// parameters as positional arguments: `my_osc(20)`.
public struct CustomIndicator: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Function name used in scripts; letters, digits and `_`.
    public var name: String
    public var title: String
    public var summary: String
    public var parameters: [ScriptParameter]
    public var script: String
    public var placement: IndicatorPlacement
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, title: String, summary: String = "",
                parameters: [ScriptParameter] = [], script: String,
                placement: IndicatorPlacement = .overlay, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.title = title
        self.summary = summary
        self.parameters = parameters
        self.script = script
        self.placement = placement
        self.updatedAt = updatedAt
    }

    /// Checks the name and that the script parses.
    public func validate(against library: FunctionLibrary) throws {
        try Self.validateName(name, library: library)
        var seen = Set<String>()
        for parameter in parameters {
            guard Self.isIdentifier(parameter.name) else {
                throw ScriptError("Tên tham số \"\(parameter.name)\" không hợp lệ")
            }
            guard seen.insert(parameter.name).inserted else {
                throw ScriptError("Tham số \"\(parameter.name)\" bị trùng")
            }
        }
        _ = try Parser.parse(script)
    }

    /// Runs the indicator and returns its plotted lines.
    public func compute(context: EvaluationContext, values: [String: Double] = [:]) throws -> [Plot] {
        var bindings: [String: Value] = [:]
        for parameter in parameters {
            bindings[parameter.name] = .scalar(values[parameter.name] ?? parameter.defaultValue)
        }
        let result = try Evaluator.run(script, context: context, bindings: bindings)
        return result.outputs(defaultTitle: title, count: context.count)
    }

    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { ($0.isLetter || $0.isNumber || $0 == "_") && $0.isASCII }
    }

    /// Function names must be identifiers and must not shadow built-ins.
    public static func validateName(_ name: String, library: FunctionLibrary) throws {
        guard isIdentifier(name) else {
            throw ScriptError("Tên hàm \"\(name)\" chỉ được dùng chữ cái không dấu, số và _, không bắt đầu bằng số")
        }
        if Parser.reserved.contains(name) || EvaluationContext.builtinVariables.contains(where: { $0.name == name }) {
            throw ScriptError("\"\(name)\" là tên dành riêng")
        }
        if let existing = library.function(named: name), existing.category != customCategory {
            throw ScriptError("\"\(name)\" trùng với hàm có sẵn")
        }
    }

    public static let customCategory = "Chỉ báo tự tạo"

    /// Wraps the indicator as a callable script function.
    public func asFunction() -> ScriptFunction {
        let indicator = self
        let program = Result { try Parser.parse(indicator.script) }
        let parameters = indicator.parameters.map { FunctionParameter($0.name, .number, default: $0.defaultValue) }
        return ScriptFunction(indicator.name, parameters, category: Self.customCategory,
                              summary: indicator.title + (indicator.summary.isEmpty ? "" : " — " + indicator.summary)) { args in
            let context = args.context
            var bindings: [String: Value] = [:]
            var key = indicator.name
            for (index, parameter) in indicator.parameters.enumerated() {
                let value = args.number(index)
                bindings[parameter.name] = .scalar(value)
                key += ":\(value)"
            }
            if let cached = context.callCache[key] { return cached }
            guard context.depth < EvaluationContext.maxDepth else {
                throw ScriptError("Chỉ báo \"\(indicator.name)\" gọi lồng nhau quá sâu (có thể đang tự gọi chính nó)")
            }
            context.depth += 1
            defer { context.depth -= 1 }
            let parsed: Program
            do {
                parsed = try program.get()
            } catch {
                throw ScriptError("Chỉ báo \"\(indicator.name)\" bị lỗi: \(error.localizedDescription)")
            }
            let result: ScriptResult
            do {
                result = try Evaluator.run(parsed, context: context, bindings: bindings)
            } catch let error as ScriptError {
                throw ScriptError("Trong chỉ báo \"\(indicator.name)\": \(error.localizedDescription)")
            }
            guard let first = result.outputs(defaultTitle: indicator.title, count: context.count).first else {
                throw ScriptError("Chỉ báo \"\(indicator.name)\" không trả về giá trị")
            }
            let value = Value.series(first.values)
            context.callCache[key] = value
            return value
        }
    }
}

public extension FunctionLibrary {
    /// A copy of this library with the given custom indicators callable by name.
    func adding(_ indicators: [CustomIndicator]) -> FunctionLibrary {
        let library = copy()
        for indicator in indicators where CustomIndicator.isIdentifier(indicator.name) {
            if let existing = library.function(named: indicator.name),
               existing.category != CustomIndicator.customCategory {
                continue // never let a custom indicator shadow a built-in
            }
            library.register(indicator.asFunction())
        }
        return library
    }
}

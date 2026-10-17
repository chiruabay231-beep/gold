import Foundation

/// A trading strategy written as one script. The script assigns special
/// variables that the backtest engine reads; everything else is free-form.
///
/// ```
/// fast = ema(close, fast_len)
/// slow = ema(close, slow_len)
/// long_entry  = crossover(fast, slow)
/// long_exit   = crossunder(fast, slow)
/// long_stop   = close - 2 * atr(14)     // optional, price level
/// long_target = close + 3 * atr(14)     // optional, price level
/// plot(fast, "EMA nhanh")
/// plot(slow, "EMA chậm")
/// ```
///
/// Signals are evaluated on the close of a bar and filled at the next bar's
/// open, so a strategy cannot trade on information it would not have had.
public struct StrategyDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var parameters: [ScriptParameter]
    public var script: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, summary: String = "",
                parameters: [ScriptParameter] = [], script: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.summary = summary
        self.parameters = parameters
        self.script = script
        self.updatedAt = updatedAt
    }

    /// Variables the engine understands.
    public static let signalVariables: [(name: String, summary: String)] = [
        ("long_entry", "Điều kiện mở lệnh Mua (BUY)"),
        ("long_exit", "Điều kiện đóng lệnh Mua"),
        ("short_entry", "Điều kiện mở lệnh Bán (SELL)"),
        ("short_exit", "Điều kiện đóng lệnh Bán"),
        ("long_stop", "Giá cắt lỗ cho lệnh Mua (tính tại nến tín hiệu)"),
        ("long_target", "Giá chốt lời cho lệnh Mua"),
        ("short_stop", "Giá cắt lỗ cho lệnh Bán"),
        ("short_target", "Giá chốt lời cho lệnh Bán"),
    ]

    public func signals(context: EvaluationContext, values: [String: Double] = [:]) throws -> StrategySignals {
        var bindings: [String: Value] = [:]
        for parameter in parameters {
            bindings[parameter.name] = .scalar(values[parameter.name] ?? parameter.defaultValue)
        }
        let result = try Evaluator.run(script, context: context, bindings: bindings)
        return try StrategySignals(result: result, count: context.count)
    }

    public func validate() throws {
        let program = try Parser.parse(script)
        let names = Set(program.assignedNames)
        guard names.contains("long_entry") || names.contains("short_entry") else {
            throw ScriptError("Chiến lược cần gán ít nhất một trong long_entry hoặc short_entry")
        }
    }
}

/// The engine's view of a strategy run: one series per signal variable.
public struct StrategySignals {
    public var longEntry: Series?
    public var longExit: Series?
    public var shortEntry: Series?
    public var shortExit: Series?
    public var longStop: Series?
    public var longTarget: Series?
    public var shortStop: Series?
    public var shortTarget: Series?
    public var plots: [Plot]

    public init(longEntry: Series? = nil, longExit: Series? = nil,
                shortEntry: Series? = nil, shortExit: Series? = nil,
                longStop: Series? = nil, longTarget: Series? = nil,
                shortStop: Series? = nil, shortTarget: Series? = nil,
                plots: [Plot] = []) {
        self.longEntry = longEntry
        self.longExit = longExit
        self.shortEntry = shortEntry
        self.shortExit = shortExit
        self.longStop = longStop
        self.longTarget = longTarget
        self.shortStop = shortStop
        self.shortTarget = shortTarget
        self.plots = plots
    }

    init(result: ScriptResult, count: Int) throws {
        func series(_ name: String) -> Series? {
            result.variables[name].map { $0.series(count: count) }
        }
        self.init(longEntry: series("long_entry"), longExit: series("long_exit"),
                  shortEntry: series("short_entry"), shortExit: series("short_exit"),
                  longStop: series("long_stop"), longTarget: series("long_target"),
                  shortStop: series("short_stop"), shortTarget: series("short_target"),
                  plots: result.plots)
        guard longEntry != nil || shortEntry != nil else {
            throw ScriptError("Chiến lược cần gán ít nhất một trong long_entry hoặc short_entry")
        }
    }
}

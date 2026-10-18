import Foundation
import BacktestKit

// Command-line strategy engine for the VPS bot server.
//
// Reads one JSON request on stdin, writes one JSON response on stdout, so the
// server runs exactly the same strategy code as the app's backtests.
//
// Request:
//   {"command": "evaluate",
//    "strategy": <StrategyDefinition as saved by the app>,
//    "sampleStrategy": "EMA Cross + ATR",          instead of "strategy": a built-in sample
//    "indicators": [<CustomIndicator>],            optional
//    "config": <BacktestConfig>,                   optional, the app's backtest settings
//    "parameterValues": {"rr": 2},                 optional
//    "allowLong": true, "allowShort": true, "timeZone": "UTC",   override the config
//    "candles": [[unixSeconds, open, high, low, close, volume], ...],   closed bars only
//    "positions": [<PaperAccount.Position, dates in unix seconds>],      optional
//    "rules": <TradeManagement>}                   optional
// Response:
//   {"ok": true, "signals": [{"kind", "time", "barIndex", "price", "stop", "target"}],
//    "lastBarSignals": [...], "reversals": [{"id", "reason"}], "bars": 500}
//   {"command": "samples"} → {"ok": true, "samples": ["EMA Cross + ATR", ...]}
//   {"ok": false, "error": "..."}

struct Request: Decodable {
    var command: String?
    var strategy: StrategyDefinition?
    var sampleStrategy: String?
    var indicators: [CustomIndicator]?
    var config: BacktestConfig?
    var parameterValues: [String: Double]?
    var allowLong: Bool?
    var allowShort: Bool?
    var timeZone: String?
    var candles: [[Double]]?
    var positions: [PaperAccount.Position]?
    var rules: TradeManagement?
}

enum BotError: Error, CustomStringConvertible {
    case missingStrategy
    var description: String { "Thiếu chiến lược (strategy hoặc sampleStrategy)" }
}

func respond(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{\"ok\":false}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func signalJSON(_ s: LiveSignal) -> [String: Any] {
    var object: [String: Any] = ["kind": s.kind.rawValue, "time": s.time.timeIntervalSince1970,
                                 "barIndex": s.barIndex, "price": s.price]
    if let stop = s.stop { object["stop"] = stop }
    if let target = s.target { object["target"] = target }
    return object
}

let input = FileHandle.standardInput.readDataToEndOfFile()
do {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let request = try decoder.decode(Request.self, from: input)
    if request.command == "samples" {
        respond(["ok": true, "samples": Samples.strategies.map(\.name)])
        exit(0)
    }
    guard let strategy = request.strategy ?? Samples.strategies.first(where: { $0.name == request.sampleStrategy }) else {
        throw BotError.missingStrategy
    }
    let candles = (request.candles ?? []).compactMap { row -> Candle? in
        guard row.count >= 5 else { return nil }
        return Candle(time: Date(timeIntervalSince1970: row[0]), open: row[1], high: row[2], low: row[3],
                      close: row[4], volume: row.count > 5 ? row[5] : 0)
    }
    let library = FunctionLibrary.standard.adding(request.indicators ?? [])
    try strategy.validate()
    if request.command == "validate" {
        respond(["ok": true])
        exit(0)
    }
    var config = request.config ?? BacktestConfig()
    if let allowLong = request.allowLong { config.allowLong = allowLong }
    if let allowShort = request.allowShort { config.allowShort = allowShort }
    if let zone = request.timeZone { config.timeZoneIdentifier = zone }
    let scan = try LiveSignalScanner.scan(strategy: strategy, candles: candles, config: config,
                                          library: library, parameterValues: request.parameterValues ?? [:])
    let last = candles.count - 1
    var reversals: [[String: Any]] = []
    if let rules = request.rules, let price = candles.last?.close {
        for position in request.positions ?? [] {
            if let reason = rules.reversalReason(for: position, closed: candles, price: price) {
                reversals.append(["id": position.id.uuidString, "reason": reason])
            }
        }
    }
    respond(["ok": true,
             "signals": scan.signals.suffix(50).map(signalJSON),
             "lastBarSignals": scan.signals.filter { $0.barIndex == last }.map(signalJSON),
             "reversals": reversals,
             "bars": candles.count])
} catch {
    respond(["ok": false, "error": "\(error)"])
    exit(1)
}

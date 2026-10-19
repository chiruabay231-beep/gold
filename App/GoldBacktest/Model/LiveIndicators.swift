import Foundation
import BacktestKit

/// Which custom indicators (tab Chỉ báo) are drawn on the Live chart.
/// Stored as comma-separated ids so both tabs can share one AppStorage key.
enum LiveIndicators {
    static let storageKey = "live.customIndicators"

    static func ids(_ stored: String) -> Set<UUID> {
        Set(stored.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    static func toggled(_ id: UUID, in stored: String) -> String {
        var set = ids(stored)
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        return set.map(\.uuidString).sorted().joined(separator: ",")
    }
}

/// Re-runs the selected indicators only when a bar is added or the selection
/// or a script changes, not on every price tick.
@MainActor
final class LiveIndicatorCache {
    private var key = ""
    private var cached = IndicatorRenderer()

    func render(_ indicators: [CustomIndicator], candles: [Candle], library: FunctionLibrary,
                timeZone: TimeZone) -> IndicatorRenderer {
        guard !indicators.isEmpty, candles.count > 2 else { return IndicatorRenderer() }
        let newKey = indicators.map { "\($0.id)-\($0.updatedAt.timeIntervalSince1970)" }.joined(separator: ",")
            + "|\(candles.count)|\(candles.first?.time.timeIntervalSince1970 ?? 0)|\(candles.last?.time.timeIntervalSince1970 ?? 0)"
            + "|\(timeZone.identifier)"
        if newKey != key {
            key = newKey
            cached = IndicatorRenderer(indicators: indicators, data: PriceData(candles: candles), library: library,
                                       timeZone: timeZone)
        }
        return cached
    }
}

import Foundation
import BacktestKit

/// Which custom indicators (tab Chỉ báo) are drawn on the Live chart.
/// Stored as comma-separated ids so both tabs can share one AppStorage key.
enum LiveIndicators {
    static let storageKey = "live.customIndicators"
    static let sharkKey = "live.sharkFlow"
    static let sharkMultipleKey = "live.sharkMultiple"
    /// Supply / demand zones of the shark flow (where big players wait to buy or sell).
    static let sharkZonesKey = "live.sharkZones"

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

/// Small results the Live chart needs on every frame (dragging redraws the
/// whole screen): computed again only when their input changes.
@MainActor
final class LiveFrameCache {
    private var emaKey = ""
    private var ema: [Double] = []
    private var colorsJSON: String?
    private var colors: CandleColors?
    private var formatters: [String: DateFormatter] = [:]

    func ema200(_ closes: @autoclosure () -> [Double], candles: [Candle]) -> [Double] {
        let key = "\(candles.count)|\(candles.first?.time.timeIntervalSince1970 ?? 0)|\(candles.last?.close ?? 0)"
        if key != emaKey {
            emaKey = key
            ema = TA.ema(closes(), 200)
        }
        return ema
    }

    private var sharkKey = ""
    private var shark = SharkFlow.Output()

    func sharkFlow(_ candles: [Candle], multiple: Double) -> SharkFlow.Output {
        let key = "\(candles.count)|\(candles.first?.time.timeIntervalSince1970 ?? 0)|\(candles.last?.close ?? 0)|\(candles.last?.volume ?? 0)|\(multiple)"
        if key != sharkKey {
            sharkKey = key
            shark = SharkFlow.compute(candles: candles, config: SharkFlow.Config(sharkMultiple: multiple))
        }
        return shark
    }

    func candleColors(_ json: String) -> CandleColors? {
        if json != colorsJSON {
            colorsJSON = json
            colors = CandleColors.decode(json)
        }
        return colors
    }

    func clock(_ date: Date, zone: String) -> String {
        let formatter = formatters[zone] ?? {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.timeZone = ChartTimeZones.zone(zone)
            formatters[zone] = f
            return f
        }()
        return formatter.string(from: date)
    }
}

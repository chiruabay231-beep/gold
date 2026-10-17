import Foundation
import BacktestKit

/// Metadata of an imported price history. The candles themselves are stored
/// separately (see `AppStore.priceData(for:)`).
struct DatasetInfo: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case csv, binance, sample
    }

    var id: UUID
    var name: String
    var symbol: String
    var source: Source
    var barCount: Int
    var start: Date
    var end: Date
    /// Median bar spacing in seconds.
    var interval: TimeInterval
    var createdAt: Date

    init(id: UUID = UUID(), name: String, symbol: String, source: Source, candles: [Candle]) {
        let data = PriceData(candles: candles)
        self.id = id
        self.name = name
        self.symbol = symbol
        self.source = source
        barCount = candles.count
        start = candles.first?.time ?? Date()
        end = candles.last?.time ?? Date()
        interval = data.medianBarInterval
        createdAt = Date()
    }

    /// "M15", "H1", "D1"…
    var intervalLabel: String {
        Self.label(forInterval: interval)
    }

    static func label(forInterval seconds: TimeInterval) -> String {
        switch seconds {
        case ..<1: return "?"
        case ..<3600: return "M\(Int((seconds / 60).rounded()))"
        case ..<86_400: return "H\(Int((seconds / 3600).rounded()))"
        case ..<604_800: return "D\(Int((seconds / 86_400).rounded()))"
        default: return "W\(Int((seconds / 604_800).rounded()))"
        }
    }

    var sourceLabel: String {
        switch source {
        case .csv: return "CSV"
        case .binance: return "Binance"
        case .sample: return "Mẫu"
        }
    }
}

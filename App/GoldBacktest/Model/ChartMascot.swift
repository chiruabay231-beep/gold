import Foundation
import BacktestKit

/// A mascot standing on the chart at a time and price: the buyer (girl) or the seller (boy).
struct ChartMascot: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case buyer, seller

        var wantsUp: Bool { self == .buyer }
        var title: String { self == .buyer ? "Cô gái phe MUA" : "Chàng trai phe BÁN" }
        /// File name stem of its pictures ("girl-happy.svg").
        var file: String { self == .buyer ? "girl" : "boy" }
    }

    var id = UUID()
    var kind: Kind
    var time: Date
    var price: Double
    /// Width in points.
    var size: Double = 110

    func picture(_ mood: MascotMood) -> String { "\(kind.file)-\(mood.rawValue)" }
}

/// The mascots of each symbol, kept on the device.
enum MascotStore {
    private static func key(_ symbol: String) -> String { "mascots.\(symbol)" }

    static func load(_ symbol: String) -> [ChartMascot] {
        UserDefaults.standard.data(forKey: key(symbol)).flatMap { try? JSONDecoder().decode([ChartMascot].self, from: $0) } ?? []
    }

    static func save(_ list: [ChartMascot], for symbol: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key(symbol))
    }
}

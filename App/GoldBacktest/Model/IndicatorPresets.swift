import Foundation

/// A named copy of an indicator's settings, to switch back to later.
struct IndicatorPreset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var json: String
    var date = Date()
}

/// Presets per indicator, in UserDefaults ("presets.<indicator>").
enum IndicatorPresets {
    private static func key(_ indicator: String) -> String { "presets.\(indicator)" }

    static func all(_ indicator: String) -> [IndicatorPreset] {
        guard let data = UserDefaults.standard.data(forKey: key(indicator)),
              let list = try? JSONDecoder().decode([IndicatorPreset].self, from: data) else { return [] }
        return list
    }

    /// Saves under `name`, replacing a preset with the same name.
    static func save(name: String, json: String, indicator: String) {
        var list = all(indicator).filter { $0.name != name }
        list.insert(IndicatorPreset(name: name, json: json), at: 0)
        store(list, indicator)
    }

    static func delete(_ preset: IndicatorPreset, indicator: String) {
        store(all(indicator).filter { $0.id != preset.id }, indicator)
    }

    private static func store(_ list: [IndicatorPreset], _ indicator: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: key(indicator))
    }
}

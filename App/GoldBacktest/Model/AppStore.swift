import Foundation
import Observation
import BacktestKit

enum AppTab: Hashable {
    case live, trade, indicators, news, backtest
}

/// App-wide state: datasets, custom indicators, strategies and the last
/// backtest settings. Everything is persisted as files in Application Support.
@Observable
final class AppStore {
    var datasets: [DatasetInfo] = []
    var indicators: [CustomIndicator] = []
    var strategies: [StrategyDefinition] = []
    var config = BacktestConfig()
    var lastError: String?
    /// Selected tab, so screens can send the user to another tab.
    var selectedTab: AppTab = .live
    /// Chart drawings per symbol key (e.g. "BINANCE:PAXGUSDT").
    private(set) var drawings: [String: [Drawing]] = [:]

    @ObservationIgnored private var drawingUndo: [String: [[Drawing]]] = [:]

    @ObservationIgnored private var candleCache: [UUID: PriceData] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoldBacktest", isDirectory: true)
        self.directory = base
        try? fileManager.createDirectory(at: candlesDirectory, withIntermediateDirectories: true)
        load()
    }

    /// Functions available to scripts: built-ins, native Swift indicators
    /// and the user's custom indicators.
    var library: FunctionLibrary {
        FunctionLibrary.standard.adding(indicators)
    }

    func saveConfig() {
        save(config, to: "config.json")
    }

    // MARK: - Drawings

    func drawings(for key: String) -> [Drawing] { drawings[key] ?? [] }

    func addDrawing(_ drawing: Drawing, key: String) {
        mutateDrawings(key) { $0.append(drawing) }
    }

    func updateDrawing(_ drawing: Drawing, key: String) {
        mutateDrawings(key) { list in
            if let index = list.firstIndex(where: { $0.id == drawing.id }) { list[index] = drawing }
        }
    }

    func removeDrawing(_ id: UUID, key: String) {
        mutateDrawings(key) { $0.removeAll { $0.id == id } }
    }

    func clearDrawings(key: String) {
        mutateDrawings(key) { $0.removeAll() }
    }

    var canUndoDrawing: Bool { drawingUndo.values.contains { !$0.isEmpty } }

    func undoDrawing(key: String) {
        guard var history = drawingUndo[key], let previous = history.popLast() else { return }
        drawingUndo[key] = history
        drawings[key] = previous
        save(drawings, to: "drawings.json")
    }

    private func mutateDrawings(_ key: String, _ change: (inout [Drawing]) -> Void) {
        var list = drawings[key] ?? []
        drawingUndo[key, default: []].append(list)
        if drawingUndo[key]!.count > 50 { drawingUndo[key]!.removeFirst() }
        change(&list)
        drawings[key] = list
        save(drawings, to: "drawings.json")
    }

    // MARK: - Datasets

    func priceData(for id: UUID) throws -> PriceData {
        if let cached = candleCache[id] { return cached }
        let data = try Data(contentsOf: candleURL(id))
        let price = PriceData(candles: try CandleCodec.decode(data))
        candleCache[id] = price
        return price
    }

    @discardableResult
    func addDataset(name: String, symbol: String, source: DatasetInfo.Source, candles: [Candle]) throws -> DatasetInfo {
        let info = DatasetInfo(name: name, symbol: symbol, source: source, candles: candles)
        try CandleCodec.encode(candles).write(to: candleURL(info.id), options: .atomic)
        candleCache[info.id] = PriceData(candles: candles)
        datasets.insert(info, at: 0)
        saveDatasets()
        return info
    }

    func renameDataset(_ id: UUID, to name: String) {
        guard let index = datasets.firstIndex(where: { $0.id == id }) else { return }
        datasets[index].name = name
        saveDatasets()
    }

    func deleteDataset(_ id: UUID) {
        datasets.removeAll { $0.id == id }
        candleCache[id] = nil
        try? fileManager.removeItem(at: candleURL(id))
        saveDatasets()
    }

    func addSampleDataset() {
        do {
            try addDataset(name: "Dữ liệu mẫu (giả lập H1)", symbol: "SAMPLE", source: .sample,
                           candles: SampleData.candles(count: 3000))
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Indicators

    func upsert(_ indicator: CustomIndicator) {
        var indicator = indicator
        indicator.updatedAt = Date()
        if let index = indicators.firstIndex(where: { $0.id == indicator.id }) {
            indicators[index] = indicator
        } else {
            indicators.append(indicator)
        }
        save(indicators, to: "indicators.json")
    }

    func deleteIndicator(_ id: UUID) {
        indicators.removeAll { $0.id == id }
        save(indicators, to: "indicators.json")
    }

    /// Validates an indicator before saving; returns an error message or nil.
    func validationError(for indicator: CustomIndicator) -> String? {
        if indicator.title.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Hãy đặt tên hiển thị cho chỉ báo."
        }
        if indicators.contains(where: { $0.name == indicator.name && $0.id != indicator.id }) {
            return "Đã có chỉ báo khác tên hàm \"\(indicator.name)\"."
        }
        do {
            try indicator.validate(against: .standard)
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    // MARK: - Strategies

    func upsert(_ strategy: StrategyDefinition) {
        var strategy = strategy
        strategy.updatedAt = Date()
        if let index = strategies.firstIndex(where: { $0.id == strategy.id }) {
            strategies[index] = strategy
        } else {
            strategies.append(strategy)
        }
        save(strategies, to: "strategies.json")
    }

    func deleteStrategy(_ id: UUID) {
        strategies.removeAll { $0.id == id }
        save(strategies, to: "strategies.json")
    }

    func restoreSamples() {
        for sample in Samples.indicators where !indicators.contains(where: { $0.name == sample.name }) {
            indicators.append(sample)
        }
        for sample in Samples.strategies where !strategies.contains(where: { $0.name == sample.name }) {
            strategies.append(sample)
        }
        save(indicators, to: "indicators.json")
        save(strategies, to: "strategies.json")
    }

    // MARK: - Persistence

    private var candlesDirectory: URL { directory.appendingPathComponent("candles", isDirectory: true) }

    private func candleURL(_ id: UUID) -> URL {
        candlesDirectory.appendingPathComponent("\(id.uuidString).bin")
    }

    private func load() {
        let isFirstLaunch = !fileManager.fileExists(atPath: directory.appendingPathComponent("datasets.json").path)
        datasets = read("datasets.json") ?? []
        indicators = read("indicators.json") ?? []
        strategies = read("strategies.json") ?? []
        if let saved: BacktestConfig = read("config.json") { config = saved }
        drawings = read("drawings.json") ?? [:]
        if isFirstLaunch {
            indicators = Samples.indicators
            strategies = Samples.strategies
            save(indicators, to: "indicators.json")
            save(strategies, to: "strategies.json")
            addSampleDataset()
        }
    }

    private func saveDatasets() {
        save(datasets, to: "datasets.json")
    }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            lastError = "Không lưu được \(name): \(error.localizedDescription)"
        }
    }
}

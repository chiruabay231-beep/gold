import SwiftUI
import BacktestKit

/// A symbol in the user's watchlist.
struct WatchItem: Codable, Hashable, Identifiable {
    var source: LiveSource
    var symbol: String

    var id: String { "\(source.rawValue):\(symbol)" }

    static let defaults: [WatchItem] = [
        WatchItem(source: .binanceFutures, symbol: "XAUUSDT"),
        WatchItem(source: .binanceFutures, symbol: "XAGUSDT"),
        WatchItem(source: .binance, symbol: "PAXGUSDT"),
        WatchItem(source: .binance, symbol: "BTCUSDT"),
        WatchItem(source: .binance, symbol: "ETHUSDT"),
    ]

    static func decode(_ json: String) -> [WatchItem] {
        guard let data = json.data(using: .utf8), !json.isEmpty,
              let items = try? JSONDecoder().decode([WatchItem].self, from: data) else { return defaults }
        return items
    }

    static func encode(_ items: [WatchItem]) -> String {
        (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Normalises what the user typed: upper case, OANDA names as "XAU_USD".
    static func clean(_ text: String, source: LiveSource) -> String {
        let letters = text.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        guard source == .oanda else { return letters.replacingOccurrences(of: "_", with: "") }
        if letters.contains("_") { return letters }
        // XAUUSD → XAU_USD, NAS100USD → NAS100_USD
        for quote in ["USD", "EUR", "JPY", "GBP", "AUD", "CAD", "CHF", "NZD"] where letters.hasSuffix(quote) && letters.count > quote.count {
            return "\(letters.dropLast(quote.count))_\(quote)"
        }
        return letters
    }
}

/// Watchlist sheet: tap to open, swipe to delete, drag to reorder, + to add.
struct SymbolPickerView: View {
    let currentID: String
    var onOpen: (WatchItem) -> Void
    var onOandaToken: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("live.watchlist") private var watchlistJSON = ""
    @State private var items: [WatchItem] = []
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            onOpen(item)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LiveView.displayName(item.symbol)).font(.headline).foregroundColor(.primary)
                                    Text(item.source.title).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if item.id == currentID {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                        save()
                    }
                    .onMove { from, to in
                        items.move(fromOffsets: from, toOffset: to)
                        save()
                    }
                } footer: {
                    Text("Vuốt sang trái để xoá, bấm Sửa để kéo sắp xếp, bấm + để thêm mã.")
                }
                Section {
                    Button { showAdd = true } label: { Label("Thêm mã", systemImage: "plus.circle.fill") }
                    Button { onOandaToken() } label: { Label("Token OANDA…", systemImage: "key") }
                    Button("Khôi phục danh sách mặc định") {
                        items = WatchItem.defaults
                        save()
                    }
                }
            }
            .navigationTitle("Danh sách mã")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddSymbolView { item in
                    if !items.contains(item) { items.append(item) }
                    save()
                }
            }
        }
        .onAppear { items = WatchItem.decode(watchlistJSON) }
    }

    private func save() { watchlistJSON = WatchItem.encode(items) }
}

/// Adds a symbol: choose the data source, type a code or tap a suggestion.
struct AddSymbolView: View {
    var onAdd: (WatchItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source = LiveSource.binanceFutures
    @State private var text = ""

    private var suggestions: [String] {
        switch source {
        case .binanceFutures: return ["XAUUSDT", "XAGUSDT", "BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"]
        case .binance: return LiveMarket.popularSymbols
        case .oanda: return OandaClient.instruments
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Nguồn", selection: $source) {
                        Text("Binance Futures (vàng, bạc)").tag(LiveSource.binanceFutures)
                        Text("Binance (crypto)").tag(LiveSource.binance)
                        Text("OANDA (cần token)").tag(LiveSource.oanda)
                    }
                    TextField(source == .oanda ? "VD: XAUUSD, EURUSD" : "VD: XAUUSDT, BTCUSDT", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Thêm \(WatchItem.clean(text, source: source))") { add(text) }
                        .disabled(WatchItem.clean(text, source: source).isEmpty)
                }
                Section("Gợi ý") {
                    ForEach(suggestions, id: \.self) { symbol in
                        Button { add(symbol) } label: {
                            Text(LiveView.displayName(symbol)).foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Thêm mã")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } } }
        }
    }

    private func add(_ symbol: String) {
        let cleaned = WatchItem.clean(symbol, source: source)
        guard !cleaned.isEmpty else { return }
        onAdd(WatchItem(source: source, symbol: cleaned))
        dismiss()
    }
}

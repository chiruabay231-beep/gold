import SwiftUI
import UniformTypeIdentifiers
import BacktestKit

struct DatasetListView: View {
    @Environment(AppStore.self) private var store
    @State private var showingImporter = false
    @State private var showingBinance = false
    @State private var importing = false

    var body: some View {
        List {
            if store.datasets.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có dữ liệu", systemImage: "tray")
                } description: {
                    Text("Nhập file CSV xuất từ MT5/Exness, TradingView, hoặc tải nến từ Binance.")
                } actions: {
                    Button("Nhập CSV") { showingImporter = true }
                    Button("Thêm dữ liệu mẫu") { store.addSampleDataset() }
                }
            }
            ForEach(store.datasets) { dataset in
                NavigationLink(value: dataset.id) {
                    DatasetRow(dataset: dataset)
                }
            }
            .onDelete { offsets in
                for index in offsets { store.deleteDataset(store.datasets[index].id) }
            }
        }
        .navigationTitle("Dữ liệu")
        .navigationDestination(for: UUID.self) { id in
            DatasetDetailView(datasetID: id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingImporter = true } label: {
                        Label("Nhập file CSV", systemImage: "doc.text")
                    }
                    Button { showingBinance = true } label: {
                        Label("Tải từ Binance", systemImage: "arrow.down.circle")
                    }
                    Button { store.addSampleDataset() } label: {
                        Label("Dữ liệu mẫu", systemImage: "wand.and.stars")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .overlay {
            if importing { ProgressView("Đang đọc file…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                store.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingBinance) {
            BinanceDownloadView()
        }
    }

    @MainActor
    private func importFiles(_ urls: [URL]) {
        importing = true
        Task {
            for url in urls {
                let name = url.deletingPathExtension().lastPathComponent
                do {
                    let candles = try await Task.detached(priority: .userInitiated) {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        guard let text = CSVParser.decodeText(data) else { throw CSVParseError.empty }
                        return try CSVParser().parse(text)
                    }.value
                    try store.addDataset(name: name, symbol: Self.guessSymbol(name), source: .csv, candles: candles)
                } catch {
                    store.lastError = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            importing = false
        }
    }

    /// "XAUUSD_H1_2024" → "XAUUSD".
    static func guessSymbol(_ fileName: String) -> String {
        let separators = CharacterSet(charactersIn: "_- .,")
        return fileName.components(separatedBy: separators).first { !$0.isEmpty }?.uppercased() ?? fileName
    }
}

struct DatasetRow: View {
    let dataset: DatasetInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dataset.name).font(.headline)
                Spacer()
                Text(dataset.intervalLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
            Text("\(dataset.symbol) · \(dataset.barCount) nến · \(dataset.sourceLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(Format.shortDate(dataset.start)) → \(Format.shortDate(dataset.end))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

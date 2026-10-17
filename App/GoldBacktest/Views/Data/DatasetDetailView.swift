import SwiftUI
import BacktestKit

struct IndicatorPane: Identifiable {
    var id: UUID
    var title: String
    var lines: [ChartLine]
}

/// Computes chart lines for a set of custom indicators.
struct IndicatorRenderer {
    var overlays: [ChartLine] = []
    var panes: [IndicatorPane] = []
    var errors: [String] = []

    init() {}

    init(indicators: [CustomIndicator], data: PriceData, library: FunctionLibrary, timeZone: TimeZone) {
        let context = EvaluationContext(data: data, library: library, timeZone: timeZone)
        var colorOffset = 0
        for indicator in indicators {
            do {
                let plots = try indicator.compute(context: context)
                let lines = ChartPalette.lines(from: plots, offset: colorOffset)
                colorOffset += plots.count
                switch indicator.placement {
                case .overlay: overlays += lines
                case .pane: panes.append(IndicatorPane(id: indicator.id, title: indicator.title, lines: lines))
                }
            } catch {
                errors.append("\(indicator.title): \(error.localizedDescription)")
            }
        }
    }
}

struct DatasetDetailView: View {
    let datasetID: UUID
    @Environment(AppStore.self) private var store

    @State private var data: PriceData?
    @State private var window = ChartWindow(total: 0)
    @State private var selected: Set<UUID> = []
    @State private var rendered = IndicatorRenderer()
    @State private var name = ""
    @State private var exportURL: URL?
    @State private var loadError: String?

    private var dataset: DatasetInfo? { store.datasets.first { $0.id == datasetID } }

    var body: some View {
        List {
            if let data {
                Section {
                    PriceChartView(data: data, lines: rendered.overlays, range: window.range)
                        .frame(height: 300)
                    ChartLegend(lines: rendered.overlays)
                    ForEach(rendered.panes) { pane in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pane.title).font(.caption.bold())
                            PaneChartView(times: data.time, lines: pane.lines, range: window.range)
                                .frame(height: 110)
                        }
                    }
                    ChartWindowControls(window: $window, total: data.count)
                    ForEach(rendered.errors, id: \.self) { ErrorText(message: $0) }
                }
                Section("Chỉ báo trên biểu đồ") {
                    if store.indicators.isEmpty {
                        Text("Chưa có chỉ báo. Tạo ở tab Chỉ báo.").foregroundStyle(.secondary)
                    }
                    ForEach(store.indicators) { indicator in
                        Toggle(isOn: Binding(
                            get: { selected.contains(indicator.id) },
                            set: { isOn in
                                if isOn { selected.insert(indicator.id) } else { selected.remove(indicator.id) }
                            })) {
                            VStack(alignment: .leading) {
                                Text(indicator.title)
                                Text(indicator.placement == .overlay ? "Trên giá" : "Khung riêng")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if let loadError {
                ErrorText(message: loadError)
            } else {
                ProgressView()
            }

            if let dataset {
                Section("Thông tin") {
                    TextField("Tên", text: $name)
                        .onSubmit { store.renameDataset(datasetID, to: name) }
                    LabeledContent("Mã", value: dataset.symbol)
                    LabeledContent("Khung", value: dataset.intervalLabel)
                    LabeledContent("Số nến", value: "\(dataset.barCount)")
                    LabeledContent("Từ", value: Format.date(dataset.start))
                    LabeledContent("Đến", value: Format.date(dataset.end))
                    if let last = data?.candles.last {
                        LabeledContent("Giá đóng cuối", value: Format.price(last.close))
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Xuất CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle(dataset?.name ?? "Dữ liệu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: selected) { render() }
        .onDisappear {
            if let dataset, name != dataset.name, !name.isEmpty { store.renameDataset(datasetID, to: name) }
        }
    }

    @MainActor
    private func load() async {
        name = dataset?.name ?? ""
        do {
            let loaded = try store.priceData(for: datasetID)
            data = loaded
            window = ChartWindow(total: loaded.count)
            render()
            let fileName = (dataset?.name ?? "data").replacingOccurrences(of: "/", with: "-")
            exportURL = try await Task.detached(priority: .utility) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).csv")
                try CSVParser.export(loaded.candles).write(to: url, atomically: true, encoding: .utf8)
                return url
            }.value
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func render() {
        guard let data else { return }
        let chosen = store.indicators.filter { selected.contains($0.id) }
        rendered = IndicatorRenderer(indicators: chosen, data: data, library: store.library,
                                     timeZone: store.config.timeZone)
    }
}

import SwiftUI
import BacktestKit

struct IndicatorEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var indicator: CustomIndicator
    @State private var previewDataset: UUID?
    @State private var previewData: PriceData?
    @State private var window = ChartWindow(total: 0)
    @State private var rendered = IndicatorRenderer()
    @State private var saveError: String?

    init(indicator: CustomIndicator) {
        _indicator = State(initialValue: indicator)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên hiển thị", text: $indicator.title)
                    LabeledContent("Tên hàm") {
                        TextField("ten_ham", text: $indicator.name)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Mô tả", text: $indicator.summary, axis: .vertical)
                    Picker("Hiển thị", selection: $indicator.placement) {
                        Text("Trên giá").tag(IndicatorPlacement.overlay)
                        Text("Khung riêng").tag(IndicatorPlacement.pane)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ParameterListEditor(parameters: $indicator.parameters)
                } header: {
                    Text("Tham số")
                } footer: {
                    Text("Dùng tên tham số như biến trong script. Khi gọi từ script khác: \(indicator.name)(giá trị, …) theo đúng thứ tự.")
                }

                Section {
                    ScriptEditor(text: $indicator.script)
                } header: {
                    Text("Script")
                } footer: {
                    Text("Kết quả là biểu thức cuối cùng, hoặc mọi đường plot(x, \"tên\"). hline(70) vẽ đường ngang.")
                }

                Section("Xem trước") {
                    DatasetPicker(datasets: store.datasets, selection: $previewDataset)
                    if let data = previewData {
                        if indicator.placement == .overlay {
                            PriceChartView(data: data, lines: rendered.overlays, range: window.range)
                                .frame(height: 240)
                            ChartLegend(lines: rendered.overlays)
                        } else {
                            ForEach(rendered.panes) { pane in
                                PaneChartView(times: data.time, lines: pane.lines, range: window.range)
                                    .frame(height: 160)
                                ChartLegend(lines: pane.lines)
                            }
                        }
                        ChartWindowControls(window: $window, total: data.count)
                    }
                    ForEach(rendered.errors, id: \.self) { ErrorText(message: $0) }
                }

                if let saveError {
                    Section { ErrorText(message: saveError) }
                }
            }
            .navigationTitle(indicator.title.isEmpty ? "Chỉ báo" : indicator.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                }
            }
            .onAppear {
                if previewDataset == nil { previewDataset = store.datasets.first?.id }
            }
            .task(id: previewDataset) { loadPreviewData() }
            .task(id: indicator) {
                // Small debounce so typing stays responsive.
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                renderPreview()
            }
        }
    }

    @MainActor
    private func loadPreviewData() {
        guard let id = previewDataset, let data = try? store.priceData(for: id) else {
            previewData = nil
            return
        }
        previewData = data
        window = ChartWindow(total: data.count)
        renderPreview()
    }

    @MainActor
    private func renderPreview() {
        guard let data = previewData else { return }
        // Other custom indicators are callable; this one is evaluated directly
        // so unsaved edits are previewed.
        let others = store.indicators.filter { $0.id != indicator.id }
        rendered = IndicatorRenderer(indicators: [indicator], data: data,
                                     library: FunctionLibrary.standard.adding(others),
                                     timeZone: store.config.timeZone)
    }

    @MainActor
    private func save() {
        if let message = store.validationError(for: indicator) {
            saveError = message
            return
        }
        store.upsert(indicator)
        dismiss()
    }
}

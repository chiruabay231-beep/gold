import SwiftUI
import BacktestKit

struct StrategyEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var strategy: StrategyDefinition
    @State private var previewDataset: UUID?
    @State private var preview: BacktestMetrics?
    @State private var previewError: String?
    @State private var saveError: String?
    @State private var showingReference = false

    init(strategy: StrategyDefinition) {
        _strategy = State(initialValue: strategy)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên chiến lược", text: $strategy.name)
                    TextField("Mô tả", text: $strategy.summary, axis: .vertical)
                }

                Section {
                    ParameterListEditor(parameters: $strategy.parameters)
                } header: {
                    Text("Tham số")
                } footer: {
                    Text("Tham số có thể chỉnh nhanh khi chạy backtest và dùng cho tối ưu.")
                }

                Section {
                    ScriptEditor(text: $strategy.script, minHeight: 280)
                    Button {
                        showingReference = true
                    } label: {
                        Label("Biến tín hiệu & hàm", systemImage: "book")
                    }
                } header: {
                    Text("Script")
                } footer: {
                    Text("Gán long_entry / short_entry (bắt buộc ít nhất một), long_exit, short_exit và tuỳ chọn long_stop, long_target, short_stop, short_target (giá).")
                }

                Section("Kiểm tra nhanh") {
                    DatasetPicker(datasets: store.datasets, selection: $previewDataset)
                    if let preview {
                        MetricsSummaryRow(metrics: preview)
                    }
                    if let previewError {
                        ErrorText(message: previewError)
                    }
                }

                if let saveError {
                    Section { ErrorText(message: saveError) }
                }
            }
            .navigationTitle(strategy.name.isEmpty ? "Chiến lược" : strategy.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                }
            }
            .sheet(isPresented: $showingReference) {
                NavigationStack { FunctionReferenceView() }
            }
            .onAppear {
                if previewDataset == nil { previewDataset = store.datasets.first?.id }
            }
            .task(id: PreviewKey(strategy: strategy, dataset: previewDataset)) {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                runPreview()
            }
        }
    }

    private struct PreviewKey: Equatable {
        var strategy: StrategyDefinition
        var dataset: UUID?
    }

    @MainActor
    private func runPreview() {
        guard let id = previewDataset, let data = try? store.priceData(for: id) else { return }
        do {
            try strategy.validate()
            let result = try BacktestEngine.run(strategy: strategy, data: data, config: store.config, library: store.library)
            preview = result.metrics
            previewError = result.warnings.first
        } catch {
            preview = nil
            previewError = error.localizedDescription
        }
    }

    @MainActor
    private func save() {
        do {
            guard !strategy.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                saveError = "Hãy đặt tên chiến lược."
                return
            }
            try strategy.validate()
            store.upsert(strategy)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Compact one-line summary of a backtest.
struct MetricsSummaryRow: View {
    let metrics: BacktestMetrics

    var body: some View {
        HStack {
            stat("Lợi nhuận", Format.percent(metrics.netProfitPercent), metrics.netProfit >= 0 ? .green : .red)
            stat("Lệnh", "\(metrics.totalTrades)", .primary)
            stat("Thắng", Format.number(metrics.winRate, digits: 1) + "%", .primary)
            stat("PF", Format.number(metrics.profitFactor), .primary)
            stat("Max DD", Format.number(metrics.maxDrawdownPercent, digits: 1) + "%", .orange)
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

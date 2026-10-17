import SwiftUI
import BacktestKit

struct OptimizerView: View {
    let strategy: StrategyDefinition
    let data: PriceData
    let tradingStart: Int
    let config: BacktestConfig
    let library: FunctionLibrary
    var onApply: ([String: Double]) -> Void

    @Environment(\.dismiss) private var dismiss

    struct RangeInput: Identifiable {
        var id: String { name }
        var name: String
        var enabled: Bool
        var from: Double
        var to: Double
        var step: Double
    }

    @State private var ranges: [RangeInput] = []
    @State private var objective: Optimizer.Objective = .netProfit
    @State private var minTrades = 10
    @State private var running = false
    @State private var progress = 0.0
    @State private var runs: [Optimizer.Run] = []
    @State private var task: Task<Void, Never>?

    private let maxRuns = 2000

    private var combinationCount: Int {
        ranges.filter(\.enabled).reduce(1) { total, range in
            total * Optimizer.Range(name: range.name, from: range.from, to: range.to, step: range.step).values.count
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($ranges) { $range in
                        VStack(alignment: .leading) {
                            Toggle(range.name, isOn: $range.enabled)
                                .font(.body.monospaced())
                            if range.enabled {
                                HStack {
                                    field("Từ", $range.from)
                                    field("Đến", $range.to)
                                    field("Bước", $range.step)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Khoảng tham số")
                } footer: {
                    Text("\(combinationCount) tổ hợp" + (combinationCount > maxRuns ? " — chỉ chạy \(maxRuns) tổ hợp đầu." : ""))
                }

                Section("Mục tiêu") {
                    Picker("Tối ưu theo", selection: $objective) {
                        ForEach(Optimizer.Objective.allCases, id: \.self) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Stepper("Tối thiểu \(minTrades) lệnh", value: $minTrades, in: 1...500)
                }

                Section {
                    if running {
                        ProgressView(value: progress)
                        Button("Dừng", role: .destructive) { task?.cancel() }
                    } else {
                        Button("Chạy tối ưu") { start() }
                            .disabled(combinationCount == 0 || ranges.allSatisfy { !$0.enabled })
                    }
                } footer: {
                    Text("Cẩn thận overfitting: kiểm tra lại bộ tham số tốt nhất trên một khoảng thời gian khác (giới hạn ngày ở màn Backtest).")
                }

                if !runs.isEmpty {
                    Section("Kết quả tốt nhất (\(runs.count))") {
                        ForEach(runs.prefix(50)) { run in
                            Button {
                                onApply(run.values)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.values.sorted { $0.key < $1.key }
                                        .map { "\($0.key)=\(Format.number($0.value, digits: 2))" }
                                        .joined(separator: "  "))
                                        .font(.caption.monospaced())
                                    MetricsSummaryRow(metrics: run.metrics)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Tối ưu tham số")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard ranges.isEmpty else { return }
                ranges = strategy.parameters.map { p in
                    let step = p.step ?? (p.defaultValue == p.defaultValue.rounded() ? 1 : 0.1)
                    let from = p.minValue ?? max(step, p.defaultValue / 2)
                    let to = p.maxValue ?? p.defaultValue * 2
                    // Keep the default grid reasonably small.
                    let coarse = max(step, ((to - from) / 10 / step).rounded(.up) * step)
                    return RangeInput(name: p.name, enabled: true, from: from, to: to, step: coarse)
                }
            }
        }
    }

    private func field(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    @MainActor
    private func start() {
        let selected = ranges.filter(\.enabled).map {
            Optimizer.Range(name: $0.name, from: $0.from, to: $0.to, step: $0.step)
        }
        running = true
        progress = 0
        runs = []
        let strategy = strategy, data = data, config = config, library = library
        let objective = objective, minTrades = minTrades, maxRuns = maxRuns, tradingStart = tradingStart
        task = Task {
            let worker = Task.detached(priority: .userInitiated) {
                Optimizer.run(strategy: strategy, data: data, config: config, library: library,
                              ranges: selected, objective: objective, minTrades: minTrades,
                              maxRuns: maxRuns, tradingStart: tradingStart) { value in
                    Task { @MainActor in progress = value }
                }
            }
            let results = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            runs = results
            running = false
        }
    }
}

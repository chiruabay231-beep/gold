import SwiftUI
import BacktestKit

/// A finished backtest, ready to display.
struct BacktestRun: Identifiable, Hashable {
    let id = UUID()
    let strategy: StrategyDefinition
    let datasetName: String
    let data: PriceData
    let result: BacktestResult
    let parameterValues: [String: Double]

    static func == (lhs: BacktestRun, rhs: BacktestRun) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct BacktestView: View {
    @Environment(AppStore.self) private var store

    @State private var datasetID: UUID?
    @State private var strategyID: UUID?
    @State private var parameterValues: [String: Double] = [:]
    @State private var useDateRange = false
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var running = false
    @State private var error: String?
    @State private var run: BacktestRun?
    @State private var showingOptimizer = false

    struct TimeZoneOption: Identifiable {
        var id: String
        var label: String
    }

    static let timeZones = [
        TimeZoneOption(id: "UTC", label: "UTC"),
        TimeZoneOption(id: "Asia/Ho_Chi_Minh", label: "Việt Nam (UTC+7)"),
        TimeZoneOption(id: "Europe/London", label: "London"),
        TimeZoneOption(id: "America/New_York", label: "New York"),
        TimeZoneOption(id: "Asia/Tokyo", label: "Tokyo"),
    ]

    private var strategy: StrategyDefinition? { store.strategies.first { $0.id == strategyID } }
    private var dataset: DatasetInfo? { store.datasets.first { $0.id == datasetID } }

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Chọn") {
                DatasetPicker(datasets: store.datasets, selection: $datasetID)
                Picker("Chiến lược", selection: $strategyID) {
                    Text("Chọn…").tag(UUID?.none)
                    ForEach(store.strategies) { strategy in
                        Text(strategy.name).tag(Optional(strategy.id))
                    }
                }
            }

            if let strategy, !strategy.parameters.isEmpty {
                Section {
                    ForEach(strategy.parameters) { parameter in
                        LabeledContent(parameter.name) {
                            TextField("", value: Binding(
                                get: { parameterValues[parameter.name] ?? parameter.defaultValue },
                                set: { parameterValues[parameter.name] = $0 }),
                                format: .number)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.body.monospaced())
                    }
                    Button("Về mặc định") { parameterValues = [:] }
                } header: {
                    Text("Tham số chiến lược")
                }
            }

            if let dataset {
                Section("Khoảng thời gian") {
                    Toggle("Giới hạn ngày", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("Từ", selection: $fromDate, in: dataset.start...dataset.end, displayedComponents: .date)
                        DatePicker("Đến", selection: $toDate, in: dataset.start...dataset.end, displayedComponents: .date)
                        Text("Dữ liệu trước ngày bắt đầu vẫn được dùng để tính chỉ báo (warm-up).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Vốn & khối lượng") {
                numberRow("Vốn ban đầu", $store.config.initialCapital)
                Picker("Khối lượng", selection: $store.config.sizingMode) {
                    Text("% vốn").tag(PositionSizingMode.percentOfEquity)
                    Text("Số lượng cố định").tag(PositionSizingMode.fixedQuantity)
                    Text("Số tiền cố định").tag(PositionSizingMode.fixedCash)
                    Text("% rủi ro theo SL").tag(PositionSizingMode.riskPercent)
                }
                numberRow(sizingLabel, $store.config.sizingValue)
            }

            Section {
                numberRow("Phí % mỗi chiều", $store.config.commissionPercent)
                numberRow("Phí cố định mỗi chiều", $store.config.commissionPerTrade)
                numberRow("Trượt giá / spread (giá)", $store.config.slippage)
            } header: {
                Text("Chi phí")
            } footer: {
                Text("XAUUSD: spread 0.2 tương đương 20 point. Trượt giá được cộng vào giá khớp mỗi chiều.")
            }

            Section {
                Toggle("Cho phép Mua", isOn: $store.config.allowLong)
                Toggle("Cho phép Bán", isOn: $store.config.allowShort)
                optionalPercentRow("Cắt lỗ mặc định %", $store.config.stopLossPercent)
                optionalPercentRow("Chốt lời mặc định %", $store.config.takeProfitPercent)
                Picker("Múi giờ", selection: $store.config.timeZoneIdentifier) {
                    ForEach(Self.timeZones) { zone in
                        Text(zone.label).tag(zone.id)
                    }
                }
            } header: {
                Text("Quản lý lệnh")
            } footer: {
                Text("Cắt lỗ/chốt lời mặc định chỉ dùng khi script không gán long_stop / long_target… Múi giờ áp dụng cho hour, session(), vwap, daily_high().")
            }

            if let error {
                Section { ErrorText(message: error) }
            }

            Section {
                Button {
                    runBacktest()
                } label: {
                    HStack {
                        Spacer()
                        if running { ProgressView().padding(.trailing, 6) }
                        Text(running ? "Đang chạy…" : "Chạy backtest").bold()
                        Spacer()
                    }
                }
                .disabled(running || strategy == nil || dataset == nil)

                Button {
                    store.saveConfig()
                    showingOptimizer = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Tối ưu tham số", systemImage: "slider.horizontal.3")
                        Spacer()
                    }
                }
                .disabled(running || strategy?.parameters.isEmpty != false || dataset == nil)
            }
        }
        .navigationTitle("Backtest")
        .toolbar {
            // Strategies no longer have their own tab; they are edited from here.
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { StrategyListView() } label: { Label("Chiến lược", systemImage: "list.bullet.rectangle") }
            }
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { BotView() } label: { Label("Bot", systemImage: "cpu") }
            }
        }
        .navigationDestination(item: $run) { run in
            BacktestResultView(run: run)
        }
        .sheet(isPresented: $showingOptimizer) {
            if let strategy, let dataset, let data = try? store.priceData(for: dataset.id) {
                OptimizerView(strategy: strategy, data: sliced(data).data, tradingStart: sliced(data).start,
                              config: store.config, library: store.library) { values in
                    parameterValues = values
                }
            }
        }
        .onAppear {
            if datasetID == nil { datasetID = store.datasets.first?.id }
            if strategyID == nil { strategyID = store.strategies.first?.id }
        }
        .onChange(of: strategyID) { parameterValues = [:] }
        .onChange(of: datasetID) {
            if let dataset {
                fromDate = dataset.start
                toDate = dataset.end
            }
        }
        .onDisappear { store.saveConfig() }
    }

    private var sizingLabel: String {
        switch store.config.sizingMode {
        case .percentOfEquity: return "% vốn mỗi lệnh"
        case .fixedQuantity: return "Số lượng (VD: 100 oz = 1 lot vàng)"
        case .fixedCash: return "Số tiền mỗi lệnh"
        case .riskPercent: return "% vốn rủi ro mỗi lệnh"
        }
    }

    private func numberRow(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }

    private func optionalPercentRow(_ title: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? (value.wrappedValue ?? 1) : nil }))
            if value.wrappedValue != nil {
                TextField("", value: Binding(
                    get: { value.wrappedValue ?? 0 },
                    set: { value.wrappedValue = $0 }),
                    format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
        }
    }

    /// Data cut at the end date, plus the first bar on or after the start date.
    private func sliced(_ data: PriceData) -> (data: PriceData, start: Int) {
        guard useDateRange else { return (data, 0) }
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: toDate)) ?? toDate
        let end = data.time.firstIndex { $0 >= endOfDay } ?? data.count
        let start = data.time.firstIndex { $0 >= Calendar.current.startOfDay(for: fromDate) } ?? 0
        let cut = end < data.count ? data.slice(0..<max(end, 1)) : data
        return (cut, min(start, max(0, cut.count - 1)))
    }

    @MainActor
    private func runBacktest() {
        guard let strategy, let dataset else { return }
        error = nil
        store.saveConfig()
        let data: PriceData
        do {
            data = try store.priceData(for: dataset.id)
        } catch {
            self.error = error.localizedDescription
            return
        }
        let (input, start) = sliced(data)
        let config = store.config
        let library = store.library
        let values = parameterValues
        running = true
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try BacktestEngine.run(strategy: strategy, data: input, config: config, library: library,
                                           parameterValues: values, tradingStart: start)
                }.value
                run = BacktestRun(strategy: strategy, datasetName: dataset.name, data: input,
                                  result: result, parameterValues: values)
            } catch {
                self.error = error.localizedDescription
            }
            running = false
        }
    }
}

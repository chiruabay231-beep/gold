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

/// Backtest: Exness data (MT5 on the VPS) or a saved file, a strategy, capital,
/// and the rest folded under "Nâng cao".
struct BacktestView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market

    /// "exness" or "file".
    @AppStorage("backtest.source") private var source = "exness"
    @AppStorage("backtest.symbol") private var exnessSymbol = ""
    @AppStorage("backtest.interval") private var exnessInterval = BinanceClient.Interval.m15.rawValue
    @AppStorage("backtest.days") private var exnessDays = 30

    @State private var datasetID: UUID?
    @State private var strategyID: UUID?
    @State private var parameterValues: [String: Double] = [:]
    @State private var useDateRange = false
    @State private var fromDate = Date()
    @State private var toDate = Date()
    @State private var running = false
    /// Bars downloaded so far while loading from Exness.
    @State private var loadedBars: Int?
    @State private var error: String?
    @State private var run: BacktestRun?
    @State private var showingOptimizer = false
    @State private var showSymbols = false
    @State private var showParameters = false
    @State private var showAdvanced = false

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

    static let exnessIntervals: [BinanceClient.Interval] = [.m1, .m5, .m15, .m30, .h1, .h4, .d1]
    static let dayChoices = [7, 14, 30, 60, 90, 180, 365]
    /// The VPS sends at most 5000 bars a request; 60 requests at most.
    static let maxBars = 300_000

    private var strategy: StrategyDefinition? { store.strategies.first { $0.id == strategyID } }
    private var fromExness: Bool { source == "exness" }
    private var interval: BinanceClient.Interval { BinanceClient.Interval(rawValue: exnessInterval) ?? .m15 }

    /// The saved file, or the Exness download already made for these choices.
    private var dataset: DatasetInfo? {
        if fromExness { return store.datasets.first { $0.source == .exness && $0.name == exnessName } }
        return store.datasets.first { $0.id == datasetID }
    }

    private var exnessName: String { "Exness \(exnessSymbol) \(interval.rawValue) \(exnessDays) ngày" }

    var body: some View {
        @Bindable var store = store
        Form {
            dataSection

            Section {
                Picker("Chiến lược", selection: $strategyID) {
                    Text("Chọn…").tag(UUID?.none)
                    ForEach(store.strategies) { strategy in
                        Text(strategy.name).tag(Optional(strategy.id))
                    }
                }
                if let strategy, !strategy.parameters.isEmpty {
                    DisclosureGroup(isExpanded: $showParameters) {
                        ForEach(strategy.parameters) { parameter in
                            LabeledContent(parameter.name) {
                                TextField("", value: Binding(
                                    get: { parameterValues[parameter.name] ?? parameter.defaultValue },
                                    set: { parameterValues[parameter.name] = $0 }),
                                    format: .number)
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.callout.monospaced())
                        }
                        Button("Về mặc định") { parameterValues = [:] }
                    } label: {
                        LabeledContent("Tham số", value: parameterSummary(strategy))
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
                DisclosureGroup("Nâng cao: phí, spread, SL/TP, múi giờ", isExpanded: $showAdvanced) {
                    numberRow("Phí % mỗi chiều", $store.config.commissionPercent)
                    numberRow("Phí cố định mỗi chiều", $store.config.commissionPerTrade)
                    numberRow("Spread / trượt giá", $store.config.slippage)
                    Toggle("Cho phép Mua", isOn: $store.config.allowLong)
                    Toggle("Cho phép Bán", isOn: $store.config.allowShort)
                    optionalPercentRow("Cắt lỗ mặc định %", $store.config.stopLossPercent)
                    optionalPercentRow("Chốt lời mặc định %", $store.config.takeProfitPercent)
                    Picker("Múi giờ", selection: $store.config.timeZoneIdentifier) {
                        ForEach(Self.timeZones) { zone in
                            Text(zone.label).tag(zone.id)
                        }
                    }
                    Text("XAUUSD: spread 0.2 = 20 point. SL/TP mặc định chỉ dùng khi chiến lược không tự đặt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                        if running { ProgressView().tint(.white).padding(.trailing, 6) }
                        Text(runTitle).bold()
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .disabled(running || strategy == nil || !canLoad)
            }
            .listRowBackground(Color.clear)

            Section {
                Button {
                    store.saveConfig()
                    showingOptimizer = true
                } label: {
                    Label("Tối ưu tham số", systemImage: "slider.horizontal.3")
                }
                .disabled(running || strategy?.parameters.isEmpty != false || dataset == nil)
            } footer: {
                if fromExness, dataset == nil {
                    Text("Tối ưu tham số dùng dữ liệu đã tải: chạy backtest một lần trước.")
                }
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
        .sheet(isPresented: $showSymbols) {
            MT5SymbolSearchView { symbol in exnessSymbol = symbol }
        }
        .onAppear {
            if exnessSymbol.isEmpty { exnessSymbol = market.source == .mt5 ? market.symbol : "XAUUSD" }
            if datasetID == nil { datasetID = store.datasets.first { $0.source != .exness }?.id ?? store.datasets.first?.id }
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

    // MARK: - Data

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Picker("Nguồn", selection: $source) {
                Text("Exness").tag("exness")
                Text("File đã nạp").tag("file")
            }
            .pickerStyle(.segmented)
            if fromExness {
                if RemoteBotSettings.client() == nil {
                    Text("Kết nối máy chủ VPS và đăng nhập Exness ở Giao dịch → Đăng nhập.")
                        .font(.footnote).foregroundColor(.orange)
                }
                Button { showSymbols = true } label: {
                    LabeledContent("Mã", value: exnessSymbol.isEmpty ? "Chọn…" : exnessSymbol)
                }
                .foregroundColor(.primary)
                Picker("Khung", selection: $exnessInterval) {
                    ForEach(Self.exnessIntervals, id: \.rawValue) { interval in
                        Text(interval.rawValue).tag(interval.rawValue)
                    }
                }
                Picker("Thời gian", selection: $exnessDays) {
                    ForEach(Self.dayChoices, id: \.self) { days in Text("\(days) ngày gần nhất").tag(days) }
                }
            } else {
                DatasetPicker(datasets: store.datasets, selection: $datasetID)
                if let dataset {
                    Toggle("Giới hạn ngày", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("Từ", selection: $fromDate, in: dataset.start...dataset.end, displayedComponents: .date)
                        DatePicker("Đến", selection: $toDate, in: dataset.start...dataset.end, displayedComponents: .date)
                    }
                }
                NavigationLink { DatasetListView() } label: {
                    Label("Nạp / quản lý file dữ liệu", systemImage: "tray.and.arrow.down")
                }
            }
        } header: {
            Text("Dữ liệu")
        } footer: {
            if let loadedBars {
                Text("Đang tải từ Exness… \(loadedBars.formatted()) nến")
            } else if let dataset {
                Text("\(dataset.barCount.formatted()) nến · \(dataset.start.formatted(date: .abbreviated, time: .omitted)) – \(dataset.end.formatted(date: .abbreviated, time: .omitted))"
                     + (fromExness ? " · tải lúc \(dataset.createdAt.formatted(date: .omitted, time: .shortened))" : ""))
            } else if fromExness {
                Text("Nến lấy thẳng từ tài khoản Exness trên VPS khi bấm Chạy backtest.")
            }
        }
    }

    private var canLoad: Bool {
        fromExness ? RemoteBotSettings.client() != nil && !exnessSymbol.isEmpty : dataset != nil
    }

    private var runTitle: String {
        if running { return loadedBars == nil ? "Đang chạy…" : "Đang tải dữ liệu…" }
        return "Chạy backtest"
    }

    private func parameterSummary(_ strategy: StrategyDefinition) -> String {
        strategy.parameters.prefix(4).map { p in
            let value = parameterValues[p.name] ?? p.defaultValue
            return value.formatted()
        }.joined(separator: " · ")
    }

    /// Exness bars for the chosen symbol, timeframe and days, newest download
    /// reused for 10 minutes; older pages fetched back to the start date.
    @MainActor
    private func exnessDataset() async throws -> DatasetInfo {
        if let dataset, Date().timeIntervalSince(dataset.createdAt) < 600 { return dataset }
        guard let client = RemoteBotSettings.client() else {
            throw RemoteBotClient.ServerError(message: "Chưa kết nối máy chủ VPS.")
        }
        let symbol = exnessSymbol, interval = interval, name = exnessName
        let startDate = Date().addingTimeInterval(-Double(exnessDays) * 86_400)
        loadedBars = 0
        defer { loadedBars = nil }
        // The newest bar is still forming: left out.
        var bars = Array(try await client.mt5Candles(symbol: symbol, interval: interval, count: 5000).dropLast())
        loadedBars = bars.count
        while let first = bars.first, first.time > startDate, bars.count < Self.maxBars {
            let older = try await client.mt5Candles(symbol: symbol, interval: interval, count: 5000, before: first.time)
            guard !older.isEmpty else { break }
            bars = older + bars
            loadedBars = bars.count
        }
        bars.removeAll { $0.time < startDate }
        guard bars.count > 50 else {
            throw RemoteBotClient.ServerError(message: "Exness chỉ trả \(bars.count) nến \(symbol) \(interval.rawValue): chọn khung lớn hơn hoặc nhiều ngày hơn.")
        }
        for old in store.datasets where old.source == .exness && old.name == name { store.deleteDataset(old.id) }
        return try store.addDataset(name: name, symbol: symbol, source: .exness, candles: bars)
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
        guard useDateRange, !fromExness else { return (data, 0) }
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: toDate)) ?? toDate
        let end = data.time.firstIndex { $0 >= endOfDay } ?? data.count
        let start = data.time.firstIndex { $0 >= Calendar.current.startOfDay(for: fromDate) } ?? 0
        let cut = end < data.count ? data.slice(0..<max(end, 1)) : data
        return (cut, min(start, max(0, cut.count - 1)))
    }

    @MainActor
    private func runBacktest() {
        guard let strategy else { return }
        error = nil
        store.saveConfig()
        let config = store.config
        let library = store.library
        let values = parameterValues
        running = true
        Task {
            do {
                let picked: DatasetInfo?
                if fromExness { picked = try await exnessDataset() } else { picked = dataset }
                guard let dataset = picked else {
                    running = false
                    return
                }
                let (input, start) = sliced(try store.priceData(for: dataset.id))
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

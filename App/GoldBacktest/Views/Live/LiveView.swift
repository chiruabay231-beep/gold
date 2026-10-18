import SwiftUI
import UIKit
import BacktestKit

/// Live chart laid out like TradingView's mobile app: symbol header with a
/// layer legend, chart with drawing tools and ICT layers, bottom tool bar.
struct LiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market
    @Environment(PaperTrader.self) private var trader
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("live.theme") private var themeName = "tradingView"
    @AppStorage("live.showMA") private var showMA = false
    @AppStorage("live.showStrategyPlots") private var showStrategyPlots = true
    @AppStorage("live.killzonePivots.on") private var showKillzonePivots = true
    @AppStorage(KillzonePivotsSettings.storageKey) private var killzonePivotsJSON = ""
    @AppStorage("live.volume") private var showVolume = true
    @AppStorage("live.highLow") private var showHighLow = true
    @AppStorage("live.candleStyle") private var candleStyle = CandleStyle.candles.rawValue
    @AppStorage("live.magnet") private var magnet = true
    @AppStorage("live.keepTool") private var keepTool = false
    @AppStorage("live.hideDrawings") private var hideDrawings = false
    @AppStorage("live.lockDrawings") private var lockDrawings = false
    @AppStorage("live.candleColors") private var candleColorsJSON = ""
    @AppStorage("live.precision") private var precision = -1
    @AppStorage("live.timeZone") private var timeZoneID = ""
    @AppStorage("position.balance") private var accountBalance = 0.0
    @AppStorage("position.riskPercent") private var riskPercent = 1.0
    @AppStorage("position.contractSize") private var contractSize = 100.0
    @State private var showChartSettings = false
    @State private var showTradePanel = false
    @State private var showVoiceSettings = false
    /// Position drawing waiting for confirmation before it becomes a demo order.
    @State private var demoOrderDrawing: Drawing?
    @AppStorage("trade.lots") private var defaultLots = 0.01
    @AppStorage(VoiceSettings.backgroundKey) private var runInBackground = false
    @AppStorage(VoiceSettings.keepAwakeKey) private var keepAwake = false
    @State private var settingsDrawing: Drawing?

    @State private var viewport = ChartViewport()
    @State private var customSymbol = ""
    @State private var askingSymbol = false
    @State private var showDrawingBar = false
    @State private var activeTool: DrawingTool?
    @State private var selectedDrawingID: UUID?
    @State private var editingTextDrawing: Drawing?
    @State private var drawingText = ""
    @State private var legendExpanded = true
    @State private var fullScreen = false
    @State private var confirmClear = false
    @State private var killzoneCache = KillzonePivotsCache()
    @State private var showKillzoneSettings = false
    @State private var showOandaSettings = false
    /// OANDA instrument to open once a token has been saved.
    @State private var pendingOandaInstrument: String?

    private var theme: ChartTheme { themeName == "binance" ? .binance : .tradingView }
    private var drawingKey: String { "\(market.source.rawValue):\(market.symbol)" }
    private var drawings: [Drawing] { store.drawings(for: drawingKey) }

    var body: some View {
        VStack(spacing: 0) {
            header
            chartPanel
            latestSignalBar
            bottomBar
        }
        .background(theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            market.start(store: store)
            if market.strategyID == nil {
                market.track(strategy: store.strategies.first { $0.name.hasPrefix("ICT Silver") }?.id ?? store.strategies.first?.id)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                BackgroundAudio.shared.stop()
                market.start(store: store)
            case .inactive:
                // Start before iOS suspends the app, while audio may still begin.
                if runInBackground { BackgroundAudio.shared.start() }
            case .background:
                if runInBackground { BackgroundAudio.shared.start() } else { market.stop() }
            @unknown default:
                break
            }
        }
        .onChange(of: keepAwake) { _, value in UIApplication.shared.isIdleTimerDisabled = value }
        .sheet(isPresented: $showTradePanel) { TradePanelView() }
        .sheet(isPresented: $showVoiceSettings) { VoiceSettingsView() }
        .confirmationDialog(demoOrderTitle, isPresented: Binding(get: { demoOrderDrawing != nil },
                                                                 set: { if !$0 { demoOrderDrawing = nil } }),
                            titleVisibility: .visible) {
            if let drawing = demoOrderDrawing, let levels = drawing.positionLevels {
                Button("Lệnh chờ tại \(CandleChart.format(levels.entry, currentDecimals))") { placeDemoOrder(drawing, market: false) }
                Button("Vào ngay giá \(CandleChart.format(currentPrice, currentDecimals))") { placeDemoOrder(drawing, market: true) }
            }
            Button("Huỷ", role: .cancel) { demoOrderDrawing = nil }
        }
        .alert("Nhập mã Binance", isPresented: $askingSymbol) {
            TextField("VD: ADAUSDT", text: $customSymbol)
                .textInputAutocapitalization(.characters)
            Button("Huỷ", role: .cancel) {}
            Button("Mở") { open(symbol: customSymbol) }
        }
        .alert("Nhãn / ghi chú", isPresented: Binding(get: { editingTextDrawing != nil },
                                                      set: { if !$0 { editingTextDrawing = nil } })) {
            TextField("VD: Vùng OB H4", text: $drawingText)
            Button("Huỷ", role: .cancel) { editingTextDrawing = nil }
            Button("Lưu") { saveText() }
        }
        .confirmationDialog("Xoá tất cả hình vẽ của \(Self.displayName(market.symbol))?", isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Xoá tất cả", role: .destructive) {
                store.clearDrawings(key: drawingKey)
                selectedDrawingID = nil
            }
        }
        .sheet(isPresented: $showOandaSettings, onDismiss: { pendingOandaInstrument = nil }) {
            OandaSettingsView {
                if let instrument = pendingOandaInstrument {
                    open(oanda: instrument)
                } else if market.source == .oanda {
                    market.restart()
                }
                pendingOandaInstrument = nil
            }
        }
        .sheet(isPresented: $showKillzoneSettings) {
            KillzonePivotsSettingsView(json: $killzonePivotsJSON)
        }
        .sheet(isPresented: $showChartSettings) {
            ChartSettingsView(theme: theme, colorsJSON: $candleColorsJSON, candleStyle: $candleStyle,
                              precision: $precision, timeZoneID: $timeZoneID, balance: $accountBalance,
                              riskPercent: $riskPercent, contractSize: $contractSize)
        }
        .sheet(item: $settingsDrawing) { drawing in
            DrawingSettingsView(drawing: drawing, decimals: priceDecimals ?? CandleChart.decimals(for: market.candles.last?.close ?? 1),
                                sizing: positionSizing) { changed in
                store.updateDrawing(changed, key: drawingKey)
            }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            FullScreenChart(title: "\(Self.displayName(market.symbol)) · \(Self.label(market.interval))", theme: theme,
                            onClose: { fullScreen = false }) {
                chartPanel
            }
        }
    }

    // MARK: - Header (TradingView style)

    private var header: some View {
        let last = market.ticker?.lastPrice ?? market.candles.last?.close ?? 0
        let changePct = market.ticker?.changePercent ?? 0
        let changeAbs = last - last / (1 + changePct / 100)
        let decimals = priceDecimals ?? CandleChart.decimals(for: last)
        let changeColor = changePct >= 0 ? theme.up : theme.down
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: [BinanceTheme.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22)
                    .overlay(Text(String(market.symbol.prefix(1))).font(.system(size: 11, weight: .bold)).foregroundColor(.white))
                Text(Self.displayName(market.symbol))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                Text(market.source.title)
                    .font(.system(size: 12))
                    .foregroundColor(theme.text)
                statusDot
                Spacer()
            }
            HStack(spacing: 8) {
                Text(CandleChart.format(last, decimals))
                    .foregroundColor(theme.primaryText)
                    .contentTransition(.numericText())
                Text(String(format: "%+.\(decimals)f (%+.2f%%)", changeAbs, changePct))
                    .foregroundColor(changeColor)
                if let profit = demoProfit {
                    Text(String(format: "Demo %+.2f$", profit))
                        .foregroundColor(profit >= 0 ? theme.up : theme.down)
                        .onTapGesture { showTradePanel = true }
                }
                if market.needsOandaToken {
                    Button("Nhập token OANDA") { showOandaSettings = true }
                        .foregroundColor(theme.accent)
                } else if case .reconnecting(let reason) = market.status {
                    Text(reason).foregroundColor(theme.down).lineLimit(1)
                }
            }
            .font(.system(size: 14).monospacedDigit())
            legend
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var statusDot: some View {
        Circle()
            .fill(market.status == .live ? theme.up : (market.status == .loading ? BinanceTheme.yellow : theme.down))
            .frame(width: 7, height: 7)
    }

    private var activeLayerNames: [String] {
        var names: [String] = []
        if showKillzonePivots { names.append(Self.killzonePivotsName) }
        if showMA { names.append("MA 7 / 25 / 99") }
        if showStrategyPlots, let strategy = store.strategies.first(where: { $0.id == market.strategyID }) {
            names.append(strategy.name)
        }
        return names
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            if legendExpanded {
                ForEach(activeLayerNames, id: \.self) { name in
                    if name == Self.killzonePivotsName {
                        // Tap the name to open its settings, like TradingView's legend.
                        Button { showKillzoneSettings = true } label: {
                            HStack(spacing: 6) {
                                Text(name)
                                Image(systemName: "gearshape").font(.system(size: 10))
                                if killzoneLayer.output.hiddenByTimeframe {
                                    Text("· ẩn trên khung này").foregroundColor(theme.text)
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundColor(theme.primaryText)
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(name)
                            .font(.system(size: 12))
                            .foregroundColor(theme.primaryText)
                            .lineLimit(1)
                    }
                }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { legendExpanded.toggle() }
            } label: {
                Image(systemName: legendExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.text)
                    .frame(width: 30, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.grid, lineWidth: 1))
            }
        }
    }

    // MARK: - Chart

    static let killzonePivotsName = "ICT Killzones + Pivots [TFO]"

    private var killzoneSettings: KillzonePivotsSettings { killzoneCache.settings(json: killzonePivotsJSON) }

    private var killzoneLayer: KillzonePivotsLayer {
        killzoneCache.layer(candles: market.candles, barInterval: market.interval.seconds,
                            settings: killzoneSettings, enabled: showKillzonePivots)
    }

    private var chartPanel: some View {
        let settings = killzoneSettings
        let layer = killzoneCache.layer(candles: market.candles, barInterval: market.interval.seconds,
                                        settings: settings, enabled: showKillzonePivots)
        return ZStack(alignment: .trailing) {
            CandleChart(candles: market.candles,
                        overlays: overlays,
                        markers: markers,
                        showVolume: showVolume,
                        countdownInterval: market.interval.seconds,
                        theme: theme,
                        sessionBoxes: layer.boxes,
                        segments: layer.segments + tradeSegments,
                        verticalLines: layer.verticalLines,
                        notes: layer.notes,
                        showHighLowLabels: showHighLow,
                        drawings: hideDrawings ? [] : drawings,
                        drawingTool: activeTool,
                        selectedDrawingID: selectedDrawingID,
                        onDrawingCreated: { drawing in drawingCreated(drawing) },
                        onDrawingChanged: { drawing in store.updateDrawing(drawing, key: drawingKey) },
                        onSelectDrawing: { id in selectedDrawingID = id },
                        candleStyle: CandleStyle(rawValue: candleStyle) ?? .candles,
                        magnet: magnet,
                        candleColors: CandleColors.decode(candleColorsJSON),
                        priceDecimals: priceDecimals,
                        timeZone: ChartTimeZones.zone(timeZoneID),
                        drawingsLocked: lockDrawings,
                        positionSizing: positionSizing,
                        viewport: $viewport)
        }
        .overlay(alignment: .leading) {
            if showDrawingBar {
                DrawingToolbar(activeTool: $activeTool, magnet: $magnet, keepTool: $keepTool,
                               lockAll: $lockDrawings, hideDrawings: $hideDrawings, theme: theme,
                               onUndo: {
                                   store.undoDrawing(key: drawingKey)
                                   selectedDrawingID = nil
                               },
                               onRemoveAll: { confirmClear = true }) {
                    showDrawingBar = false
                    activeTool = nil
                }
                .padding(.leading, 6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showKillzonePivots, settings.config.showRangeTable {
                KillzoneRangeTable(layer: layer, settings: settings,
                                   decimals: priceDecimals ?? CandleChart.decimals(for: market.candles.last?.close ?? 1),
                                   theme: theme)
                    .padding(.trailing, 72)
                    .padding(.top, 40)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let tool = activeTool {
                    Text("\(tool.title): \(tool.hint)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.accent, in: Capsule())
                }
                if let drawing = selectedDrawing {
                    DrawingActionsBar(drawing: drawing, theme: theme,
                                      onChange: { changed in store.updateDrawing(changed, key: drawingKey) },
                                      onEditText: {
                                          drawingText = drawing.text
                                          editingTextDrawing = drawing
                                      },
                                      onClone: {
                                          let copy = drawing.cloned(shift: market.interval.seconds * 5)
                                          store.addDrawing(copy, key: drawingKey)
                                          selectedDrawingID = copy.id
                                      },
                                      onSettings: { settingsDrawing = drawing },
                                      onDelete: {
                                          store.removeDrawing(drawing.id, key: drawingKey)
                                          selectedDrawingID = nil
                                      },
                                      onPlaceOrder: { demoOrderDrawing = drawing })
                }
            }
            .padding(.top, 8)
        }
    }

    private var priceDecimals: Int? { precision >= 0 ? precision : nil }

    // MARK: - Demo trading

    private var currentPrice: Double { market.ticker?.lastPrice ?? market.candles.last?.close ?? 0 }
    private var currentDecimals: Int { priceDecimals ?? CandleChart.decimals(for: currentPrice) }

    /// Open profit of demo positions on the symbol on screen.
    private var demoProfit: Double? {
        let positions = trader.account.positions.filter { $0.symbol == market.symbolKey }
        guard !positions.isEmpty, let price = trader.price(market.symbolKey) else { return nil }
        return positions.reduce(0) { $0 + $1.profit(at: price) }
    }

    private var demoOrderTitle: String {
        guard let drawing = demoOrderDrawing, let levels = drawing.positionLevels else { return "" }
        let side = drawing.tool == .longPosition ? "MUA" : "BÁN"
        return "\(side) \(PaperTrader.lots(demoLots(for: drawing))) lot · SL \(CandleChart.format(levels.stop, currentDecimals)) · TP \(CandleChart.format(levels.target, currentDecimals))"
    }

    private func demoLots(for drawing: Drawing) -> Double {
        guard let levels = drawing.positionLevels,
              let lots = positionSizing?.lots(entry: levels.entry, stop: levels.stop) else { return defaultLots }
        return max(0.01, (lots * 100).rounded(.down) / 100)
    }

    private func placeDemoOrder(_ drawing: Drawing, market useMarket: Bool) {
        guard let levels = drawing.positionLevels, currentPrice > 0 else { return }
        let side: PaperAccount.Side = drawing.tool == .longPosition ? .long : .short
        let lots = demoLots(for: drawing)
        if useMarket {
            if side == .long {
                trader.buy(symbol: market.symbolKey, lots: lots, price: currentPrice, stop: levels.stop, target: levels.target)
            } else {
                trader.sell(symbol: market.symbolKey, lots: lots, price: currentPrice, stop: levels.stop, target: levels.target)
            }
        } else {
            trader.placePending(symbol: market.symbolKey, side: side, lots: lots, entry: levels.entry, stop: levels.stop,
                                target: levels.target, currentPrice: currentPrice)
        }
        demoOrderDrawing = nil
    }

    /// Entry, stop and target lines of demo orders on this symbol.
    private var tradeSegments: [ChartSegment] {
        let key = market.symbolKey
        let candles = market.candles
        guard !candles.isEmpty else { return [] }
        func start(_ time: Date) -> Double { Double(candles.lastIndex { $0.time <= time } ?? 0) }
        var result: [ChartSegment] = []
        func addLevels(from: Double, stop: Double?, target: Double?) {
            if let stop { result.append(ChartSegment(start: from, end: nil, price: stop, color: theme.down, dash: [5, 3], label: "SL")) }
            if let target { result.append(ChartSegment(start: from, end: nil, price: target, color: theme.up, dash: [5, 3], label: "TP")) }
        }
        for p in trader.account.positions where p.symbol == key {
            let from = start(p.openTime)
            let profit = trader.price(key).map { p.profit(at: $0) } ?? 0
            let label = "\(p.side == .long ? "BUY" : "SELL") \(PaperTrader.lots(p.lots))  \(String(format: "%+.2f$", profit))"
            result.append(ChartSegment(start: from, end: nil, price: p.entryPrice, color: theme.accent, width: 1.5, label: label))
            addLevels(from: from, stop: p.stop, target: p.target)
        }
        for o in trader.account.pending where o.symbol == key {
            let from = start(o.createdAt)
            let label = "\(o.side == .long ? "BUY" : "SELL") \(o.triggersAbove == (o.side == .long) ? "STOP" : "LIMIT") \(PaperTrader.lots(o.lots))"
            result.append(ChartSegment(start: from, end: nil, price: o.entry, color: theme.accent, dash: [2, 3], label: label))
            addLevels(from: from, stop: o.stop, target: o.target)
        }
        return result
    }

    private var positionSizing: PositionSizing? {
        accountBalance > 0 ? PositionSizing(balance: accountBalance, riskPercent: riskPercent, contractSize: contractSize) : nil
    }

    private var selectedDrawing: Drawing? {
        guard let id = selectedDrawingID else { return nil }
        return drawings.first { $0.id == id }
    }

    private func drawingCreated(_ drawing: Drawing) {
        if drawing.tool == .text {
            drawingText = ""
            editingTextDrawing = drawing
        } else {
            store.addDrawing(drawing, key: drawingKey)
            selectedDrawingID = keepTool ? nil : drawing.id
        }
        if !keepTool || drawing.tool == .text { activeTool = nil }
        hideDrawings = false
    }

    private var overlays: [ChartLine] {
        var lines: [ChartLine] = []
        if showMA {
            let closes = market.candles.map { $0.close }
            for (index, length) in [7, 25, 99].enumerated() {
                lines.append(ChartLine(title: "MA(\(length))", values: TA.sma(closes, length),
                                       color: BinanceTheme.maColors[index]))
            }
        }
        if showStrategyPlots {
            lines += ChartPalette.lines(from: market.plots, offset: 3)
        }
        return lines
    }

    private var markers: [ChartMarker] {
        market.signals.compactMap { signal in
            switch signal.kind {
            case .longEntry: return ChartMarker(index: signal.barIndex, price: signal.price, kind: .buy)
            case .shortEntry: return ChartMarker(index: signal.barIndex, price: signal.price, kind: .sell)
            case .longExit, .shortExit: return nil
            }
        }
    }

    // MARK: - Latest signal

    /// One line with the newest signal; the full list and the strategy
    /// picker live in the Data tab.
    private var latestSignalBar: some View {
        let strategy = store.strategies.first { $0.id == market.strategyID }
        let latest = market.signals.last
        return Button {
            store.selectedTab = .data
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill").foregroundColor(BinanceTheme.yellow)
                if let strategy {
                    Text(strategy.name)
                        .foregroundColor(theme.text)
                        .lineLimit(1)
                    if let error = market.strategyError {
                        Text(error).foregroundColor(theme.down).lineLimit(1)
                    } else if let latest {
                        Text(latest.kind.label)
                            .fontWeight(.bold)
                            .foregroundColor(LiveSignalRow.color(for: latest.kind))
                        Text(CandleChart.format(latest.price, CandleChart.decimals(for: latest.price)))
                            .foregroundColor(theme.primaryText)
                        Text(latest.time.formatted(.dateTime.hour().minute()))
                            .foregroundColor(theme.text)
                    } else {
                        Text("Chưa có tín hiệu").foregroundColor(theme.text)
                    }
                } else {
                    Text("Chọn chiến lược để nhận tín hiệu").foregroundColor(theme.text)
                }
                Spacer(minLength: 4)
                Image(systemName: market.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .foregroundColor(theme.text)
                Image(systemName: "chevron.right")
                    .foregroundColor(theme.text)
            }
            .font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(theme.panel)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom tool bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            symbolMenu
            intervalMenu
            Spacer(minLength: 4)
            toolbarButton("pencil.tip", active: showDrawingBar) {
                showDrawingBar.toggle()
                if !showDrawingBar { activeTool = nil }
            }
            indicatorMenu
            moreMenu
            toolbarButton("briefcase", active: !trader.account.positions.isEmpty) {
                showTradePanel = true
            }
            toolbarButton("arrow.up.left.and.arrow.down.right", active: false) {
                fullScreen = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.background)
        .overlay(alignment: .top) { Rectangle().fill(theme.grid).frame(height: 1) }
    }

    private var symbolMenu: some View {
        Menu {
            Section("Binance Futures · Vàng, Bạc (miễn phí)") {
                ForEach(LiveMarket.futuresSymbols, id: \.self) { symbol in
                    Button(Self.displayName(symbol)) { open(symbol: symbol, source: .binanceFutures) }
                }
            }
            Section("OANDA · Vàng, Forex, chỉ số") {
                ForEach(OandaClient.instruments, id: \.self) { instrument in
                    Button(Self.displayName(instrument)) { open(oanda: instrument) }
                }
                Button {
                    pendingOandaInstrument = nil
                    showOandaSettings = true
                } label: {
                    Label("Token OANDA…", systemImage: "key")
                }
            }
            Section("Binance · Crypto") {
                ForEach(LiveMarket.popularSymbols, id: \.self) { symbol in
                    Button(Self.displayName(symbol)) { open(symbol: symbol) }
                }
                Button("Nhập mã khác…") {
                    customSymbol = ""
                    askingSymbol = true
                }
            }
        } label: {
            Text(market.symbol.replacingOccurrences(of: "_", with: ""))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 110, alignment: .leading)
        }
    }

    private var intervalMenu: some View {
        Menu {
            ForEach(LiveMarket.intervals, id: \.self) { interval in
                Button {
                    viewport = ChartViewport()
                    market.select(interval: interval)
                } label: {
                    if interval == market.interval {
                        Label(Self.label(interval), systemImage: "checkmark")
                    } else {
                        Text(Self.label(interval))
                    }
                }
            }
        } label: {
            Text(Self.label(market.interval))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(theme.primaryText)
                .frame(width: 44)
        }
    }

    private var indicatorMenu: some View {
        Menu {
            Section("ICT") {
                Toggle(Self.killzonePivotsName, isOn: $showKillzonePivots)
                Button {
                    showKillzoneSettings = true
                } label: {
                    Label("Cài đặt Killzones + Pivots…", systemImage: "gearshape")
                }
            }
            Section("Khác") {
                Toggle("MA 7 / 25 / 99", isOn: $showMA)
                Toggle("Đường của chiến lược", isOn: $showStrategyPlots)
                Toggle("Khối lượng", isOn: $showVolume)
                Toggle("Nhãn Cao / Thấp", isOn: $showHighLow)
            }
        } label: {
            toolbarIcon("function", active: false)
        }
    }

    private var moreMenu: some View {
        Menu {
            Picker("Giao diện", selection: $themeName) {
                Text("TradingView (sáng)").tag("tradingView")
                Text("Binance (tối)").tag("binance")
            }
            Picker("Kiểu nến", selection: $candleStyle) {
                ForEach(CandleStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
            Button {
                showChartSettings = true
            } label: {
                Label("Cài đặt biểu đồ (màu nến…)", systemImage: "gearshape")
            }
            Button {
                showTradePanel = true
            } label: {
                Label("Giao dịch demo…", systemImage: "briefcase")
            }
            Button {
                showVoiceSettings = true
            } label: {
                Label("Cảnh báo giọng nói…", systemImage: "speaker.wave.2")
            }
            Button {
                viewport.manualPriceRange = nil
            } label: {
                Label("Tự động căn thang giá", systemImage: "arrow.up.and.down")
            }
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("Xoá tất cả hình vẽ", systemImage: "trash")
            }
        } label: {
            toolbarIcon("ellipsis", active: false)
        }
    }

    private func toolbarIcon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .regular))
            .foregroundColor(active ? theme.accent : theme.primaryText)
            .frame(width: 42, height: 36)
    }

    private func toolbarButton(_ systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolbarIcon(systemName, active: active) }
    }

    // MARK: - Helpers

    private func saveText() {
        guard var drawing = editingTextDrawing else { return }
        drawing.text = drawingText
        if store.drawings(for: drawingKey).contains(where: { $0.id == drawing.id }) {
            store.updateDrawing(drawing, key: drawingKey)
        } else {
            store.addDrawing(drawing, key: drawingKey)
        }
        selectedDrawingID = drawing.id
        editingTextDrawing = nil
    }

    private func open(symbol: String, source: LiveSource = .binance) {
        let cleaned = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return }
        viewport = ChartViewport()
        selectedDrawingID = nil
        market.select(source: source, symbol: cleaned)
    }

    private func open(oanda instrument: String) {
        guard OandaSettings.hasToken else {
            pendingOandaInstrument = instrument
            showOandaSettings = true
            return
        }
        viewport = ChartViewport()
        selectedDrawingID = nil
        market.select(source: .oanda, symbol: instrument)
    }

    static func displayName(_ symbol: String) -> String {
        if symbol.contains("_") { return symbol.replacingOccurrences(of: "_", with: "") }
        for quote in ["USDT", "FDUSD", "USDC", "BTC"] where symbol.hasSuffix(quote) && symbol.count > quote.count {
            return "\(symbol.dropLast(quote.count))/\(quote)"
        }
        return symbol
    }

    static func label(_ interval: BinanceClient.Interval) -> String {
        switch interval {
        case .d1: return "1D"
        case .w1: return "1W"
        default: return interval.rawValue
        }
    }

    static func compact(_ value: Double) -> String {
        switch value {
        case 1e9...: return String(format: "%.2fB", value / 1e9)
        case 1e6...: return String(format: "%.2fM", value / 1e6)
        case 1e3...: return String(format: "%.2fK", value / 1e3)
        default: return String(format: "%.2f", value)
        }
    }
}

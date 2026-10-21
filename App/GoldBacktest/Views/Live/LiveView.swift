import SwiftUI
import UIKit
import BacktestKit

/// Live chart laid out like TradingView's mobile app: symbol header with a
/// layer legend, chart with drawing tools and ICT layers, bottom tool bar.
struct LiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market
    @Environment(PaperTrader.self) private var trader
    @Environment(BotController.self) private var bot
    @Environment(NewsStore.self) private var news
    @Environment(MT5Trader.self) private var mt5
    /// A real-money MT5 order waiting for confirmation.
    @State private var pendingRealOrder: (() -> Void)?
    /// Real orders confirmed once for this session.
    @State private var realOrdersConfirmed = false
    @AppStorage("news.vietnamese") private var newsVietnamese = false
    /// Split view: this chart and the correlated market (gold / silver), with SMT on both.
    @AppStorage("live.compare") private var compareMode = false
    /// Two charts side by side (chia dọc) instead of stacked (chia ngang).
    @AppStorage("live.splitColumns") private var splitColumns = false
    @State private var comparisonCache = KillzonePivotsCache()
    @State private var comparisonPriceRange: ClosedRange<Double>?
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("live.theme") private var themeName = "tradingView"
    @AppStorage("live.showEMA200") private var showEMA200 = true
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
    @State private var showAutoStopSettings = false
    @State private var replay = ReplaySession()
    @State private var replaySummary: String?
    @AppStorage("live.showTradeButtons") private var showTradeButtons = true
    /// Timeframes shown in the row under the price; the rest are in the ▾ picker.
    @AppStorage("live.favoriteIntervals") private var favoriteIntervalsText = "1m,5m,15m,1h,4h,1D"
    @State private var showIntervalPicker = false
    @State private var showVoiceSettings = false
    @State private var showIndicatorSheet = false
    @State private var showMoreSheet = false
    /// Opens another sheet once the f(x) / ••• sheet has gone.
    @State private var afterSheet: (() -> Void)?
    /// Position drawing waiting for confirmation before it becomes a demo order.
    @State private var demoOrderDrawing: Drawing?
    /// Limit order being placed by dragging its line on the chart.
    /// The order being prepared in the order sheet (drawn on the chart).
    @State private var orderTicket: OrderTicket?
    /// The order sheet opens low (prices, type, price, volume); drag up for SL/TP and the button.
    @State private var ticketDetent = LiveView.ticketCompact
    static let ticketCompact = PresentationDetent.height(236)
    static let ticketFull = PresentationDetent.fraction(0.56)
    /// Prices of trade lines while they are being dragged.
    @State private var lineOverrides: [String: Double] = [:]
    @AppStorage("trade.lots") private var defaultLots = 0.01
    @AppStorage(VoiceSettings.backgroundKey) private var runInBackground = false
    @AppStorage(VoiceSettings.keepAwakeKey) private var keepAwake = false
    @State private var settingsDrawing: Drawing?

    @State private var viewport = ChartViewport()
    @State private var showSymbolPicker = false
    @State private var showDrawingBar = false
    /// The "Bản vẽ" sheet with every drawing tool.
    @State private var showDrawingTools = false
    @AppStorage(DrawingFavorites.onChartKey) private var favoritesOnChart = true
    /// Thước ngắm: the crosshair shows only while this is on.
    @State private var crosshairMode = false
    /// Crosshair time shared by the two charts of the compare split.
    @State private var linkedCrosshairTime: Date?
    @State private var activeTool: DrawingTool?
    @State private var selectedDrawingID: UUID?
    @State private var editingTextDrawing: Drawing?
    @State private var drawingText = ""
    @State private var legendExpanded = true
    @State private var fullScreen = false
    @State private var confirmClear = false
    @State private var killzoneCache = KillzonePivotsCache()
    /// Custom indicators (tab Chỉ báo) ticked for the Live chart.
    @AppStorage(LiveIndicators.storageKey) private var liveIndicatorIDs = ""
    @State private var indicatorCache = LiveIndicatorCache()
    /// Results reused between frames while the chart is dragged.
    @State private var frameCache = LiveFrameCache()
    @AppStorage(LiveIndicators.sharkKey) private var showSharkFlow = false
    @AppStorage(LiveIndicators.sharkMultipleKey) private var sharkMultiple = 2.5
    @AppStorage("live.sharkPaneHeight") private var sharkPaneHeight = 120.0
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
            charts
            if let flow = sharkFlow, chartCandles.count > 2 {
                SharkFlowPane(output: flow, viewport: viewport, total: chartCandles.count, theme: theme,
                              height: $sharkPaneHeight)
            }
            indicatorPanes
            if showTradeButtons {
                TradeBar(bid: liveQuote.bid, ask: liveQuote.ask, decimals: currentDecimals, lots: $defaultLots,
                         onSell: { marketOrder(.short) }, onBuy: { marketOrder(.long) },
                         onTicket: { side in openTicket(side: side, kind: .market) })
            }
            bottomBar
        }
        .background(theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            market.start(store: store)
            // Strategy signals only run while the bot is on.
            market.track(strategy: bot.isRunning ? bot.strategyID : nil)
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
        .task {
            // The calendar feed asks for few requests; NewsStore refreshes at most every 15 minutes.
            while !Task.isCancelled {
                await news.refresh(vietnamese: newsVietnamese)
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
            }
        }
        .task(id: market.source == .mt5) {
            // Orders on an MT5 chart go to the broker account: keep its positions fresh.
            guard market.source == .mt5 else { return }
            await mt5.watch()
        }
        .alert("Lệnh MT5", isPresented: Binding(get: { mt5.lastError != nil }, set: { if !$0 { mt5.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mt5.lastError ?? "")
        }
        .confirmationDialog("Đặt lệnh trên tài khoản THẬT \(mt5.state?.login.map { "#\($0)" } ?? "")?",
                            isPresented: Binding(get: { pendingRealOrder != nil }, set: { if !$0 { pendingRealOrder = nil } }),
                            titleVisibility: .visible) {
            Button("Đặt lệnh", role: .destructive) {
                pendingRealOrder?()
                pendingRealOrder = nil
            }
            Button("Đặt lệnh và không hỏi lại lần này") {
                realOrdersConfirmed = true
                pendingRealOrder?()
                pendingRealOrder = nil
            }
            Button("Huỷ", role: .cancel) { pendingRealOrder = nil }
        } message: {
            Text("Lệnh dùng tiền thật trên \(market.symbol).")
        }
        .task(id: "\(market.symbolKey)|\(market.interval.rawValue)|\(compareTarget ?? "")") {
            market.setComparison(symbol: compareTarget)
        }
        .sheet(isPresented: $showAutoStopSettings) { AutoStopSettingsView() }
        .alert("Kết quả replay", isPresented: Binding(get: { replaySummary != nil }, set: { if !$0 { replaySummary = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(replaySummary ?? "")
        }
        .sheet(isPresented: $showVoiceSettings) { VoiceSettingsView() }
        .sheet(isPresented: $showDrawingTools) {
            DrawingToolsSheet(activeTool: activeTool, crosshair: $crosshairMode) { tool in
                activeTool = tool
                selectedDrawingID = nil
                showDrawingBar = true
            }
        }
        .sheet(isPresented: $showIndicatorSheet, onDismiss: runAfterSheet) {
            LiveIndicatorSheet(onKillzoneSettings: { afterSheet = { showKillzoneSettings = true } },
                               onManage: { afterSheet = { store.selectedTab = .indicators } })
        }
        .sheet(isPresented: $showMoreSheet, onDismiss: runAfterSheet) {
            LiveMoreSheet(onChartSettings: { afterSheet = { showChartSettings = true } },
                          onVoiceSettings: { afterSheet = { showVoiceSettings = true } },
                          onDemo: { afterSheet = { store.selectedTab = .trade } },
                          onAutoFit: { viewport.manualPriceRange = nil },
                          onClearDrawings: { afterSheet = { confirmClear = true } })
        }
        .sheet(isPresented: Binding(get: { orderTicket != nil }, set: { if !$0 { orderTicket = nil } })) {
            OrderTicketSheet(ticket: $orderTicket, lots: $defaultLots, bid: liveQuote.bid, ask: liveQuote.ask,
                             decimals: currentDecimals, contractSize: PaperAccount.contractSize(for: market.symbolKey),
                             distance: defaultDistance, accountLabel: orderAccountLabel, onSubmit: { submitTicket() })
                .presentationDetents([Self.ticketCompact, Self.ticketFull], selection: $ticketDetent)
                .presentationDragIndicator(.visible)
                // The chart stays usable: drag the order's lines while the sheet is open.
                .presentationBackgroundInteraction(.enabled(upThrough: Self.ticketFull))
        }
        .confirmationDialog(demoOrderTitle, isPresented: Binding(get: { demoOrderDrawing != nil },
                                                                 set: { if !$0 { demoOrderDrawing = nil } }),
                            titleVisibility: .visible) {
            if let drawing = demoOrderDrawing, let levels = drawing.positionLevels {
                Button("Lệnh chờ tại \(CandleChart.format(levels.entry, currentDecimals))") { placeDemoOrder(drawing, market: false) }
                Button("Vào ngay giá \(CandleChart.format(currentPrice, currentDecimals))") { placeDemoOrder(drawing, market: true) }
            }
            Button("Huỷ", role: .cancel) { demoOrderDrawing = nil }
        }
        .sheet(isPresented: $showSymbolPicker) {
            SymbolPickerView(currentID: market.symbolKey, onOpen: { item in
                switch item.source {
                case .oanda: open(oanda: item.symbol)
                default: open(symbol: item.symbol, source: item.source)
                }
            }, onOandaToken: {
                showSymbolPicker = false
                pendingOandaInstrument = nil
                // Open the token sheet once the picker has gone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showOandaSettings = true }
            })
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
                drawingChanged(changed)
            }
        }
        .fullScreenCover(isPresented: $fullScreen) {
            FullScreenChart(title: "\(Self.displayName(market.symbol)) · \(Self.label(market.interval))", theme: theme,
                            onClose: { fullScreen = false }) {
                charts
            }
        }
    }

    // MARK: - Header (TradingView style)

    private var header: some View {
        let last = currentPrice
        let changePct = market.ticker?.changePercent ?? 0
        let changeAbs = last - last / (1 + changePct / 100)
        let decimals = priceDecimals ?? CandleChart.decimals(for: last)
        let changeColor = changePct >= 0 ? theme.up : theme.down
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        // Tap the symbol to switch market.
                        symbolMenu
                        statusDot
                        if replay.isActive {
                            Text("REPLAY")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange, in: Capsule())
                        }
                    }
                    HStack(spacing: 8) {
                        Text(CandleChart.format(last, decimals))
                            .foregroundColor(theme.primaryText)
                            .contentTransition(.numericText())
                        Text(String(format: "%+.\(decimals)f (%+.2f%%)", changeAbs, changePct))
                            .foregroundColor(changeColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 14).monospacedDigit())
                    if market.needsOandaToken {
                        Button("Nhập token OANDA") { showOandaSettings = true }
                            .font(.system(size: 12))
                            .foregroundColor(theme.accent)
                    } else if case .reconnecting(let reason) = market.status {
                        Text(reason).font(.system(size: 12)).foregroundColor(theme.down).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                LiveBotControl(theme: theme)
                VStack(spacing: 6) {
                    // Shows or hides the SELL | lot | BUY bar under the chart.
                    headerButton("BUY/SELL", systemImage: showTradeButtons ? "chevron.down" : "arrow.left.arrow.right",
                                 filled: showTradeButtons) { showTradeButtons.toggle() }
                        .accessibilityLabel(showTradeButtons ? "Ẩn nút giao dịch" : "Hiện nút giao dịch")
                    headerButton(orderTicket != nil ? "Đóng" : "Lệnh chờ",
                                 systemImage: orderTicket != nil ? "xmark" : "plus.forwardslash.minus",
                                 filled: orderTicket != nil) { toggleTicket() }
                }
            }
            legend
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func headerButton(_ title: String, systemImage: String, filled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 14, weight: .bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 112, height: 30)
            .foregroundColor(filled ? .white : theme.accent)
            .background(RoundedRectangle(cornerRadius: 9).fill(filled ? theme.accent : theme.accent.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statusDot: some View {
        Circle()
            .fill(market.status == .live ? theme.up : (market.status == .loading ? BinanceTheme.yellow : theme.down))
            .frame(width: 7, height: 7)
    }

    private var activeLayerNames: [String] {
        var names: [String] = []
        if showKillzonePivots { names.append(Self.killzonePivotsName) }
        if showEMA200 { names.append("EMA 200") }
        if showSharkFlow { names.append("🦈 Dòng tiền cá mập") }
        names += selectedIndicators.map(\.title)
        names += customIndicators.errors.map { "⚠︎ \($0)" }
        if bot.isRunning, let strategy = store.strategies.first(where: { $0.id == bot.strategyID }) {
            names.append("🤖 Bot: \(strategy.name)")
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
                                    Text("· killzone ẩn trên khung này").foregroundColor(theme.text)
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
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { legendExpanded.toggle() }
                } label: {
                    Image(systemName: legendExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.text)
                        .frame(width: 30, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.grid, lineWidth: 1))
                }
                // The chosen timeframes, one tap to switch; ▾ opens all of them.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(rowIntervals, id: \.self) { interval in
                                Button { selectInterval(interval) } label: {
                                    Text(Self.label(interval))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(interval == market.interval ? .white : theme.primaryText)
                                        .frame(minWidth: 38, minHeight: 22)
                                        .background(interval == market.interval ? theme.accent : .clear,
                                                    in: RoundedRectangle(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.grid, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .id(interval)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .onAppear { proxy.scrollTo(market.interval, anchor: .center) }
                }
                Button { showIntervalPicker = true } label: {
                    Image(systemName: "chevron.down.square")
                        .font(.system(size: 18))
                        .foregroundColor(theme.text)
                        .frame(width: 30, height: 24)
                }
                .accessibilityLabel("Tất cả khung thời gian")
                .popover(isPresented: $showIntervalPicker) {
                    IntervalPicker(current: market.interval, favorites: favoriteIntervals,
                                   onSelect: { interval in
                                       selectInterval(interval)
                                       showIntervalPicker = false
                                   },
                                   onToggleFavorite: toggleFavorite)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    /// Favourite timeframes, in the order of all timeframes.
    private var favoriteIntervals: Set<BinanceClient.Interval> {
        let labels = Set(favoriteIntervalsText.split(separator: ",").map(String.init))
        return Set(LiveMarket.intervals.filter { labels.contains(Self.label($0)) })
    }

    /// The row: favourites plus the current timeframe.
    private var rowIntervals: [BinanceClient.Interval] {
        let favorites = favoriteIntervals
        return LiveMarket.intervals.filter { favorites.contains($0) || $0 == market.interval }
    }

    private func toggleFavorite(_ interval: BinanceClient.Interval) {
        var favorites = favoriteIntervals
        if favorites.contains(interval) { favorites.remove(interval) } else { favorites.insert(interval) }
        favoriteIntervalsText = LiveMarket.intervals.filter { favorites.contains($0) }.map(Self.label).joined(separator: ",")
    }


    // MARK: - Chart

    static let killzonePivotsName = "ICT Killzones + Pivots [TFO]"

    private var killzoneSettings: KillzonePivotsSettings { killzoneCache.settings(json: killzonePivotsJSON) }

    /// Market shown beside the chart in compare mode (silver for gold, or the SMT symbol set in the indicator).
    private var compareTarget: String? {
        guard compareMode else { return nil }
        let custom = killzoneSettings.smtSymbol.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? market.defaultComparisonSymbol : custom
    }

    /// Last bar on screen when scrolled back into history; nil at the live edge.
    private var focusIndex: Int? {
        guard viewport.rightOffset > 1 else { return nil }
        return viewport.range(total: chartCandles.count).upperBound - 1
    }

    /// SMT is only drawn while the two markets are side by side.
    private var smtComparison: [Candle] { compareMode ? comparisonChartCandles : [] }

    /// The comparison bars, cut at the replayed bar so replay shows no future.
    private var comparisonChartCandles: [Candle] {
        guard replay.isActive, let last = chartCandles.last?.time else { return market.comparisonCandles }
        return market.comparisonCandles.filter { $0.time <= last }
    }

    private var killzoneLayer: KillzonePivotsLayer {
        killzoneCache.layer(candles: chartCandles, barInterval: market.interval.seconds,
                            settings: killzoneSettings, enabled: showKillzonePivots, comparison: smtComparison,
                            focusIndex: focusIndex)
    }

    /// One chart, or in compare mode the two markets stacked (side by side in landscape).
    @ViewBuilder
    private var charts: some View {
        if compareMode {
            GeometryReader { geometry in
                // Bố cục: chia dọc = side by side, chia ngang = stacked. Stacked, the two
                // frames touch: no time axis on the upper chart, the lower chart's OHLC inside.
                let wide = splitColumns
                let layout = wide ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    chartPanel(timeAxis: wide)
                    comparisonPanel
                }
                .background(theme.grid)
            }
        } else {
            chartPanel(timeAxis: true)
        }
    }

    /// Scroll and zoom follow the main chart; the price axis is its own.
    private var comparisonViewport: Binding<ChartViewport> {
        Binding(get: {
            var shared = viewport
            shared.manualPriceRange = comparisonPriceRange
            return shared
        }, set: { new in
            if new.visibleCount != viewport.visibleCount { viewport.visibleCount = new.visibleCount }
            if new.rightOffset != viewport.rightOffset { viewport.rightOffset = new.rightOffset }
            comparisonPriceRange = new.manualPriceRange
        })
    }

    private var comparisonPanel: some View {
        let candles = comparisonChartCandles
        let layer = comparisonCache.layer(candles: candles, barInterval: market.interval.seconds, settings: killzoneSettings,
                                          enabled: showKillzonePivots, comparison: chartCandles,
                                          focusIndex: viewport.rightOffset > 1 ? viewport.range(total: candles.count).upperBound - 1 : nil)
        let name = market.comparisonSymbol.map { Self.displayName($0) } ?? "—"
        return ZStack(alignment: .topTrailing) {
            if candles.count > 2 {
                CandleChart(candles: candles,
                            showVolume: false,
                            countdownInterval: replay.isActive ? nil : market.interval.seconds,
                            theme: theme,
                            sessionBoxes: layer.boxes,
                            segments: layer.segments,
                            verticalLines: layer.verticalLines,
                            notes: layer.notes,
                            timeEvents: replay.isActive ? [] : newsTimeEvents,
                            candleStyle: CandleStyle(rawValue: candleStyle) ?? .candles,
                            candleColors: frameCache.candleColors(candleColorsJSON),
                            timeZone: ChartTimeZones.zone(timeZoneID),
                            framed: true,
                            crosshairMode: crosshairMode,
                            headerInside: true,
                            linkedCrosshair: $linkedCrosshairTime,
                            viewport: comparisonViewport)
            } else {
                VStack(spacing: 8) {
                    if let error = market.comparisonError {
                        Text(error).foregroundColor(theme.text)
                    } else if market.comparisonSymbol == nil {
                        Text("Không có mã so sánh cho \(Self.displayName(market.symbol)).\nChọn Binance Futures XAUUSDT hoặc OANDA XAU_USD, hoặc nhập mã trong cài đặt Killzones → SMT.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(theme.text)
                    } else {
                        ProgressView()
                        Text("Đang tải \(name)…").foregroundColor(theme.text)
                    }
                }
                .font(.footnote)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background)
            }
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.grid.opacity(0.9)))
                .padding(.top, 6)
                .padding(.trailing, 72)
                .allowsHitTesting(false)
        }
    }

    private func chartPanel(timeAxis: Bool) -> some View {
        let settings = killzoneSettings
        let layer = killzoneCache.layer(candles: chartCandles, barInterval: market.interval.seconds,
                                        settings: settings, enabled: showKillzonePivots, comparison: smtComparison,
                                        focusIndex: focusIndex)
        return ZStack(alignment: .trailing) {
            CandleChart(candles: chartCandles,
                        overlays: overlays,
                        showVolume: showVolume,
                        countdownInterval: replay.isActive ? nil : market.interval.seconds,
                        theme: theme,
                        sessionBoxes: layer.boxes,
                        segments: layer.segments,
                        verticalLines: layer.verticalLines,
                        notes: layer.notes,
                        timeEvents: replay.isActive ? [] : newsTimeEvents,
                        bubbles: sharkBubbles,
                        askPrice: liveQuote.ask > liveQuote.bid ? liveQuote.ask : nil,
                        priceLines: tradeLines,
                        onPriceLineDrag: { id, price, ended in tradeLineDragged(id: id, price: price, ended: ended) },
                        onPriceLineClose: { id in tradeLineClosed(id: id) },
                        onPickBar: replay.isPicking ? { index in replay.pick(index: index) } : nil,
                        onNeedOlder: { loadOlderBars() },
                        showHighLowLabels: showHighLow,
                        drawings: hideDrawings ? [] : drawings,
                        drawingTool: activeTool,
                        selectedDrawingID: selectedDrawingID,
                        onDrawingCreated: { drawing in drawingCreated(drawing) },
                        onDrawingChanged: { drawing in store.updateDrawing(drawing, key: drawingKey) },
                        onSelectDrawing: { id in selectedDrawingID = id },
                        candleStyle: CandleStyle(rawValue: candleStyle) ?? .candles,
                        magnet: magnet,
                        candleColors: frameCache.candleColors(candleColorsJSON),
                        priceDecimals: priceDecimals,
                        timeZone: ChartTimeZones.zone(timeZoneID),
                        drawingsLocked: lockDrawings,
                        positionSizing: positionSizing,
                        framed: true,
                        crosshairMode: crosshairMode,
                        showTimeAxis: timeAxis,
                        linkedCrosshair: compareMode ? $linkedCrosshairTime : nil,
                        viewport: $viewport)
        }
        .overlay(alignment: .leading) {
            if showDrawingBar {
                DrawingToolbar(activeTool: $activeTool, crosshair: $crosshairMode, magnet: $magnet, keepTool: $keepTool,
                               lockAll: $lockDrawings, hideDrawings: $hideDrawings, theme: theme,
                               onAllTools: { showDrawingTools = true },
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
        .overlay(alignment: .topLeading) {
            // Bản vẽ → Hiển thị mục yêu thích trên Biểu đồ.
            if favoritesOnChart, !showDrawingBar {
                FavoriteToolsBar(activeTool: $activeTool, crosshair: $crosshairMode, theme: theme) { showDrawingTools = true }
                    .padding(.leading, 6)
                    .padding(.top, 40)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showKillzonePivots, settings.config.showRangeTable {
                KillzoneRangeTable(layer: layer, settings: settings,
                                   decimals: priceDecimals ?? CandleChart.decimals(for: chartCandles.last?.close ?? 1),
                                   theme: theme)
                    .padding(.trailing, 72)
                    .padding(.top, 40)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
            if replay.isActive {
                ReplayControlBar(replay: replay, profit: trader.account.balance - trader.account.startingBalance + trader.openProfit,
                                 trades: trader.account.history.count, theme: theme, onExit: { endReplay() })
            }
            }
            .padding(.bottom, 24)
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
                                      onChange: { changed in drawingChanged(changed) },
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

    /// Bars on the chart: the live feed, or the bars revealed so far in replay.
    private var chartCandles: [Candle] { replay.isActive ? replay.visibleCandles : market.candles }

    private var currentPrice: Double {
        replay.isActive ? (replay.visibleCandles.last?.close ?? 0) : (market.ticker?.lastPrice ?? market.candles.last?.close ?? 0)
    }

    // MARK: - Replay and history

    private func loadOlderBars() {
        Task {
            let added = await market.loadOlder()
            if replay.isActive { replay.prepend(added) }
        }
    }

    private func toggleReplay() {
        if replay.isActive {
            endReplay()
        } else {
            orderTicket = nil
            replay.begin(candles: market.candles, symbolKey: market.symbolKey, trader: trader)
            viewport = ChartViewport()
        }
    }

    private func endReplay() {
        guard let account = replay.end() else { return }
        viewport = ChartViewport()
        let trades = account.history
        guard !trades.isEmpty || !account.positions.isEmpty else { return }
        let wins = trades.filter { $0.profit > 0 }.count
        let total = account.balance - account.startingBalance
        replaySummary = String(format: "%d lệnh đã đóng · thắng %d (%.0f%%)\nLãi/lỗ: %+.2f USD", trades.count, wins,
                               trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100, total)
            + (account.positions.isEmpty ? "" : "\n\(account.positions.count) lệnh còn mở bị bỏ qua.")
    }

    /// Changes timeframe; replay is left first since its bars belong to the old one.
    private func selectInterval(_ interval: BinanceClient.Interval) {
        if replay.isActive { endReplay() }
        viewport = ChartViewport()
        market.select(interval: interval)
    }
    private var currentDecimals: Int { priceDecimals ?? CandleChart.decimals(for: currentPrice) }

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
        if tradesMT5 {
            let symbol = market.symbol
            if useMarket {
                sendMT5 { await mt5.market(symbol: symbol, side: side, lots: lots, stop: levels.stop, target: levels.target) }
            } else {
                sendMT5 { await mt5.pending(symbol: symbol, side: side, lots: lots, entry: levels.entry,
                                            stop: levels.stop, target: levels.target) }
            }
            demoOrderDrawing = nil
            return
        }
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

    /// Typical bar range, used to place a new limit order and its SL/TP.
    private var defaultDistance: Double {
        let recent = chartCandles.suffix(20)
        let average = recent.isEmpty ? 0 : recent.reduce(0) { $0 + ($1.high - $1.low) } / Double(recent.count)
        return average > 0 ? average : max(currentPrice * 0.001, 1e-6)
    }

    /// Bid/ask to show and trade at: the live quote, or the chart price for both.
    private var liveQuote: LiveMarket.Quote {
        if !replay.isActive, let q = market.quote, q.bid > 0, q.ask >= q.bid, q.ask - q.bid < currentPrice * 0.01 {
            return q
        }
        return LiveMarket.Quote(bid: currentPrice, ask: currentPrice)
    }

    /// Where orders go, shown in the order sheet.
    private var orderAccountLabel: String {
        if replay.isActive { return "Tài khoản replay" }
        if tradesMT5 {
            let login = mt5.state?.login.map { "#\($0)" } ?? ""
            return "MT5 \(login) · \(mt5.isReal ? "TIỀN THẬT" : "demo")"
        }
        return "Tài khoản demo trong app"
    }

    private func toggleTicket() {
        if orderTicket != nil {
            orderTicket = nil
        } else {
            openTicket(side: .long, kind: .limit)
        }
    }

    private func openTicket(side: PaperAccount.Side, kind: OrderTicket.Kind) {
        guard currentPrice > 0 else { return }
        let auto = AutoStops.enabled ? autoStopDistance : nil
        if orderTicket == nil { ticketDetent = Self.ticketCompact }
        orderTicket = OrderTicket.make(side: side, kind: kind, bid: liveQuote.bid, ask: liveQuote.ask,
                                       distance: defaultDistance, stopDistance: auto,
                                       targetDistance: auto.map { $0 * AutoStops.riskReward })
    }

    private func submitTicket() {
        guard let t = orderTicket, currentPrice > 0, t.problem(bid: liveQuote.bid, ask: liveQuote.ask) == nil else { return }
        if t.kind == .market {
            marketOrder(t.side, stop: t.stop, target: t.target)
        } else if tradesMT5 {
            let symbol = market.symbol, lots = defaultLots
            sendMT5 { await mt5.pending(symbol: symbol, side: t.side, lots: lots, entry: t.entry, stop: t.stop, target: t.target) }
        } else {
            // The demo account decides limit or stop from where the entry is against the price.
            let reference = t.side == .long ? liveQuote.ask : liveQuote.bid
            trader.placePending(symbol: market.symbolKey, side: t.side, lots: defaultLots, entry: t.entry,
                                stop: t.stop, target: t.target, currentPrice: reference)
        }
        orderTicket = nil
    }

    /// SL distance from the automatic SL/TP settings (falls back to 3 bar ranges).
    private var autoStopDistance: Double {
        AutoStops.stopDistance(lots: defaultLots, contractSize: PaperAccount.contractSize(for: market.symbolKey),
                               typicalRange: defaultDistance) ?? defaultDistance * 3
    }

    /// On an MT5 chart orders go to the broker account on the VPS.
    private var tradesMT5: Bool { market.source == .mt5 && !replay.isActive }

    /// Runs an MT5 order, asking first on a real account.
    private func sendMT5(_ order: @escaping () async -> Void) {
        let run = { Task { await order() } }
        if mt5.isReal && !realOrdersConfirmed {
            pendingRealOrder = { _ = run() }
        } else {
            _ = run()
        }
    }

    /// SELL at the bid or BUY at the ask. One-click orders get the automatic
    /// SL/TP when that option is on; the order sheet passes its own.
    private func marketOrder(_ side: PaperAccount.Side, stop givenStop: Double?? = nil, target givenTarget: Double?? = nil) {
        guard currentPrice > 0 else { return }
        let fill = side == .long ? liveQuote.ask : liveQuote.bid
        var stop: Double?, target: Double?
        if let givenStop, let givenTarget {
            stop = givenStop
            target = givenTarget
        } else if AutoStops.enabled, AutoStops.applyToMarket {
            let distance = autoStopDistance
            stop = fill - side.sign * distance
            target = fill + side.sign * distance * AutoStops.riskReward
        }
        if tradesMT5 {
            let symbol = market.symbol, lots = defaultLots
            sendMT5 { await mt5.market(symbol: symbol, side: side, lots: lots, stop: stop, target: target) }
            return
        }
        if side == .long {
            trader.buy(symbol: market.symbolKey, lots: defaultLots, price: fill, stop: stop, target: target)
        } else {
            trader.sell(symbol: market.symbolKey, lots: defaultLots, price: fill, stop: stop, target: target)
        }
    }

    /// ✕ on a trade line: close the position, cancel the order or the draft.
    private func tradeLineClosed(id: String) {
        let parts = id.split(separator: "|").map(String.init)
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "mpos":
            if let ticket = Int(parts[1]) { sendMT5 { await mt5.close(ticket) } }
        case "mord":
            if let ticket = Int(parts[1]) { Task { await mt5.cancel(ticket) } }
        case "pos":
            if let p = trader.account.positions.first(where: { $0.id.uuidString == parts[1] }) { trader.close(p) }
        case "ord":
            if let o = trader.account.pending.first(where: { $0.id.uuidString == parts[1] }) { trader.cancel(o) }
        case "ticket":
            orderTicket = nil
        default:
            break
        }
    }

    /// Green when moving from `entry` to `price` makes money, red when it loses.
    private func moneyColor(side: PaperAccount.Side, entry: Double, price: Double) -> Color {
        (price - entry) * side.sign >= 0 ? theme.up : theme.down
    }

    /// Bar on which a position was opened, for its entry marker.
    private func openIndex(_ time: Date) -> Int? {
        chartCandles.lastIndex { $0.time <= time }
    }

    /// Money made or lost if price moves from `entry` to `price`.
    private func money(side: PaperAccount.Side, lots: Double, entry: Double, price: Double) -> String {
        let value = (price - entry) * side.sign * lots * PaperAccount.contractSize(for: market.symbolKey)
        return String(format: "%+.2f USD", value)
    }

    /// Draggable trade lines (MT5 style): positions with their SL/TP, pending
    /// orders and the limit order being placed.
    private var tradeLines: [ChartPriceLine] {
        let key = market.symbolKey
        let red = theme.down, green = theme.up, blue = Color(red: 0.161, green: 0.384, blue: 1.0)
        func value(_ id: String, _ price: Double) -> Double { lineOverrides[id] ?? price }
        var lines: [ChartPriceLine] = []

        if tradesMT5 {
            lines += mt5Lines(value: value)
        }
        for p in trader.account.positions where p.symbol == key && !tradesMT5 {
            let id = "pos|\(p.id.uuidString)"
            let profit = trader.profit(p) ?? 0
            if let dragged = lineOverrides[id + "|entry"] {
                // Dragging away from the entry sets a new SL or TP.
                let isProfit = (dragged - p.entryPrice) * p.side.sign > 0
                lines.append(ChartPriceLine(id: id + "|entry", price: dragged, color: isProfit ? green : red,
                                            label: "\(isProfit ? "TP" : "SL") \(money(side: p.side, lots: p.lots, entry: p.entryPrice, price: dragged))",
                                            dash: [5, 3]))
            }
            lines.append(ChartPriceLine(id: id + "|entry", price: p.entryPrice, color: p.side == .long ? blue : red,
                                        label: "\(p.side == .long ? "BUY" : "SELL") \(QuickTradePanel.lotText(p.lots))",
                                        dash: [6, 4], handleFraction: 0.42,
                                        value: String(format: "%+.2f USD", profit), valueColor: profit >= 0 ? green : red,
                                        markerIndex: openIndex(p.openTime), closable: true))
            if let stop = p.stop {
                let price = value(id + "|sl", stop)
                lines.append(ChartPriceLine(id: id + "|sl", price: price, color: red, label: "SL", dash: [4, 4], handleFraction: 0.42,
                                            value: money(side: p.side, lots: p.lots, entry: p.entryPrice, price: price),
                                            valueColor: moneyColor(side: p.side, entry: p.entryPrice, price: price)))
            }
            if let target = p.target {
                let price = value(id + "|tp", target)
                lines.append(ChartPriceLine(id: id + "|tp", price: price, color: green, label: "TP", dash: [4, 4], handleFraction: 0.42,
                                            value: money(side: p.side, lots: p.lots, entry: p.entryPrice, price: price),
                                            valueColor: moneyColor(side: p.side, entry: p.entryPrice, price: price)))
            }
        }

        for o in trader.account.pending where o.symbol == key && !tradesMT5 {
            let id = "ord|\(o.id.uuidString)"
            let entry = value(id + "|entry", o.entry)
            let kind = (entry > currentPrice) == (o.side == .long) ? "STOP" : "LIMIT"
            lines.append(ChartPriceLine(id: id + "|entry", price: entry, color: o.side == .long ? blue : red,
                                        label: "\(o.side == .long ? "BUY" : "SELL") \(kind) \(QuickTradePanel.lotText(o.lots))",
                                        handleFraction: 0.55, closable: true))
            if let stop = o.stop {
                let price = value(id + "|sl", stop + (entry - o.entry))
                lines.append(ChartPriceLine(id: id + "|sl", price: price, color: red,
                                            label: "SL", dash: [4, 4], handleFraction: 0.55,
                                            value: money(side: o.side, lots: o.lots, entry: entry, price: price),
                                            valueColor: moneyColor(side: o.side, entry: entry, price: price)))
            }
            if let target = o.target {
                let price = value(id + "|tp", target + (entry - o.entry))
                lines.append(ChartPriceLine(id: id + "|tp", price: price, color: green,
                                            label: "TP", dash: [4, 4], handleFraction: 0.55,
                                            value: money(side: o.side, lots: o.lots, entry: entry, price: price),
                                            valueColor: moneyColor(side: o.side, entry: entry, price: price)))
            }
        }

        if let t = orderTicket {
            let open = t.openPrice(bid: liveQuote.bid, ask: liveQuote.ask)
            let entry = t.isPending ? value("ticket|entry", t.entry) : open
            let shift = t.isPending ? entry - t.entry : 0
            if t.isPending {
                lines.append(ChartPriceLine(id: "ticket|entry", price: entry, color: t.side == .long ? blue : red,
                                            label: "\(t.name) \(QuickTradePanel.lotText(defaultLots))",
                                            handleFraction: 0.42, closable: true))
            }
            if let stop = t.stop {
                let price = value("ticket|sl", stop + shift)
                lines.append(ChartPriceLine(id: "ticket|sl", price: price, color: red, label: "SL", dash: [4, 4],
                                            handleFraction: 0.42,
                                            value: money(side: t.side, lots: defaultLots, entry: entry, price: price),
                                            valueColor: moneyColor(side: t.side, entry: entry, price: price)))
            }
            if let target = t.target {
                let price = value("ticket|tp", target + shift)
                lines.append(ChartPriceLine(id: "ticket|tp", price: price, color: green, label: "TP", dash: [4, 4],
                                            handleFraction: 0.42,
                                            value: money(side: t.side, lots: defaultLots, entry: entry, price: price),
                                            valueColor: moneyColor(side: t.side, entry: entry, price: price)))
            }
        }
        return lines
    }

    /// The MT5 account's positions and pending orders on this symbol, like the demo lines.
    private func mt5Lines(value: (String, Double) -> Double) -> [ChartPriceLine] {
        let red = theme.down, green = theme.up, blue = Color(red: 0.161, green: 0.384, blue: 1.0)
        let tag = mt5.isReal ? "" : " (demo)"
        var lines: [ChartPriceLine] = []
        for p in mt5.positions(market.symbol) {
            let id = "mpos|\(p.ticket)"
            let side = p.paperSide
            lines.append(ChartPriceLine(id: id + "|entry", price: p.entry, color: side == .long ? blue : red,
                                        label: "\(side == .long ? "BUY" : "SELL") \(QuickTradePanel.lotText(p.lots))\(tag)",
                                        dash: [6, 4], handleFraction: 0.42,
                                        value: String(format: "%+.2f %@", p.profit, mt5.state?.currency ?? "USD"),
                                        valueColor: p.profit >= 0 ? green : red,
                                        markerIndex: openIndex(Date(timeIntervalSince1970: p.time)), closable: true))
            if let stop = p.stop {
                let price = value(id + "|sl", stop)
                lines.append(ChartPriceLine(id: id + "|sl", price: price, color: red, label: "SL", dash: [4, 4], handleFraction: 0.42,
                                            value: money(side: side, lots: p.lots, entry: p.entry, price: price),
                                            valueColor: moneyColor(side: side, entry: p.entry, price: price)))
            }
            if let target = p.target {
                let price = value(id + "|tp", target)
                lines.append(ChartPriceLine(id: id + "|tp", price: price, color: green, label: "TP", dash: [4, 4], handleFraction: 0.42,
                                            value: money(side: side, lots: p.lots, entry: p.entry, price: price),
                                            valueColor: moneyColor(side: side, entry: p.entry, price: price)))
            }
        }
        for o in mt5.orders(market.symbol) {
            let id = "mord|\(o.ticket)"
            let side = o.paperSide
            let entry = value(id + "|entry", o.entry)
            lines.append(ChartPriceLine(id: id + "|entry", price: entry, color: side == .long ? blue : red,
                                        label: "\(side == .long ? "BUY" : "SELL") \(o.kind.uppercased()) \(QuickTradePanel.lotText(o.lots))\(tag)",
                                        handleFraction: 0.55, closable: true))
            if let stop = o.stop {
                let price = value(id + "|sl", stop + (entry - o.entry))
                lines.append(ChartPriceLine(id: id + "|sl", price: price, color: red, label: "SL", dash: [4, 4],
                                            handleFraction: 0.55,
                                            value: money(side: side, lots: o.lots, entry: entry, price: price),
                                            valueColor: moneyColor(side: side, entry: entry, price: price)))
            }
            if let target = o.target {
                let price = value(id + "|tp", target + (entry - o.entry))
                lines.append(ChartPriceLine(id: id + "|tp", price: price, color: green, label: "TP", dash: [4, 4],
                                            handleFraction: 0.55,
                                            value: money(side: side, lots: o.lots, entry: entry, price: price),
                                            valueColor: moneyColor(side: side, entry: entry, price: price)))
            }
        }
        return lines
    }

    /// A dragged MT5 line: new SL/TP for a position, new entry/SL/TP for a pending order.
    private func mt5LineDragged(kind: String, ticket: Int, field: String, price: Double) {
        let rejected = { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        if kind == "mpos", let p = mt5.positions(market.symbol).first(where: { $0.ticket == ticket }) {
            let lossSide = (price - currentPrice) * p.paperSide.sign < 0
            var stop = p.stop, target = p.target
            switch field {
            case "sl": guard lossSide else { return rejected() }; stop = price
            case "tp": guard !lossSide else { return rejected() }; target = price
            case "entry": if lossSide { stop = price } else { target = price }
            default: return
            }
            sendMT5 { await mt5.modify(ticket, stop: stop, target: target) }
        } else if kind == "mord", let o = mt5.orders(market.symbol).first(where: { $0.ticket == ticket }) {
            var entry = o.entry, stop = o.stop, target = o.target
            switch field {
            case "entry":
                let shift = price - o.entry
                entry = price
                stop = stop.map { $0 + shift }
                target = target.map { $0 + shift }
            case "sl":
                guard (price - o.entry) * o.paperSide.sign < 0 else { return rejected() }
                stop = price
            case "tp":
                guard (price - o.entry) * o.paperSide.sign > 0 else { return rejected() }
                target = price
            default: return
            }
            sendMT5 { await mt5.modify(ticket, entry: entry, stop: stop, target: target) }
        }
    }

    /// Applies a dragged trade line: moves SL/TP, pending entries or the limit draft.
    private func tradeLineDragged(id: String, price: Double, ended: Bool) {
        guard ended else {
            lineOverrides[id] = price
            return
        }
        lineOverrides[id] = nil
        let parts = id.split(separator: "|").map(String.init)
        guard parts.count >= 2 else { return }
        let field = parts.last ?? ""
        let rejected = { UINotificationFeedbackGenerator().notificationOccurred(.error) }

        switch parts[0] {
        case "mpos", "mord":
            if let ticket = Int(parts[1]) { mt5LineDragged(kind: parts[0], ticket: ticket, field: field, price: price) }
        case "ticket":
            guard var t = orderTicket else { return }
            switch field {
            case "entry":
                // SL and TP move with the entry.
                let shift = price - t.entry
                t.entry = price
                t.stop = t.stop.map { $0 + shift }
                t.target = t.target.map { $0 + shift }
            case "sl": t.stop = price
            case "tp": t.target = price
            default: break
            }
            orderTicket = t
        case "pos":
            guard let p = trader.account.positions.first(where: { $0.id.uuidString == parts[1] }) else { return }
            let now = trader.price(market.symbolKey) ?? currentPrice
            // SL must stay on the losing side of the current price, TP on the winning side.
            let lossSide = (price - now) * p.side.sign < 0
            switch field {
            case "sl":
                if lossSide { trader.modify(p, stop: price, target: p.target) } else { rejected() }
            case "tp":
                if !lossSide { trader.modify(p, stop: p.stop, target: price) } else { rejected() }
            case "entry":
                if lossSide { trader.modify(p, stop: price, target: p.target) } else { trader.modify(p, stop: p.stop, target: price) }
            default: break
            }
        case "ord":
            guard let o = trader.account.pending.first(where: { $0.id.uuidString == parts[1] }) else { return }
            var entry = o.entry, stop = o.stop, target = o.target
            switch field {
            case "entry":
                // SL and TP move with the entry.
                let shift = price - o.entry
                entry = price
                stop = stop.map { $0 + shift }
                target = target.map { $0 + shift }
            case "sl":
                guard (price - o.entry) * o.side.sign < 0 else { return rejected() }
                stop = price
            case "tp":
                guard (price - o.entry) * o.side.sign > 0 else { return rejected() }
                target = price
            default: break
            }
            trader.modifyPending(o, entry: entry, stop: stop, target: target, currentPrice: currentPrice)
        default:
            break
        }
    }

    private var positionSizing: PositionSizing? {
        accountBalance > 0 ? PositionSizing(balance: accountBalance, riskPercent: riskPercent, contractSize: contractSize) : nil
    }

    private var selectedDrawing: Drawing? {
        guard let id = selectedDrawingID else { return nil }
        return drawings.first { $0.id == id }
    }

    private func drawingCreated(_ new: Drawing) {
        // Starts with the look last used for this tool.
        var drawing = new
        if let style = DrawingStyles.defaultStyle(for: drawing.tool) { drawing.style = style }
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

    /// Saves an edited drawing; a new look becomes the default for its tool.
    private func drawingChanged(_ changed: Drawing) {
        if let old = drawings.first(where: { $0.id == changed.id }), old.style != changed.style {
            DrawingStyles.setDefault(changed.style, for: changed.tool)
        }
        store.updateDrawing(changed, key: drawingKey)
    }

    /// "Dòng tiền cá mập" of the chart's bars (nil when off).
    private var sharkFlow: SharkFlow.Output? {
        guard showSharkFlow else { return nil }
        return frameCache.sharkFlow(chartCandles, multiple: sharkMultiple)
    }

    private var sharkBubbles: [ChartBubble] {
        sharkFlow?.sharks.map { ChartBubble(index: $0.index, buying: $0.buying, ratio: $0.ratio) } ?? []
    }

    private var overlays: [ChartLine] {
        var lines: [ChartLine] = []
        if showEMA200 {
            lines.append(ChartLine(title: "EMA(200)", values: frameCache.ema200(chartCandles.map { $0.close }, candles: chartCandles),
                                   color: Color(red: 1.0, green: 0.596, blue: 0.0)))
        }
        return lines + customIndicators.overlays
    }

    private var selectedIndicators: [CustomIndicator] {
        let ids = LiveIndicators.ids(liveIndicatorIDs)
        return store.indicators.filter { ids.contains($0.id) }
    }

    /// The ticked custom indicators computed on the chart's bars.
    private var customIndicators: IndicatorRenderer {
        indicatorCache.render(selectedIndicators, candles: chartCandles, library: store.library,
                              timeZone: store.config.timeZone)
    }

    /// Indicators that draw in their own panel (RSI-like), under the chart.
    @ViewBuilder
    private var indicatorPanes: some View {
        let rendered = customIndicators
        if !rendered.panes.isEmpty, chartCandles.count > 2 {
            let times = chartCandles.map(\.time)
            let range = viewport.range(total: chartCandles.count)
            VStack(spacing: 0) {
                ForEach(rendered.panes.prefix(3)) { pane in
                    ZStack(alignment: .topLeading) {
                        PaneChartView(times: times, lines: pane.lines, range: range)
                            .padding(.leading, 4)
                            .padding(.top, 14)
                        Button { store.selectedTab = .indicators } label: {
                            Text(pane.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.primaryText)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 6)
                        .padding(.top, 2)
                    }
                    .frame(height: 96)
                    .overlay(alignment: .top) { Rectangle().fill(theme.grid).frame(height: 1) }
                }
            }
            .background(theme.background)
        }
    }

    // MARK: - Bottom tool bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            layoutButton
            newsInfo
            Spacer(minLength: 4)
            toolbarButton("backward.end.alt", active: replay.isActive) { toggleReplay() }
            toolbarButton("pencil.tip", active: showDrawingBar) {
                if showDrawingBar {
                    showDrawingBar = false
                    activeTool = nil
                } else {
                    showDrawingTools = true
                }
            }
            toolbarButton("function", active: false) { showIndicatorSheet = true }
            toolbarButton("ellipsis", active: false) { showMoreSheet = true }
            toolbarButton("arrow.up.left.and.arrow.down.right", active: false) {
                fullScreen = true
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(theme.background)
        .overlay(alignment: .top) { Rectangle().fill(theme.grid).frame(height: 1) }
    }

    // MARK: - Session and news info

    /// Red USD news of today (chart time zone), grouped by time, for the time axis.
    private var todaysRedNews: [(time: Date, events: [EconomicEvent])] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ChartTimeZones.zone(timeZoneID)
        let today = MarketNews.goldEvents(news.events, minimum: .high).filter { calendar.isDateInToday($0.date) }
        let grouped = Dictionary(grouping: today, by: \.date)
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    private var newsTimeEvents: [ChartTimeEvent] {
        todaysRedNews.map { item in
            var label = Self.shortNewsTitle(item.events.first?.title ?? "")
            if item.events.count > 1 { label += " +\(item.events.count - 1)" }
            label += " " + clockText(item.time)
            let past = item.time < Date()
            return ChartTimeEvent(time: item.time, label: label, color: Self.newsRed.opacity(past ? 0.55 : 1))
        }
    }

    static let newsRed = Color(red: 0.91, green: 0.2, blue: 0.24)

    static func shortNewsTitle(_ title: String) -> String {
        title.count > 16 ? String(title.prefix(15)) + "…" : title
    }

    private func clockText(_ date: Date) -> String {
        frameCache.clock(date, zone: timeZoneID)
    }

    /// Bố cục: one chart, or two (this market and the correlated one, SMT on both)
    /// stacked (chia ngang) or side by side (chia dọc).
    private var layoutButton: some View {
        Menu {
            Button { compareMode = false } label: {
                Label("1 biểu đồ", systemImage: compareMode ? "rectangle" : "checkmark")
            }
            Button {
                compareMode = true
                splitColumns = false
            } label: {
                Label("Chia ngang 2 (trên / dưới)", systemImage: compareMode && !splitColumns ? "checkmark" : "rectangle.split.1x2")
            }
            Button {
                compareMode = true
                splitColumns = true
            } label: {
                Label("Chia dọc 2 (trái / phải)", systemImage: compareMode && splitColumns ? "checkmark" : "rectangle.split.2x1")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: !compareMode ? "rectangle" : (splitColumns ? "rectangle.split.2x1.fill" : "rectangle.split.1x2.fill"))
                Text("Bố cục")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(compareMode ? .white : theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(compareMode ? theme.accent : theme.grid.opacity(theme.isLight ? 0.5 : 0.8)))
        }
    }

    /// The next red news of the day; tap for the News tab.
    @ViewBuilder
    private var newsInfo: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let next = todaysRedNews.first(where: { $0.time > context.date }) {
                Button { store.selectedTab = .news } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Self.newsRed).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.shortNewsTitle(next.events.first?.title ?? ""))
                                .foregroundColor(theme.primaryText)
                            Text("\(clockText(next.time)) · sau \(Self.duration(next.time.timeIntervalSince(context.date)))")
                                .foregroundColor(theme.text)
                        }
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)g\(String(format: "%02d", minutes % 60))" : "\(minutes)p"
    }

    private var symbolMenu: some View {
        Button { showSymbolPicker = true } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(LinearGradient(colors: [BinanceTheme.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22)
                    .overlay(Text(String(market.symbol.prefix(1))).font(.system(size: 11, weight: .bold)).foregroundColor(.white))
                Text(Self.displayName(market.symbol))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(theme.text)
            }
        }
    }

    private func runAfterSheet() {
        let action = afterSheet
        afterSheet = nil
        action?()
    }

    private func toolbarIcon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(active ? theme.accent : theme.primaryText)
            .frame(width: 38, height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? theme.accent.opacity(0.14) : .clear))
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
        let cleaned = WatchItem.clean(symbol, source: source)
        guard !cleaned.isEmpty else { return }
        if replay.isActive { endReplay() }
        viewport = ChartViewport()
        selectedDrawingID = nil
        // MT5 has no second bars: fall back to 1m.
        market.select(source: source, symbol: cleaned,
                      interval: source == .mt5 && market.interval.isSeconds ? .m1 : nil)
    }

    private func open(oanda instrument: String) {
        guard OandaSettings.hasToken else {
            pendingOandaInstrument = instrument
            showOandaSettings = true
            return
        }
        if replay.isActive { endReplay() }
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

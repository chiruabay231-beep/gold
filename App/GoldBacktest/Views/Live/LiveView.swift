import SwiftUI
import BacktestKit

/// Binance-style live chart with strategy signals.
struct LiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewport = ChartViewport()
    @State private var showMA = true
    @State private var showStrategyPlots = true
    @State private var customSymbol = ""
    @State private var askingSymbol = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            priceHeader
            intervalBar
            ExpandableCandleChart(title: "\(Self.displayName(market.symbol)) · \(Self.label(market.interval))",
                                  candles: market.candles, overlays: overlays, markers: markers,
                                  countdownInterval: market.interval.seconds, viewport: $viewport)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            strategyBar
            signalList
        }
        .background(BinanceTheme.panel.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            market.start(store: store)
            if market.strategyID == nil {
                market.track(strategy: store.strategies.first { $0.name.hasPrefix("ICT Silver") }?.id ?? store.strategies.first?.id)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: market.start(store: store)
            case .background: market.stop()
            default: break
            }
        }
        .alert("Nhập mã Binance", isPresented: $askingSymbol) {
            TextField("VD: ADAUSDT", text: $customSymbol)
                .textInputAutocapitalization(.characters)
            Button("Huỷ", role: .cancel) {}
            Button("Mở") { open(symbol: customSymbol) }
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(LiveMarket.popularSymbols, id: \.self) { symbol in
                    Button(Self.displayName(symbol)) { open(symbol: symbol) }
                }
                Button("Nhập mã khác…") {
                    customSymbol = ""
                    askingSymbol = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(Self.displayName(market.symbol))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(BinanceTheme.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BinanceTheme.text)
                }
            }
            if let change = market.ticker?.changePercent {
                Text(String(format: "%+.2f%%", change))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((change >= 0 ? BinanceTheme.up : BinanceTheme.down).opacity(0.15), in: .rect(cornerRadius: 4))
                    .foregroundColor(change >= 0 ? BinanceTheme.up : BinanceTheme.down)
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(market.status == .live ? BinanceTheme.up : (market.status == .loading ? BinanceTheme.yellow : BinanceTheme.down))
                .frame(width: 7, height: 7)
            Text(market.status == .live ? "Live" : (market.status == .loading ? "Đang tải" : "Offline"))
                .font(.system(size: 11))
                .foregroundColor(BinanceTheme.text)
        }
    }

    private var priceHeader: some View {
        let last = market.ticker?.lastPrice ?? market.candles.last?.close ?? 0
        let change = market.ticker?.changePercent ?? 0
        let decimals = CandleChart.decimals(for: last)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CandleChart.format(last, decimals))
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundColor(change >= 0 ? BinanceTheme.up : BinanceTheme.down)
                    .contentTransition(.numericText())
                if case .reconnecting(let reason) = market.status {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(BinanceTheme.down)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                stat("24h High", market.ticker.map { CandleChart.format($0.high, decimals) })
                stat("24h Low", market.ticker.map { CandleChart.format($0.low, decimals) })
                stat("24h Vol(USDT)", market.ticker.map { Self.compact($0.quoteVolume) })
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundColor(BinanceTheme.text)
            Text(value ?? "–").foregroundColor(BinanceTheme.primaryText)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .font(.system(size: 11).monospacedDigit())
    }

    private var intervalBar: some View {
        HStack(spacing: 14) {
            ForEach(LiveMarket.intervals, id: \.self) { interval in
                Button {
                    viewport = ChartViewport()
                    market.select(interval: interval)
                } label: {
                    VStack(spacing: 3) {
                        Text(Self.label(interval))
                            .font(.system(size: 13, weight: market.interval == interval ? .semibold : .regular))
                            .foregroundColor(market.interval == interval ? BinanceTheme.primaryText : BinanceTheme.text)
                        Rectangle()
                            .fill(market.interval == interval ? BinanceTheme.yellow : .clear)
                            .frame(width: 14, height: 2)
                    }
                }
            }
            Spacer()
            Menu {
                Toggle("MA(7, 25, 99)", isOn: $showMA)
                Toggle("Đường của chiến lược", isOn: $showStrategyPlots)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(BinanceTheme.text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(BinanceTheme.panel)
    }

    // MARK: - Chart data

    private var overlays: [ChartLine] {
        var lines: [ChartLine] = []
        if showMA {
            let closes = market.candles.map(\.close)
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

    // MARK: - Strategy & signals

    private var strategyBar: some View {
        @Bindable var market = market
        return HStack(spacing: 10) {
            Image(systemName: "bolt.fill").foregroundColor(BinanceTheme.yellow)
            Picker("Chiến lược", selection: Binding(get: { market.strategyID }, set: { market.track(strategy: $0) })) {
                Text("Không theo dõi").tag(UUID?.none)
                ForEach(store.strategies) { strategy in
                    Text(strategy.name).tag(Optional(strategy.id))
                }
            }
            .tint(BinanceTheme.primaryText)
            Spacer()
            Toggle(isOn: $market.notificationsEnabled) {
                Image(systemName: market.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .foregroundColor(BinanceTheme.text)
            }
            .toggleStyle(.button)
            .onChange(of: market.notificationsEnabled) { _, enabled in
                if enabled { LiveMarket.requestNotificationPermission() }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(BinanceTheme.background)
    }

    private var signalList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let error = market.strategyError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(BinanceTheme.down)
                        .padding(14)
                } else if market.strategyID != nil, market.signals.isEmpty {
                    Text("Chưa có tín hiệu trên \(market.closedCandles.count) nến gần nhất. Tín hiệu mới sẽ được báo khi nến đóng.")
                        .font(.system(size: 12))
                        .foregroundColor(BinanceTheme.text)
                        .padding(14)
                }
                ForEach(market.signals.reversed().prefix(30)) { signal in
                    SignalRow(signal: signal, isLatest: signal.id == market.latestAlert?.id)
                    Divider().overlay(BinanceTheme.grid)
                }
            }
        }
        .frame(height: 150)
        .background(BinanceTheme.panel)
    }

    // MARK: - Helpers

    private func open(symbol: String) {
        let cleaned = symbol.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !cleaned.isEmpty else { return }
        viewport = ChartViewport()
        market.select(symbol: cleaned)
    }

    static func displayName(_ symbol: String) -> String {
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

private struct SignalRow: View {
    let signal: LiveSignal
    let isLatest: Bool

    private var color: Color {
        switch signal.kind {
        case .longEntry: return BinanceTheme.up
        case .shortEntry: return BinanceTheme.down
        case .longExit, .shortExit: return BinanceTheme.text
        }
    }

    var body: some View {
        let decimals = CandleChart.decimals(for: signal.price)
        HStack(spacing: 10) {
            Text(signal.kind.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.time.formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute()))
                    .foregroundColor(BinanceTheme.text)
                Text(CandleChart.format(signal.price, decimals))
                    .foregroundColor(BinanceTheme.primaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let stop = signal.stop {
                    Text("SL \(CandleChart.format(stop, decimals))").foregroundColor(BinanceTheme.down)
                }
                if let target = signal.target {
                    Text("TP \(CandleChart.format(target, decimals))").foregroundColor(BinanceTheme.up)
                }
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isLatest ? BinanceTheme.yellow.opacity(0.08) : .clear)
    }
}

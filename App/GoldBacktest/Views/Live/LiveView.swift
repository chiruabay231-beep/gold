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
            latestSignalBar
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
                        .foregroundColor(BinanceTheme.text)
                        .lineLimit(1)
                    if let error = market.strategyError {
                        Text(error).foregroundColor(BinanceTheme.down).lineLimit(1)
                    } else if let latest {
                        let decimals = CandleChart.decimals(for: latest.price)
                        Text(latest.kind.label)
                            .fontWeight(.bold)
                            .foregroundColor(LiveSignalRow.color(for: latest.kind))
                        Text(CandleChart.format(latest.price, decimals))
                            .foregroundColor(BinanceTheme.primaryText)
                        Text(latest.time.formatted(.dateTime.hour().minute()))
                            .foregroundColor(BinanceTheme.text)
                    } else {
                        Text("Chưa có tín hiệu").foregroundColor(BinanceTheme.text)
                    }
                } else {
                    Text("Chọn chiến lược để nhận tín hiệu").foregroundColor(BinanceTheme.text)
                }
                Spacer(minLength: 4)
                Image(systemName: market.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .foregroundColor(BinanceTheme.text)
                Image(systemName: "chevron.right")
                    .foregroundColor(BinanceTheme.text)
            }
            .font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(BinanceTheme.background)
        }
        .buttonStyle(.plain)
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

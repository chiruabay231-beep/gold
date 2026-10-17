import SwiftUI
import BacktestKit

/// Strategy picker and signal list of the live market, shown in the Data tab.
struct LiveSignalsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveMarket.self) private var market

    var body: some View {
        @Bindable var market = market
        Section {
            Picker(selection: Binding(get: { market.strategyID }, set: { market.track(strategy: $0) })) {
                Text("Không theo dõi").tag(UUID?.none)
                ForEach(store.strategies) { strategy in
                    Text(strategy.name).tag(Optional(strategy.id))
                }
            } label: {
                Label("Chiến lược", systemImage: "bolt.fill")
            }
            Toggle(isOn: $market.notificationsEnabled) {
                Label("Thông báo khi có tín hiệu", systemImage: "bell")
            }
            .onChange(of: market.notificationsEnabled) { _, enabled in
                if enabled { LiveMarket.requestNotificationPermission() }
            }
            if let error = market.strategyError {
                ErrorText(message: error)
            } else if market.strategyID != nil, market.signals.isEmpty {
                Text("Chưa có tín hiệu trên \(market.scannedBarCount) nến gần nhất. Tín hiệu mới sẽ được báo khi nến đóng.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(market.signals.reversed().prefix(30)) { signal in
                LiveSignalRow(signal: signal, isLatest: signal.id == market.latestAlert?.id)
            }
        } header: {
            HStack {
                Text("Tín hiệu Live · \(LiveView.displayName(market.symbol)) \(LiveView.label(market.interval))")
                Spacer()
                Button("Mở biểu đồ") { store.selectedTab = .live }
                    .font(.caption)
            }
        } footer: {
            Text("Chiến lược chạy trên mỗi nến đã đóng của tab Live. Đổi mã và khung thời gian ở tab Live.")
        }
    }
}

struct LiveSignalRow: View {
    let signal: LiveSignal
    var isLatest = false

    static func color(for kind: LiveSignal.Kind) -> Color {
        switch kind {
        case .longEntry: return BinanceTheme.up
        case .shortEntry: return BinanceTheme.down
        case .longExit, .shortExit: return .secondary
        }
    }

    var body: some View {
        let decimals = CandleChart.decimals(for: signal.price)
        HStack(spacing: 10) {
            Text(signal.kind.label)
                .font(.subheadline.bold())
                .foregroundStyle(Self.color(for: signal.kind))
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(CandleChart.format(signal.price, decimals))
                Text(signal.time.formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let stop = signal.stop {
                    Text("SL \(CandleChart.format(stop, decimals))").foregroundStyle(BinanceTheme.down)
                }
                if let target = signal.target {
                    Text("TP \(CandleChart.format(target, decimals))").foregroundStyle(BinanceTheme.up)
                }
            }
            .font(.caption)
        }
        .font(.subheadline.monospacedDigit())
        .listRowBackground(isLatest ? BinanceTheme.yellow.opacity(0.12) : nil)
    }
}

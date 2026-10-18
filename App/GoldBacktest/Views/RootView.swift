import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            NavigationStack { LiveView() }
                .tabItem { Label("Live", systemImage: "waveform.path.ecg.rectangle") }
                .tag(AppTab.live)
            NavigationStack { TradePanelView() }
                .tabItem { Label("Giao dịch", systemImage: "briefcase") }
                .tag(AppTab.trade)
            NavigationStack { IndicatorListView() }
                .tabItem { Label("Chỉ báo", systemImage: "function") }
                .tag(AppTab.indicators)
            NavigationStack { StrategyListView() }
                .tabItem { Label("Chiến lược", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.strategies)
            NavigationStack { BacktestView() }
                .tabItem { Label("Backtest", systemImage: "play.circle") }
                .tag(AppTab.backtest)
        }
        .alert("Lỗi", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

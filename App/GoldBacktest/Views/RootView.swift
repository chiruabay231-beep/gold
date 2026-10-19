import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(NewsStore.self) private var news

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            NavigationStack { LiveView() }
                .tabItem { Label("Live", systemImage: "waveform.path.ecg.rectangle") }
                .tag(AppTab.live)
            NavigationStack { TradeRootView() }
                .tabItem { Label("Giao dịch", systemImage: "briefcase") }
                .tag(AppTab.trade)
            NavigationStack { IndicatorListView() }
                .tabItem { Label("Chỉ báo", systemImage: "function") }
                .tag(AppTab.indicators)
            NavigationStack { NewsView() }
                .tabItem { Label("Tin tức", systemImage: "newspaper") }
                .tag(AppTab.news)
            NavigationStack { BacktestView() }
                .tabItem { Label("Backtest", systemImage: "play.circle") }
                .tag(AppTab.backtest)
        }
        // Watches gold for sudden moves and their news while the app runs.
        .task { await news.monitor() }
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

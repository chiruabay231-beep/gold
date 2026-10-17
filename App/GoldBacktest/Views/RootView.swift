import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            NavigationStack { DatasetListView() }
                .tabItem { Label("Dữ liệu", systemImage: "chart.bar.xaxis") }
            NavigationStack { IndicatorListView() }
                .tabItem { Label("Chỉ báo", systemImage: "function") }
            NavigationStack { StrategyListView() }
                .tabItem { Label("Chiến lược", systemImage: "list.bullet.rectangle") }
            NavigationStack { BacktestView() }
                .tabItem { Label("Backtest", systemImage: "play.circle") }
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

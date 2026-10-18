import SwiftUI
import UserNotifications

@main
struct GoldBacktestApp: App {
    @State private var store = AppStore()
    @State private var market = LiveMarket()
    @State private var trader = PaperTrader()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        LiveMarket.requestNotificationPermission()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(market)
                .environment(trader)
                .onAppear {
                    let trader = trader
                    market.onPrice = { symbol, price, time in trader.update(symbol: symbol, price: price, time: time) }
                }
        }
    }
}

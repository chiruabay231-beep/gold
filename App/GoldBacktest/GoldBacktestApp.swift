import SwiftUI
import UserNotifications

@main
struct GoldBacktestApp: App {
    @State private var store = AppStore()
    @State private var market = LiveMarket()
    @State private var trader = PaperTrader()
    @State private var bot = BotController()
    @State private var news = NewsStore()
    @State private var mt5Trader = MT5Trader()

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
                .environment(bot)
                .environment(news)
                .environment(mt5Trader)
                .onAppear {
                    let trader = trader
                    market.onPrice = { symbol, bid, ask, time in trader.update(symbol: symbol, bid: bid, ask: ask, time: time) }
                    market.onBarClose = { symbol, candles in trader.barClosed(symbol: symbol, candles: candles) }
                    let bot = bot
                    bot.attach(market: market, trader: trader)
                    market.onSignals = { signals, symbol in bot.handle(signals: signals, symbol: symbol) }
                }
        }
    }
}

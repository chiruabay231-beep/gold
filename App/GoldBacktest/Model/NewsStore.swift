import Foundation
import Observation
import UserNotifications
import BacktestKit

/// Economic calendar and gold headlines for the News tab, refreshed at most
/// every 15 minutes (the calendar feed asks clients not to poll it often).
@MainActor
@Observable
final class NewsStore {
    private(set) var events: [EconomicEvent] = []
    private(set) var headlines: [NewsHeadline] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var updatedAt: Date?

    @ObservationIgnored private var headlinesLanguage: Bool?

    /// Market-moving headlines of the last day (geopolitics, tariffs, Fed…), newest first.
    private(set) var breaking: [TaggedHeadline] = []
    /// Sudden XAUUSD moves of the last hours with the news around them, newest first.
    private(set) var moves: [MoveExplanation] = []
    private(set) var movesUpdatedAt: Date?
    private(set) var movesError: String?
    @ObservationIgnored private var movesLoading = false
    /// Moves already notified, and whether that notification named a cause.
    @ObservationIgnored private var notifiedMoves: [Date: Bool] = [:]

    static let moveAlertsKey = "news.moveAlerts"

    static let reminderKey = "news.remind"
    static let reminderPrefix = "news-"

    func refresh(vietnamese: Bool, force: Bool = false) async {
        let stale = updatedAt.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true
        guard force || stale || headlinesLanguage != vietnamese, !loading else { return }
        loading = true
        defer { loading = false }
        var problems: [String] = []
        do {
            events = try MarketNews.parseCalendar(try await MarketNews.load(MarketNews.calendarURL))
        } catch {
            problems.append("lịch kinh tế")
        }
        do {
            headlines = MarketNews.parseRSS(try await MarketNews.load(MarketNews.headlinesURL(vietnamese: vietnamese)))
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            headlinesLanguage = vietnamese
        } catch {
            problems.append("tin tức")
        }
        error = problems.isEmpty ? nil : "Không tải được \(problems.joined(separator: " và ")). Kéo xuống để thử lại."
        if problems.isEmpty { updatedAt = Date() }
        if UserDefaults.standard.bool(forKey: Self.reminderKey) { scheduleReminders() }
    }

    /// Re-checks gold's last 12 hours for sudden moves and the news behind them
    /// every 2 minutes while the app runs.
    func monitor() async {
        while !Task.isCancelled {
            await refreshMoves(vietnamese: UserDefaults.standard.bool(forKey: "news.vietnamese"))
            try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
        }
    }

    func refreshMoves(vietnamese: Bool, force: Bool = false) async {
        let stale = movesUpdatedAt.map { Date().timeIntervalSince($0) > 90 } ?? true
        guard force || stale, !movesLoading else { return }
        movesLoading = true
        defer { movesLoading = false }
        // Gold 1-minute bars (Binance Futures XAUUSDT tracks XAUUSD) and the news feeds, in parallel.
        async let bars = BinanceClient.withFallback(market: .futures) { client in
            try await client.fetchCandles(symbol: "XAUUSDT", interval: .m1, count: 720)
        }
        let urls = MarketNews.breakingURLs(vietnamese: vietnamese)
        let feeds = await withTaskGroup(of: [NewsHeadline].self) { group -> [NewsHeadline] in
            for url in urls {
                group.addTask { (try? MarketNews.parseRSS(await MarketNews.load(url))) ?? [] }
            }
            var all: [NewsHeadline] = []
            for await items in group { all += items }
            return all
        }
        // One copy of each story, last 24 hours, newest first.
        var seen = Set<String>()
        let dayAgo = Date().addingTimeInterval(-86_400)
        let merged = (feeds + headlines)
            .filter { ($0.date ?? .distantPast) > dayAgo }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .filter { seen.insert(Self.storyKey($0.title)).inserted }
        breaking = merged.map { TaggedHeadline(headline: $0, category: NewsCategory.classify($0.title)) }
        do {
            let candles = try await bars
            let spikes = MarketMoves.spikes(candles)
            moves = Array(MarketMoves.explain(spikes, events: MarketNews.goldEvents(events, currencies: []),
                                              headlines: merged).reversed())
            movesError = nil
            movesUpdatedAt = Date()
            notifyNewMoves()
        } catch {
            movesError = "Không tải được giá vàng (Binance Futures) để dò biến động."
        }
    }

    /// Titles differ by the outlet suffix ("… - Reuters"); compare the start.
    private static func storyKey(_ title: String) -> String {
        String(title.lowercased().split(separator: " - ").first ?? "").prefix(80).description
    }

    private func notifyNewMoves() {
        guard UserDefaults.standard.bool(forKey: Self.moveAlertsKey) else { return }
        for move in moves where move.spike.end > Date().addingTimeInterval(-20 * 60) {
            let hasCause = move.cause != nil
            // Once when found, and again if the reason turns up later.
            if let notified = notifiedMoves[move.id], notified || !hasCause { continue }
            let firstTime = notifiedMoves[move.id] == nil
            notifiedMoves[move.id] = hasCause
            let content = UNMutableNotificationContent()
            content.title = firstTime ? "⚡️ " + Self.moveTitle(move.spike) : "Lý do: " + Self.moveTitle(move.spike)
            content.body = Self.causeText(move)
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "move-\(move.id.timeIntervalSince1970)-\(hasCause)",
                                                                         content: content, trigger: nil))
        }
    }

    static func moveTitle(_ spike: PriceSpike) -> String {
        let minutes = max(1, Int(spike.end.timeIntervalSince(spike.start) / 60))
        return "Vàng \(spike.isUp ? "tăng" : "giảm") mạnh \(String(format: "%+.1f$ (%+.2f%%)", spike.change, spike.percent)) trong \(minutes) phút"
    }

    /// One line on why gold moved, for notifications and the list.
    static func causeText(_ move: MoveExplanation) -> String {
        if let event = move.events.first {
            return "📊 Tin kinh tế: \(event.country) \(event.title)"
        }
        if let top = move.headlines.first, let category = top.category {
            return "\(category.symbol) \(category.title): \(top.headline.title)"
        }
        return "Chưa thấy tin liên quan: có thể do kỹ thuật (quét thanh khoản, chốt lời, lệnh lớn) hoặc tin chưa kịp lên báo."
    }

    /// Next high-impact USD event that hasn't happened yet.
    var nextRedEvent: EconomicEvent? {
        MarketNews.goldEvents(events, minimum: .high).first { $0.date > Date() }
    }

    /// Notifications 15 minutes before each upcoming red USD event this week.
    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        let upcoming = MarketNews.goldEvents(events, minimum: .high).filter { $0.date.timeIntervalSinceNow > 15 * 60 }
        let prefix = Self.reminderPrefix
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for event in upcoming {
                let content = UNMutableNotificationContent()
                content.title = "🔴 15 phút nữa: \(event.title)"
                content.body = "\(event.country) · Dự báo \(event.forecast.isEmpty ? "–" : event.forecast) · Trước \(event.previous.isEmpty ? "–" : event.previous). Cẩn thận biến động XAUUSD."
                content.sound = .default
                let fire = event.date.addingTimeInterval(-15 * 60)
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: prefix + event.id, content: content, trigger: trigger))
            }
        }
    }

    func cancelReminders() {
        let center = UNUserNotificationCenter.current()
        let prefix = Self.reminderPrefix
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }
}

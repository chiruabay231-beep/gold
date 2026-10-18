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

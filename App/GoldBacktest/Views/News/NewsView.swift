import SwiftUI
import BacktestKit

/// The News tab: this week's economic calendar (red / orange USD events
/// that move XAUUSD) and today's gold headlines.
struct NewsView: View {
    @State private var news = NewsStore()

    enum Page: String, CaseIterable, Identifiable {
        case calendar = "Lịch kinh tế", headlines = "Tin vàng"
        var id: String { rawValue }
    }

    @State private var page = Page.calendar
    @AppStorage("news.redOnly") private var redOnly = false
    @AppStorage("news.usdOnly") private var usdOnly = true
    @AppStorage("news.vietnamese") private var vietnamese = false
    @AppStorage(NewsStore.reminderKey) private var remind = false

    var body: some View {
        List {
            nextEventSection
            Section {
                Picker("Mục", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
            if let error = news.error {
                Section { Label(error, systemImage: "wifi.exclamationmark").foregroundColor(.orange) }
            }
            switch page {
            case .calendar: calendar
            case .headlines: headlineList
            }
        }
        .navigationTitle("Tin tức")
        .refreshable { await news.refresh(vietnamese: vietnamese, force: true) }
        .task { await news.refresh(vietnamese: vietnamese) }
        .onChange(of: vietnamese) { _, value in Task { await news.refresh(vietnamese: value, force: true) } }
        .onChange(of: remind) { _, on in
            if on {
                LiveMarket.requestNotificationPermission()
                news.scheduleReminders()
            } else {
                news.cancelReminders()
            }
        }
        .overlay { if news.loading && news.events.isEmpty && news.headlines.isEmpty { ProgressView() } }
    }

    // MARK: - Next red event

    @ViewBuilder
    private var nextEventSection: some View {
        if let event = news.nextRedEvent {
            Section("Tin đỏ USD sắp tới") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        impactBadge(.high)
                        Text(event.title).font(.headline)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Còn \(Self.countdown(event.date.timeIntervalSince(context.date))) · \(event.date.formatted(.dateTime.weekday(.wide).hour().minute()))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.red)
                    }
                    Text("Dự báo \(dash(event.forecast)) · Trước \(dash(event.previous))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Báo trước tin đỏ 15 phút", isOn: $remind)
            }
        }
    }

    // MARK: - Calendar

    private var filteredEvents: [EconomicEvent] {
        MarketNews.goldEvents(news.events, minimum: redOnly ? .high : .medium, currencies: usdOnly ? ["USD"] : [])
    }

    @ViewBuilder
    private var calendar: some View {
        Section {
            Toggle("Chỉ tin đỏ (mạnh nhất)", isOn: $redOnly)
            Toggle("Chỉ tin USD (ảnh hưởng vàng)", isOn: $usdOnly)
        } footer: {
            Text("Giờ hiển thị theo giờ trên điện thoại. 🔴 tác động mạnh · 🟠 trung bình. Nguồn: lịch Forex Factory tuần này.")
        }
        let days = Dictionary(grouping: filteredEvents) { Calendar.current.startOfDay(for: $0.date) }
        if days.isEmpty, !news.loading {
            Section { Text("Không có tin phù hợp trong tuần này.").foregroundColor(.secondary) }
        }
        ForEach(days.keys.sorted(), id: \.self) { day in
            Section(day.formatted(.dateTime.weekday(.wide).day().month())) {
                ForEach(days[day] ?? []) { event in eventRow(event) }
            }
        }
    }

    private func eventRow(_ event: EconomicEvent) -> some View {
        let past = event.date < Date()
        return HStack(alignment: .top, spacing: 10) {
            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .frame(width: 52, alignment: .leading)
            impactBadge(event.impact)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.country) · \(event.title)").font(.subheadline.weight(.semibold))
                Text("Dự báo \(dash(event.forecast)) · Trước \(dash(event.previous))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .opacity(past ? 0.45 : 1)
    }

    private func impactBadge(_ impact: EconomicEvent.Impact) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(impact == .high ? Color.red : (impact == .medium ? Color.orange : Color.yellow))
            .frame(width: 10, height: 18)
    }

    // MARK: - Headlines

    @ViewBuilder
    private var headlineList: some View {
        Section {
            Picker("Ngôn ngữ", selection: $vietnamese) {
                Text("Tiếng Anh").tag(false)
                Text("Tiếng Việt").tag(true)
            }
        } footer: {
            if let updated = news.updatedAt {
                Text("Cập nhật \(updated.formatted(date: .omitted, time: .shortened)) · Google News, 2 ngày gần nhất. Kéo xuống để làm mới.")
            }
        }
        Section {
            if news.headlines.isEmpty, !news.loading {
                Text("Chưa có tin.").foregroundColor(.secondary)
            }
            ForEach(news.headlines.prefix(60)) { item in
                if let url = URL(string: item.link) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline).foregroundColor(.primary).multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text(item.source).fontWeight(.semibold)
                                if let date = item.date { Text(date, style: .relative) + Text(" trước") }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func dash(_ text: String) -> String { text.isEmpty ? "–" : text }

    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let days = s / 86_400, hours = (s % 86_400) / 3600, minutes = (s % 3600) / 60, secs = s % 60
        if days > 0 { return "\(days) ngày \(hours) giờ" }
        if hours > 0 { return String(format: "%d giờ %02d phút", hours, minutes) }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

import SwiftUI
import BacktestKit

/// The News tab: this week's economic calendar (red / orange USD events
/// that move XAUUSD) and today's gold headlines.
struct NewsView: View {
    @Environment(NewsStore.self) private var news

    enum Page: String, CaseIterable, Identifiable {
        case moves = "Biến động", calendar = "Lịch kinh tế", headlines = "Tin vàng"
        var id: String { rawValue }
    }

    @AppStorage("news.page") private var page = Page.moves
    @AppStorage(NewsStore.moveAlertsKey) private var moveAlerts = false
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
            case .moves: movesPage
            case .calendar: calendar
            case .headlines: headlineList
            }
        }
        .navigationTitle("Tin tức")
        .refreshable {
            await news.refresh(vietnamese: vietnamese, force: true)
            await news.refreshMoves(vietnamese: vietnamese, force: true)
        }
        .task {
            await news.refresh(vietnamese: vietnamese)
            await news.refreshMoves(vietnamese: vietnamese)
        }
        .onChange(of: moveAlerts) { _, on in if on { LiveMarket.requestNotificationPermission() } }
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

    // MARK: - Sudden moves and why

    @ViewBuilder
    private var movesPage: some View {
        Section {
            if let error = news.movesError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundColor(.orange).font(.footnote)
            }
            if news.moves.isEmpty {
                Text(news.movesUpdatedAt == nil ? "Đang dò biến động…" : "12 giờ qua không có cú tăng/giảm đột ngột bất thường.")
                    .foregroundColor(.secondary)
            }
            ForEach(news.moves) { move in moveRow(move) }
            Toggle("Thông báo khi vàng chạy mạnh", isOn: $moveAlerts)
        } header: {
            Text("Biến động mạnh XAUUSD · 12 giờ qua")
        } footer: {
            Text("Dò mỗi 2 phút trên nến 1 phút XAUUSDT (Binance Futures): cú chạy trong vài phút lớn gấp 4 lần bình thường và trên 0,2%. Lý do ghép từ lịch kinh tế và tin tức quanh thời điểm đó (Google News). Đây là gợi ý tự động: tin trên báo thường chậm vài phút đến cả giờ, nên lý do có thể hiện sau.\(news.movesUpdatedAt.map { " Cập nhật " + $0.formatted(date: .omitted, time: .shortened) + "." } ?? "")")
        }
        Section {
            let tagged = news.breaking.filter { $0.category != nil }
            if tagged.isEmpty {
                Text(news.movesUpdatedAt == nil ? "Đang tải…" : "Chưa có tin nổi bật.").foregroundColor(.secondary)
            }
            ForEach(tagged.prefix(60)) { item in headlineRow(item.headline, category: item.category) }
        } header: {
            Text("Tin nóng ảnh hưởng vàng · 24 giờ")
        } footer: {
            Text("⚔️ địa chính trị/chiến sự · 🚢 thuế quan/trừng phạt · 🏦 Fed, lãi suất · 📊 số liệu kinh tế · 🏛️ chính trị Mỹ · 💵 USD, lợi suất · 📉 bán tháo, khủng hoảng · 🪙 dòng tiền vàng.")
        }
    }

    private func moveRow(_ move: MoveExplanation) -> some View {
        let spike = move.spike
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: spike.isUp ? "arrow.up.right" : "arrow.down.right")
                    .foregroundColor(spike.isUp ? .green : .red)
                Text(String(format: "%+.1f$ (%+.2f%%)", spike.change, spike.percent))
                    .font(.headline.monospacedDigit())
                    .foregroundColor(spike.isUp ? .green : .red)
                Spacer()
                Text("\(spike.start.formatted(date: .omitted, time: .shortened))–\(spike.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Text(NewsStore.causeText(move))
                .font(.subheadline.weight(.medium))
                .foregroundColor(move.cause == nil ? .secondary : .primary)
            ForEach(move.headlines.dropFirst(move.events.isEmpty ? 1 : 0).prefix(3)) { item in
                headlineRow(item.headline, category: item.category, compact: true)
            }
            if move.events.isEmpty, let top = move.headlines.first, let url = URL(string: top.headline.link) {
                Link(destination: url) {
                    Text("\(top.headline.source) · \(top.headline.date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "") · Đọc tin")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func headlineRow(_ item: NewsHeadline, category: NewsCategory?, compact: Bool = false) -> some View {
        if let url = URL(string: item.link) {
            Link(destination: url) {
                HStack(alignment: .top, spacing: 8) {
                    if let category {
                        Text(category.symbol).font(compact ? .caption : .body)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(compact ? .caption : .subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(compact ? 2 : 4)
                        HStack(spacing: 6) {
                            if let category, !compact { Text(category.title) }
                            Text(item.source).fontWeight(.semibold)
                            if let date = item.date {
                                Text(date.formatted(date: .omitted, time: .shortened))
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
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

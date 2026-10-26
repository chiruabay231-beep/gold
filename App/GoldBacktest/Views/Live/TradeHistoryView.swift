import SwiftUI
import BacktestKit

/// History like MT5's: closed positions, orders and deals of a period, with
/// the period's profit, deposits, swap, commission and balance.
struct TradeHistory {
    struct Position: Decodable, Identifiable {
        var ticket: Int
        var symbol: String
        var side: String
        var lots: Double
        var entry: Double
        var exit: Double
        var openTime: Double
        var closeTime: Double
        var profit: Double
        var reason: String?
        /// SL / TP when it closed, and when it opened (moved if they differ).
        var stop: Double?
        var target: Double?
        var stopOpen: Double?
        var targetOpen: Double?
        var swap: Double?
        var commission: Double?
        var comment: String?
        /// Price digits of the symbol (points = price × 10^digits).
        var digits: Int?
        var description: String?
        var id: Int { ticket }
    }

    struct Order: Decodable, Identifiable {
        var ticket: Int
        var symbol: String
        /// buy, sell, buy limit, sell limit, buy stop, sell stop
        var type: String
        var lots: Double
        var filled: Double
        var price: Double
        var state: String
        var time: Double
        var doneTime: Double
        var id: Int { ticket }
    }

    struct Deal: Decodable, Identifiable {
        var ticket: Int
        var symbol: String
        /// buy, sell, balance
        var type: String
        var entry: String
        var lots: Double
        var price: Double
        var profit: Double
        var swap: Double
        var commission: Double
        var time: Double
        var id: Int { ticket }
    }

    struct Summary: Decodable {
        var profit: Double
        var deposit: Double
        var withdrawal: Double
        var swap: Double
        var commission: Double
        var balance: Double?
        var currency: String?
    }

    var positions: [Position]
    var orders: [Order]
    var deals: [Deal]
    var summary: Summary

    /// The demo account's closed trades as an MT5 history.
    @MainActor
    static func demo(_ account: PaperAccount, from: Date, to: Date) -> TradeHistory {
        let trades = account.history.filter { $0.closeTime >= from && $0.closeTime <= to }
        var positions: [Position] = [], orders: [Order] = [], deals: [Deal] = []
        for (k, t) in trades.enumerated() {
            let symbol = PaperTrader.bareSymbol(t.symbol)
            let side = t.side == .long ? "buy" : "sell"
            let other = t.side == .long ? "sell" : "buy"
            let open = t.openTime.timeIntervalSince1970, close = t.closeTime.timeIntervalSince1970
            positions.append(Position(ticket: k, symbol: symbol, side: t.side.rawValue, lots: t.lots, entry: t.entryPrice,
                                      exit: t.exitPrice, openTime: open, closeTime: close, profit: t.profit,
                                      reason: t.reason.rawValue, stop: t.stop, target: t.target,
                                      stopOpen: t.initialStop, targetOpen: nil, swap: nil, commission: nil,
                                      comment: nil, digits: nil, description: nil))
            orders.append(Order(ticket: k * 2, symbol: symbol, type: side, lots: t.lots, filled: t.lots, price: t.entryPrice,
                                state: "filled", time: open, doneTime: open))
            orders.append(Order(ticket: k * 2 + 1, symbol: symbol, type: other, lots: t.lots, filled: t.lots, price: t.exitPrice,
                                state: "filled", time: close, doneTime: close))
            deals.append(Deal(ticket: k * 2, symbol: symbol, type: side, entry: "in", lots: t.lots, price: t.entryPrice,
                              profit: 0, swap: 0, commission: 0, time: open))
            deals.append(Deal(ticket: k * 2 + 1, symbol: symbol, type: other, entry: "out", lots: t.lots, price: t.exitPrice,
                              profit: t.profit, swap: 0, commission: 0, time: close))
        }
        return TradeHistory(positions: positions, orders: orders, deals: deals,
                            summary: Summary(profit: trades.reduce(0) { $0 + $1.profit }, deposit: 0, withdrawal: 0, swap: 0,
                                             commission: 0, balance: account.balance, currency: "USD"))
    }
}

extension TradeHistory: Decodable {}

extension RemoteBotClient {
    func mt5History(from: Date, to: Date) async throws -> TradeHistory {
        let path = "/mt5/history?from=\(Int(from.timeIntervalSince1970))&to=\(Int(to.timeIntervalSince1970))"
        return try JSONDecoder().decode(TradeHistory.self, from: await send(path, timeout: 30))
    }
}

struct TradeHistoryView: View {
    enum Source { case demo, mt5 }

    enum Page: String, CaseIterable {
        case positions = "Vị thế", orders = "Lệnh", deals = "Giao dịch"
    }

    enum Period: String, CaseIterable, Identifiable {
        case today = "Hôm nay", yesterday = "Hôm qua", week = "Tuần trước", month = "Tháng trước", threeMonths = "3 tháng trước", custom = "Tuỳ chỉnh"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable {
        case newest = "Mới nhất", oldest = "Cũ nhất", symbol = "Theo mã", profit = "Theo lãi/lỗ"
    }

    let source: Source
    /// Inside another list (the MT5 account page): the bar is a section header and
    /// the page opens on today.
    var embedded = false
    /// Changes when positions close, to reload.
    var reloadKey = 0

    @Environment(PaperTrader.self) private var trader
    @AppStorage("history.page") private var pageName = Page.positions.rawValue
    @AppStorage("history.period") private var periodName = Period.today.rawValue
    @AppStorage("history.sort") private var sortName = Sort.newest.rawValue
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var showCustom = false
    @State private var history: TradeHistory?
    @State private var error: String?
    @State private var loading = false
    /// A closed position tapped: its details with the SL/TP it had.
    @State private var selected: TradeHistory.Position?
    /// Lots traded today, yesterday and over the whole account, whatever period is shown.
    @State private var lotTotals: LotTotals?

    struct LotTotals {
        struct Part { var lots = 0.0; var count = 0 }
        var today = Part(), yesterday = Part(), all = Part()
        var at = Date()

        init(closeTimes: [(time: Double, lots: Double)]) {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date()).timeIntervalSince1970
            let yesterday = today - 86400
            for item in closeTimes {
                all.lots += item.lots; all.count += 1
                if item.time >= today { self.today.lots += item.lots; self.today.count += 1 }
                else if item.time >= yesterday { self.yesterday.lots += item.lots; self.yesterday.count += 1 }
            }
        }
    }
    /// The whole account's history is long: read again at most once a minute (shared by every list).
    @MainActor private static var cachedTotals: LotTotals?

    private var page: Page { Page(rawValue: pageName) ?? .positions }
    private var period: Period { Period(rawValue: periodName) ?? .week }
    private var sort: Sort { Sort(rawValue: sortName) ?? .newest }

    private var range: (from: Date, to: Date) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        switch period {
        case .today: return (today, now)
        case .yesterday: return (calendar.date(byAdding: .day, value: -1, to: today) ?? today, today)
        case .week: return (calendar.date(byAdding: .day, value: -7, to: today) ?? today, now)
        case .month: return (calendar.date(byAdding: .month, value: -1, to: today) ?? today, now)
        case .threeMonths: return (calendar.date(byAdding: .month, value: -3, to: today) ?? today, now)
        case .custom: return (calendar.startOfDay(for: customFrom),
                              calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customTo)) ?? customTo)
        }
    }

    private var loadKey: String {
        "\(periodName)|\(customFrom.timeIntervalSince1970)|\(customTo.timeIntervalSince1970)|\(reloadKey)"
    }

    var body: some View {
        if embedded {
            Section {
                content
            } header: {
                topBar
                    .textCase(nil)
                    .padding(.horizontal, -16)
                    .task(id: loadKey) { await load() }
                    .onAppear { periodName = Period.today.rawValue }
                    .sheet(isPresented: $showCustom) { customSheet }
            }
            if let history { summary(history) }
        } else {
            VStack(spacing: 0) {
                topBar
                List {
                    content
                    if let history { summary(history) }
                }
                .listStyle(.plain)
            }
            .navigationTitle(source == .mt5 ? "Lịch sử" : "Lịch sử demo")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: loadKey) { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showCustom) { customSheet }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            Text(error).font(.footnote).foregroundColor(.orange)
        }
        if page == .positions, let lotTotals {
            lotStrip(lotTotals)
        }
        if let history {
            rows(history)
        } else if loading {
            HStack { Spacer(); ProgressView(); Spacer() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        topBarRow
            .background {
                // Details of a tapped closed position (here: one sheet for the whole list).
                Color.clear.sheet(item: $selected) { p in
                    ClosedPositionDetail(position: p, name: Self.name(p.symbol), fromMT5: source == .mt5)
                }
            }
    }

    private var topBarRow: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Sắp xếp", selection: $sortName) {
                    ForEach(Sort.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
            } label: {
                circleIcon("arrow.up.arrow.down")
            }
            HStack(spacing: 2) {
                ForEach(Page.allCases, id: \.rawValue) { p in
                    Button { pageName = p.rawValue } label: {
                        Text(p.rawValue)
                            .font(.system(size: 15, weight: page == p ? .semibold : .regular))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(page == p ? Color(.systemGray5) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(.secondarySystemBackground), in: Capsule())
            Menu {
                Picker("Khoảng thời gian", selection: Binding(get: { periodName }, set: { value in
                    periodName = value
                    if value == Period.custom.rawValue { showCustom = true }
                })) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            } label: {
                circleIcon("clock")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Text(periodText).font(.caption2).foregroundColor(.secondary).offset(y: 10)
        }
        .padding(.bottom, 10)
    }

    private var periodText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return "\(f.string(from: range.from)) – \(f.string(from: range.to))"
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.primary)
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemBackground), in: Circle())
    }

    private var customSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Từ ngày", selection: $customFrom, displayedComponents: .date)
                DatePicker("Đến ngày", selection: $customTo, in: customFrom..., displayedComponents: .date)
            }
            .navigationTitle("Tuỳ chỉnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { showCustom = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Rows

    @ViewBuilder
    private func rows(_ h: TradeHistory) -> some View {
        switch page {
        case .positions:
            let items = sorted(h.positions, time: \.closeTime, symbol: \.symbol, profit: { $0.profit })
            if items.isEmpty { empty }
            ForEach(items) { p in
                Button { selected = p } label: {
                    HistoryRow(symbol: Self.name(p.symbol), side: p.side == "long" ? "buy" : "sell", lots: p.lots,
                               detail: "\(Self.price(p.entry)) → \(Self.price(p.exit))",
                               value: String(format: "%.2f", p.profit), valueColor: Self.color(p.profit),
                               time: p.closeTime, marker: Self.marker(p.reason))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

        case .orders:
            let items = sorted(h.orders, time: \.time, symbol: \.symbol, profit: { _ in 0 })
            if items.isEmpty { empty }
            ForEach(items) { o in
                HistoryRow(symbol: Self.name(o.symbol), side: o.type, lots: o.lots,
                           detail: "\(Self.lots(o.filled)) / \(Self.lots(o.lots)) at \(o.price > 0 ? Self.price(o.price) : "market")",
                           value: Self.state(o.state), valueColor: o.state == "filled" ? .primary : .secondary,
                           time: o.doneTime)
            }
        case .deals:
            let items = sorted(h.deals, time: \.time, symbol: \.symbol, profit: { $0.profit })
            if items.isEmpty { empty }
            ForEach(items) { d in
                if d.type == "balance" {
                    HistoryRow(symbol: "Balance", side: "", lots: nil, detail: d.profit >= 0 ? "Nạp tiền" : "Rút tiền",
                               value: String(format: "%.2f", d.profit), valueColor: Self.color(d.profit), time: d.time)
                } else {
                    HistoryRow(symbol: Self.name(d.symbol), side: "\(d.type), \(d.entry)", lots: d.lots,
                               detail: "at \(Self.price(d.price))",
                               value: d.entry == "in" ? "" : String(format: "%.2f", d.profit),
                               valueColor: Self.color(d.profit), time: d.time)
                }
            }
        }
    }

    /// The bar at the left of a closed position: red when the SL closed it, green for
    /// the TP, grey when it was closed by hand (or by the bot).
    static func marker(_ reason: String?) -> Color {
        switch reason {
        case "stop": return HistoryRow.red
        case "target": return Color(red: 0.12, green: 0.66, blue: 0.36)
        default: return Color.secondary.opacity(0.35)
        }
    }

    private var empty: some View {
        Text("Không có lệnh trong khoảng này").foregroundColor(.secondary)
    }

    private func sorted<T>(_ items: [T], time: KeyPath<T, Double>, symbol: KeyPath<T, String>,
                           profit: (T) -> Double) -> [T] {
        switch sort {
        case .newest: return items.sorted { $0[keyPath: time] > $1[keyPath: time] }
        case .oldest: return items.sorted { $0[keyPath: time] < $1[keyPath: time] }
        case .symbol: return items.sorted { ($0[keyPath: symbol], $0[keyPath: time]) < ($1[keyPath: symbol], $1[keyPath: time]) }
        case .profit: return items.sorted { profit($0) > profit($1) }
        }
    }

    /// "Hôm nay 0.10 lot · Hôm qua 0.23 lot · Tất cả 12.40 lot", with the number of positions under each.
    private func lotStrip(_ t: LotTotals) -> some View {
        HStack(spacing: 8) {
            lotCell("Hôm nay", t.today, highlight: false)
            lotCell("Hôm qua", t.yesterday, highlight: false)
            lotCell("Tất cả", t.all, highlight: true)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .listRowSeparator(.hidden)
    }

    private func lotCell(_ title: String, _ part: LotTotals.Part, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Self.lotsText(part.lots))
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundColor(highlight ? Color(red: 0.8, green: 0.6, blue: 0.15) : .primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("lot").font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            }
            Text("\(part.count) lệnh").font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if highlight {
                RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.8, green: 0.6, blue: 0.15).opacity(0.5), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func summary(_ h: TradeHistory) -> some View {
        let s = h.summary
        Section {
            HStack {
                Text("Khối lượng").foregroundColor(.secondary)
                Spacer()
                Text("\(Self.lotsText(h.positions.reduce(0) { $0 + $1.lots })) lot · \(h.positions.count) lệnh")
                    .font(.body.monospacedDigit())
            }
            summaryRow("Lợi nhuận", s.profit)
            if source == .mt5 {
                summaryRow("Nạp tiền", s.deposit)
                summaryRow("Rút tiền", s.withdrawal)
                summaryRow("Phí qua đêm (swap)", s.swap)
                summaryRow("Hoa hồng", s.commission)
            }
            if let balance = s.balance { summaryRow("Số dư", balance, plain: true) }
        }
    }

    private func summaryRow(_ title: String, _ value: Double, plain: Bool = false) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(Self.money(value)).font(.body.monospacedDigit()).foregroundColor(plain ? .primary : Self.color(value))
        }
    }

    // MARK: - Data

    private func load() async {
        let (from, to) = range
        switch source {
        case .demo:
            history = .demo(trader.account, from: from, to: to)
            lotTotals = LotTotals(closeTimes: trader.account.history.map { ($0.closeTime.timeIntervalSince1970, $0.lots) })
        case .mt5:
            guard let client = RemoteBotSettings.client() else {
                error = "Chưa kết nối máy chủ VPS"
                return
            }
            loading = true
            defer { loading = false }
            do {
                history = try await client.mt5History(from: from, to: to)
                error = nil
                await loadLotTotals(client)
            } catch {
                self.error = ServerUpdate.isOutdated(error)
                    ? "Máy chủ VPS chưa có lịch sử theo ngày: vào Bot trên VPS → Cập nhật máy chủ VPS."
                    : error.localizedDescription
            }
        }
    }

    private func loadLotTotals(_ client: RemoteBotClient) async {
        if let cached = Self.cachedTotals, Date().timeIntervalSince(cached.at) < 60, reloadKey == lastTotalsKey {
            lotTotals = cached
            return
        }
        lotTotals = Self.cachedTotals
        let start = Date(timeIntervalSince1970: 1_262_304_000) // 2010: the whole account
        guard let all = try? await client.mt5History(from: start, to: Date().addingTimeInterval(60)) else { return }
        let totals = LotTotals(closeTimes: all.positions.map { ($0.closeTime, $0.lots) })
        Self.cachedTotals = totals
        lastTotalsKey = reloadKey
        lotTotals = totals
    }

    /// The reload key the cached totals were read for: a position closing reads them again.
    @MainActor private static var totalsKey = -1
    private var lastTotalsKey: Int {
        get { Self.totalsKey }
        nonmutating set { Self.totalsKey = newValue }
    }

    // MARK: - Formatting

    /// Lots with two decimals, like MT5 ("0.15", "12.40").
    static func lotsText(_ value: Double) -> String { String(format: "%.2f", value) }

    static func name(_ symbol: String) -> String { symbol.isEmpty ? "—" : symbol }
    static func price(_ value: Double) -> String { CandleChart.format(value, CandleChart.decimals(for: value)) }
    static func lots(_ value: Double) -> String { String(format: "%g", value) }
    static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
    static func color(_ value: Double) -> Color { value < 0 ? OrderRow.lossColor : (value > 0 ? HistoryRow.blue : .primary) }
    static func state(_ state: String) -> String {
        switch state {
        case "filled": return "filled"
        case "canceled": return "canceled"
        case "expired": return "expired"
        case "rejected": return "rejected"
        default: return state
        }
    }
}

/// One row of the history in MT5's look: "XAUUSD sell 0.1", prices under it,
/// the profit (blue / red) and the time on the right.
struct HistoryRow: View {
    let symbol: String
    let side: String
    let lots: Double?
    let detail: String
    let value: String
    let valueColor: Color
    let time: Double
    /// Bar at the left (closed positions: SL red, TP green).
    var marker: Color? = nil

    static let blue = Color(red: 0.16, green: 0.42, blue: 0.95)
    static let red = Color(red: 0.86, green: 0.25, blue: 0.2)

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            if let marker {
                RoundedRectangle(cornerRadius: 2)
                    .fill(marker)
                    .frame(width: 4)
                    .padding(.vertical, 2)
            }
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(symbol)
                        .font(.system(size: 19, weight: .bold).width(.condensed))
                        .foregroundColor(.primary)
                    if !side.isEmpty {
                        Text(side + (lots.map { " " + TradeHistoryView.lots($0) } ?? ""))
                            .font(.system(size: 14))
                            .foregroundColor(side.hasPrefix("buy") ? Self.blue : Self.red)
                    }
                }
                .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundColor(valueColor)
            }
            HStack {
                Text(detail)
                Spacer()
                Text(Self.formatter.string(from: Date(timeIntervalSince1970: time)))
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }
}

/// A closed position like MT5's card: prices, Δ in points, times, SL / TP (the SL
/// that fired and the slippage against it), swap, fees, comment; then Biểu đồ / Giao dịch.
struct ClosedPositionDetail: View {
    let position: TradeHistory.Position
    let name: String
    /// An MT5 account trade (the chart opens the MT5 symbol).
    var fromMT5 = false

    @Environment(\.dismiss) private var dismiss
    @Environment(LiveMarket.self) private var market
    @Environment(AppStore.self) private var store

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return f
    }()

    private var p: TradeHistory.Position { position }
    private var buy: Bool { p.side == "long" }
    private var sign: Double { buy ? 1 : -1 }
    private var digits: Int { p.digits ?? CandleChart.decimals(for: p.entry) }
    private var pointSize: Double { pow(10, -Double(digits)) }

    var body: some View {
        VStack(spacing: 10) {
            card
            VStack(spacing: 0) {
                actionButton("Biểu đồ") { openChart(trade: false) }
                Divider()
                actionButton("Giao dịch") { openChart(trade: true) }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .presentationDetents([.height(p.reason == "stop" || p.reason == "target" ? 550 : 500)])
        .presentationBackground(.clear)
    }

    private var card: some View {
        let profitColor = p.profit >= 0 ? HistoryRow.blue : HistoryRow.red
        let delta = (p.exit - p.entry) * sign
        return VStack(alignment: .leading, spacing: 0) {
            // Header tinted by the result, like MT5.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 19, weight: .bold).width(.condensed))
                        Text("\(buy ? "buy" : "sell") \(TradeHistoryView.lots(p.lots))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(buy ? HistoryRow.blue : HistoryRow.red)
                    }
                    if let description = p.description, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text("#\(p.ticket)").font(.footnote.monospacedDigit()).foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((p.profit >= 0 ? HistoryRow.blue : HistoryRow.red).opacity(0.1))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(price(p.entry)) → \(price(p.exit))").font(.system(size: 19).monospacedDigit())
                    Spacer()
                    Text(String(format: "%.2f", p.profit))
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundColor(profitColor)
                }
                Text("Δ = \(points(delta)) (\(String(format: "%+.2f%%", delta / p.entry * 100)))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(delta >= 0 ? HistoryRow.blue : HistoryRow.red)
                Text("\(time(p.openTime)) → \(time(p.closeTime))")
                    .font(.subheadline.monospacedDigit())
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        label("S/L:")
                        Text(p.stop.map(price) ?? "–").foregroundColor(p.reason == "stop" ? HistoryRow.red : .primary)
                        label("Phí qua đêm:")
                        money(p.swap)
                    }
                    GridRow {
                        label("T/P:")
                        Text(p.target.map(price) ?? "–").foregroundColor(p.reason == "target" ? HistoryRow.blue : .primary)
                        label("Phí:")
                        money(p.commission)
                    }
                }
                .font(.subheadline.monospacedDigit())
                slippage
                moved
                if let comment = p.comment, !comment.isEmpty {
                    Text(comment).font(.subheadline).foregroundColor(.secondary)
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Closed by SL or TP: how far the fill was from the level that fired.
    @ViewBuilder
    private var slippage: some View {
        let level = p.reason == "stop" ? p.stop : (p.reason == "target" ? p.target : nil)
        if let level {
            let slip = (p.exit - level) * sign
            let worse = slip < -pointSize / 2
            HStack(spacing: 6) {
                Image(systemName: worse ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text(p.reason == "stop" ? "Chạm SL \(price(level))" : "Chạm TP \(price(level))")
                Spacer()
                Text(abs(slip) < pointSize / 2 ? "khớp đúng giá"
                     : "trượt \(points(slip)) điểm (\(String(format: "%+.\(digits)f", slip)))")
            }
            .font(.footnote.monospacedDigit())
            .foregroundColor(worse ? .orange : .green)
            .padding(8)
            .background((worse ? Color.orange : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else if p.reason == "stop" || p.reason == "target" {
            Text("Chưa có giá SL/TP lúc đóng (máy chủ cũ): cập nhật máy chủ để xem trượt giá.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    /// The SL/TP moved after opening.
    @ViewBuilder
    private var moved: some View {
        let lines = [("SL", p.stopOpen, p.stop), ("TP", p.targetOpen, p.target)].compactMap { item -> String? in
            guard let first = item.1, let last = item.2, abs(first - last) > pointSize / 2 else { return nil }
            return "\(item.0) đã kéo: \(price(first)) → \(price(last))"
        }
        if !lines.isEmpty {
            Text(lines.joined(separator: " · ")).font(.caption.monospacedDigit()).foregroundColor(.secondary)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundColor(.secondary)
    }

    private func money(_ value: Double?) -> some View {
        Text(value.map { abs($0) < 0.005 ? "-" : String(format: "%.2f", $0) } ?? "-")
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func price(_ value: Double) -> String { String(format: "%.\(digits)f", value) }

    private func points(_ move: Double) -> String { String(format: "%+.0f", move / pointSize) }

    private func time(_ value: Double) -> String { Self.formatter.string(from: Date(timeIntervalSince1970: value)) }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.title3).frame(maxWidth: .infinity, minHeight: 54)
        }
    }

    /// Opens the symbol on the Live chart; "Giao dịch" also shows the BUY/SELL bar.
    private func openChart(trade: Bool) {
        if fromMT5 {
            market.select(source: .mt5, symbol: p.symbol)
        }
        if trade { UserDefaults.standard.set(true, forKey: "live.showTradeButtons") }
        store.selectedTab = .live
        dismiss()
    }
}

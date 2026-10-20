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
                                      reason: t.reason.rawValue))
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
        case today = "Hôm nay", week = "Tuần trước", month = "Tháng trước", threeMonths = "3 tháng trước", custom = "Tuỳ chỉnh"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable {
        case newest = "Mới nhất", oldest = "Cũ nhất", symbol = "Theo mã", profit = "Theo lãi/lỗ"
    }

    let source: Source

    @Environment(PaperTrader.self) private var trader
    @AppStorage("history.page") private var pageName = Page.positions.rawValue
    @AppStorage("history.period") private var periodName = Period.week.rawValue
    @AppStorage("history.sort") private var sortName = Sort.newest.rawValue
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var showCustom = false
    @State private var history: TradeHistory?
    @State private var error: String?
    @State private var loading = false

    private var page: Page { Page(rawValue: pageName) ?? .positions }
    private var period: Period { Period(rawValue: periodName) ?? .week }
    private var sort: Sort { Sort(rawValue: sortName) ?? .newest }

    private var range: (from: Date, to: Date) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        switch period {
        case .today: return (today, now)
        case .week: return (calendar.date(byAdding: .day, value: -7, to: today) ?? today, now)
        case .month: return (calendar.date(byAdding: .month, value: -1, to: today) ?? today, now)
        case .threeMonths: return (calendar.date(byAdding: .month, value: -3, to: today) ?? today, now)
        case .custom: return (calendar.startOfDay(for: customFrom),
                              calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customTo)) ?? customTo)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            List {
                if let error {
                    Text(error).font(.footnote).foregroundColor(.orange)
                }
                if let history {
                    rows(history)
                    summary(history)
                } else if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(source == .mt5 ? "Lịch sử" : "Lịch sử demo")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(periodName)|\(customFrom.timeIntervalSince1970)|\(customTo.timeIntervalSince1970)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCustom) { customSheet }
    }

    // MARK: - Top bar

    private var topBar: some View {
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
                HistoryRow(symbol: Self.name(p.symbol), side: p.side == "long" ? "buy" : "sell", lots: p.lots,
                           detail: "\(Self.price(p.entry)) → \(Self.price(p.exit))",
                           value: String(format: "%.2f", p.profit), valueColor: Self.color(p.profit),
                           time: p.closeTime)
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

    @ViewBuilder
    private func summary(_ h: TradeHistory) -> some View {
        let s = h.summary
        Section {
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
            } catch {
                self.error = ServerUpdate.isOutdated(error)
                    ? "Máy chủ VPS chưa có lịch sử theo ngày: vào Bot trên VPS → Cập nhật máy chủ VPS."
                    : error.localizedDescription
            }
        }
    }

    // MARK: - Formatting

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

    static let blue = Color(red: 0.16, green: 0.42, blue: 0.95)
    static let red = Color(red: 0.86, green: 0.25, blue: 0.2)

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Text(symbol).foregroundColor(.primary)
                    if !side.isEmpty {
                        Text(side + (lots.map { " " + TradeHistoryView.lots($0) } ?? ""))
                            .foregroundColor(side.hasPrefix("buy") ? Self.blue : Self.red)
                    }
                }
                .font(.system(size: 19, weight: .semibold).width(.condensed))
                .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.system(size: 19, weight: .semibold).width(.condensed).monospacedDigit())
                    .foregroundColor(valueColor)
            }
            HStack {
                Text(detail)
                Spacer()
                Text(Self.formatter.string(from: Date(timeIntervalSince1970: time)))
            }
            .font(.system(size: 16).monospacedDigit())
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }
}

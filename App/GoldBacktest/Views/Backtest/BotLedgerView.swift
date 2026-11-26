import SwiftUI

/// The grid ("nhồi lệnh") bot on the server, compact: its state and account, a chart of its market with the open
/// positions' entry lines, its numbers, open positions and closed trades. Read only: the bot runs 24/7 on the
/// server, set up and switched on / off on the website.
struct BotLedgerView: View {
    /// Kept current the whole time the app runs (BotLive): the tab opens up to date and moves live.
    private var live: BotLive { BotLive.shared }
    private var ledger: BotLedger? { live.ledger }
    private var error: String? { live.error }
    private var account: BotAccount? { live.account }
    @State private var chart: BotChartData?
    @State private var chartError: String?
    @AppStorage("bot.chartTf") private var tf = "1m"
    @State private var showAll = false
    @State private var showStats = true
    /// "Lệnh đã đóng" for a period: today, yesterday, the last 7 days or days picked (read from the server).
    @State private var period = BotPeriod.today
    @State private var customFrom = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-6 * 86400)
    @State private var customTo = Date()
    @State private var periodTrades: [BotBook.Closed]?
    @State private var periodKey = ""
    @State private var periodAt = Date.distantPast

    private var useOwn: Bool { live.useOwn }
    private var book: BotBook? { live.book }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error {
                    Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).botCard()
                }
                if ledger?.own != nil {
                    Picker("Tài khoản", selection: Binding(get: { live.showOwn }, set: { live.showOwn = $0 })) {
                        Text("MT5 thứ 2 (bot)").tag(true)
                        Text("Tài khoản chart").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: live.showOwn) { _, _ in chart = nil; live.account = nil; Task { await live.refresh(force: true); await load() } }
                }
                if let book {
                    header(book)
                    chartCard(book)
                    stats(book)
                    if !book.positions.isEmpty { positions(book) }
                    analysis(book)
                    history(book)
                } else if ledger != nil {
                    Text("Bot nhồi lệnh chưa được cài trên máy chủ: chỉnh và bật ở web (tab Bot).")
                        .font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).botCard()
                } else if error == nil {
                    ProgressView("Đang tải…").frame(maxWidth: .infinity).botCard()
                }
                NavigationLink { RemoteBotView() } label: {
                    HStack {
                        Label("Kết nối máy chủ", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .botCard()
                }
                .buttonStyle(.plain)
                Text("Bot chạy 24/24 trên máy chủ, kể cả khi tắt app hay web. Bật / tắt và chỉnh bot ở web (tab Bot).")
                    .font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Bot nhồi lệnh")
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .refreshable { await live.refresh(force: true); await load() }
    }

    // MARK: Cards

    private func header(_ book: BotBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("🕸️ Nhồi lệnh").font(.headline)
                if !book.symbol.isEmpty { Text(book.symbol).font(.subheadline).foregroundColor(.secondary) }
                Spacer()
                Text(book.running ? (book.paper ? "ĐANG CHẠY ẢO" : "ĐANG CHẠY MT5") : "ĐANG TẮT")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill((book.running ? (book.paper ? Color.blue : Color.green) : Color.gray).opacity(0.18)))
                    .foregroundColor(book.running ? (book.paper ? .blue : .green) : .secondary)
            }
            HStack(spacing: 6) {
                if book.paper {
                    tag("ẢO", .blue)
                    Text("Tài khoản ảo của bot").font(.caption).foregroundColor(.secondary)
                } else if let a = account, let login = a.login {
                    tag(a.mode == "real" ? "THẬT" : "DEMO", a.mode == "real" ? .red : .green)
                    Text("#\(String(login))\(a.server.map { " · " + $0 } ?? "")\(useOwn ? " · MT5 thứ 2" : " · tài khoản chart")")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                } else {
                    Text("Đang đọc tài khoản…").font(.caption).foregroundColor(.secondary)
                }
            }
            if let e = book.error, !e.isEmpty { Text(e).font(.caption).foregroundColor(.orange) }
        }
        .botCard()
    }

    private func chartCard(_ book: BotBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chart của bot").font(.subheadline.bold())
                Spacer()
                Picker("Khung", selection: $tf) {
                    ForEach(["1m", "5m", "15m", "1h"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .onChange(of: tf) { _, _ in chart = nil; Task { await load() } }
            }
            if let chart, chart.candles.count > 1 {
                BotChartView(data: chart, positions: book.positions).frame(height: 260)
                Text("Chụm / mở 2 ngón để zoom · kéo ngang xem nến cũ · kéo dọc trục giá để giãn / co nến · chạm 2 lần về mặc định")
                    .font(.caption2).foregroundColor(.secondary)
            } else if let chartError {
                Text(chartError).font(.caption).foregroundColor(.orange).frame(height: 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: 250)
            }
        }
        .botCard()
    }

    private func stats(_ book: BotBook) -> some View {
        let closed = closedTrades(book)
        let net = closed.reduce(0) { $0 + $1.profit }
        let open = book.positions.reduce(0) { $0 + $1.profit }
        let wins = closed.filter { $0.profit > 0 }.count
        let when = period.label.lowercased()
        let balance = book.paper ? book.balance : account?.balance
        let equity = book.paper ? book.balance.map { $0 + open } : account?.equity
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("Lãi/lỗ đã chốt (\(when))", Self.money(net), net >= 0 ? .green : .red)
            tile("Đang mở", "\(book.positions.count) · \(Self.money(open))", open >= 0 ? .green : .red)
            tile("Thắng (\(when))", closed.isEmpty ? "–" : "\(wins)/\(closed.count) · \(Int((Double(wins) / Double(closed.count) * 100).rounded()))%", .primary)
            tile(book.paper ? "Số dư ảo / Equity" : "Balance / Equity",
                 balance.map { String(format: "%.2f", $0) + (equity.map { String(format: " / %.2f", $0) } ?? "") } ?? "–", .primary)
        }
    }

    // MARK: Statistics (as the website's, compact): over the period picked for "Lệnh đã đóng"

    private func analysis(_ book: BotBook) -> some View {
        let tr = closedTrades(book).sorted { ($0.closeTime ?? 0) < ($1.closeTime ?? 0) }
        return DisclosureGroup(isExpanded: $showStats) {
            if tr.isEmpty {
                Text("Chưa có lệnh đã đóng trong khoảng này").font(.caption).foregroundColor(.secondary).padding(.top, 4)
            } else {
                BotStatsView(trades: tr).padding(.top, 6)
            }
        } label: {
            Text("📊 Thống kê · \(period.label.lowercased())").font(.subheadline.bold()).foregroundColor(.primary)
        }
        .botCard()
    }

    private func positions(_ book: BotBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lệnh đang mở").font(.subheadline.bold())
            ForEach(book.positions) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        sideTag(p.side, p.lots)
                        Text(p.entry.map { String(format: "@ %.2f", $0) } ?? "").font(.caption).foregroundColor(.secondary).monospacedDigit()
                        Spacer()
                        Text(Self.money(p.profit)).font(.subheadline.bold()).foregroundColor(p.profit >= 0 ? .green : .red).monospacedDigit()
                    }
                    if let why = p.why, !why.isEmpty { reasonLine("Vào", BotReason.entry(why), .secondary) }
                    if let stop = p.stop {
                        let k = BotReason.close(p.stopKind ?? "SL rổ", kind: nil)
                        HStack(spacing: 6) {
                            chip(k.label, k.color)
                            Text(String(format: "SL %.2f", stop)).font(.caption2).monospacedDigit().foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) { chip("Không có SL trên sàn", .orange); Text("bot tự đóng theo rổ").font(.caption2).foregroundColor(.secondary) }
                    }
                }
                .padding(.vertical, 2)
                if p.id != book.positions.last?.id { Divider() }
            }
        }
        .botCard()
    }

    private func history(_ book: BotBook) -> some View {
        let closed = closedTrades(book)
        let shown = showAll ? closed : Array(closed.prefix(8))
        let net = closed.reduce(0) { $0 + $1.profit }
        let wins = closed.filter { $0.profit > 0 }.count
        return VStack(alignment: .leading, spacing: 6) {
            Text("Lệnh đã đóng").font(.subheadline.bold())
            Picker("Thời gian", selection: $period) {
                ForEach(BotPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: period) { _, _ in periodTrades = nil; showAll = false; Task { await load() } }
            if period == .custom {
                HStack {
                    DatePicker("Từ", selection: $customFrom, in: ...Date(), displayedComponents: .date)
                    DatePicker("Đến", selection: $customTo, in: ...Date(), displayedComponents: .date)
                }
                .font(.caption)
                .onChange(of: customFrom) { _, _ in periodTrades = nil; Task { await load() } }
                .onChange(of: customTo) { _, _ in periodTrades = nil; Task { await load() } }
            }
            HStack(spacing: 6) {
                Text(closed.isEmpty ? "Không có lệnh" : "\(closed.count) lệnh · thắng \(Int((Double(wins) / Double(max(closed.count, 1)) * 100).rounded()))%")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                if !closed.isEmpty {
                    Text(Self.money(net)).font(.subheadline.bold()).foregroundColor(net >= 0 ? .green : .red).monospacedDigit()
                }
            }
            .padding(.vertical, 2)
            ForEach(shown) { t in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        sideTag(t.side, t.lots)
                        Text("\(t.entry.map { String(format: "%.2f", $0) } ?? "–") → \(t.exit.map { String(format: "%.2f", $0) } ?? "–")")
                            .font(.caption).monospacedDigit()
                        Spacer()
                        Text(Self.money(t.profit)).font(.caption.bold()).foregroundColor(t.profit >= 0 ? .green : .red).monospacedDigit()
                    }
                    HStack(spacing: 6) {
                        if t.reason != nil || t.stopKind != nil {
                            let r = BotReason.close(t.reason, kind: t.stopKind)
                            chip(r.label, r.color)
                        }
                        if let time = t.closeTime {
                            Text(Date(timeIntervalSince1970: time), format: .dateTime.day().month().hour().minute())
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if let why = t.why, !why.isEmpty { reasonLine("Vào", BotReason.entry(why), .secondary) }
                }
                .padding(.vertical, 2)
                if t.id != shown.last?.id { Divider() }
            }
            if closed.count > 8 {
                Button(showAll ? "Thu gọn" : "Xem tất cả \(closed.count) lệnh") { showAll.toggle() }.font(.caption)
            }
            DisclosureGroup("Các loại SL / lý do đóng lệnh") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(BotReason.legend.indices, id: \.self) { i in
                        let item = BotReason.legend[i]
                        let r = BotReason.close(item.0, kind: nil)
                        HStack(alignment: .top, spacing: 6) {
                            chip(r.label, r.color).frame(width: 118, alignment: .leading)
                            Text(item.1).font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
        }
        .botCard()
    }

    /// The period picked, as [from, to) in time.
    private var periodRange: (from: Date, to: Date) {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        switch period {
        case .today: return (today, Date().addingTimeInterval(60))
        case .yesterday: return (cal.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86400), today)
        case .week: return (Date().addingTimeInterval(-7 * 86400), Date().addingTimeInterval(60))
        case .custom:
            let a = cal.startOfDay(for: min(customFrom, customTo)), b = cal.startOfDay(for: max(customFrom, customTo))
            return (a, cal.date(byAdding: .day, value: 1, to: b) ?? b.addingTimeInterval(86400))
        }
    }

    /// The period's closed trades: from the server (any length of time), else the bot's recent ones filtered.
    private func closedTrades(_ book: BotBook) -> [BotBook.Closed] {
        if let periodTrades { return periodTrades }
        let r = periodRange
        return book.history.filter { t in
            guard let c = t.closeTime else { return false }
            return c >= r.from.timeIntervalSince1970 && c < r.to.timeIntervalSince1970
        }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline.bold()).foregroundColor(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .botCard()
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15))).foregroundColor(color)
    }

    private func reasonLine(_ title: String, _ text: String, _ color: Color) -> some View {
        (Text(title + ": ").bold() + Text(text)).font(.caption2).foregroundColor(color).lineLimit(2)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.18))).foregroundColor(color)
    }

    private func sideTag(_ side: String, _ lots: Double?) -> some View {
        tag("\(side == "long" ? "BUY" : "SELL") \(lots.map { String(format: "%g", $0) } ?? "")", side == "long" ? .blue : .red)
    }

    // MARK: Data

    private func load() async {
        // The bot and its account come from BotLive (every 2 s / 8 s); here its chart and closed trades.
        if live.ledger == nil { await live.refresh(force: true) }
        guard let client = RemoteBotSettings.client() else { return }
        let prefix = live.prefix
        await loadPeriod(client, prefix: prefix)
        guard let symbol = book?.symbol, !symbol.isEmpty else { return }
        do {
            let path = "\(prefix)/mt5/candles?symbol=\(RemoteBotClient.queryValue(symbol))&interval=\(tf)&count=400"
            chart = try JSONDecoder().decode(BotChartData.self, from: try await client.send(path, timeout: 20))
            chartError = nil
        } catch let e as RemoteBotClient.ServerError {
            chartError = e.code == 404 ? "Cập nhật máy chủ để xem chart của bot" : e.message
        } catch {
            chartError = error.localizedDescription
        }
    }

    /// The period's closed trades from the server (server 8.6+): again when the period changes, else every 30 s.
    private func loadPeriod(_ client: RemoteBotClient, prefix: String) async {
        let r = periodRange
        // Today / 7 days roll on with the clock: read again every 30 s; days picked: when they change.
        let key = "\(prefix)|\(period.rawValue)" + (period == .custom ? "|\(Int(r.from.timeIntervalSince1970))|\(Int(r.to.timeIntervalSince1970))" : "")
        guard key != periodKey || Date().timeIntervalSince(periodAt) > 30 else { return }
        struct Response: Decodable { var trades: [ServerBot.Trade] }
        let path = "\(prefix)/gridbot/history?from=\(Int(r.from.timeIntervalSince1970))&to=\(Int(r.to.timeIntervalSince1970))"
        if let data = try? await client.send(path, timeout: 30), let response = try? JSONDecoder().decode(Response.self, from: data) {
            periodTrades = ServerBot.closed(response.trades)
        } else {
            periodTrades = nil  // an older server: the bot's recent trades, filtered here
        }
        periodKey = key
        periodAt = Date()
    }

    static func money(_ v: Double) -> String { String(format: "%@%.2f$", v >= 0 ? "+" : "−", abs(v)) }
}

/// The grid bot's numbers over some closed trades: profit factor, expectancy, drawdown, why many wins can still
/// lose (average win against average loss, the win rate needed), and by session, side, exit and hour (Vietnam time).
struct BotStatsView: View {
    var trades: [BotBook.Closed]

    private struct Row: Identifiable { var id: String; var name: String; var n: Int; var wins: Int; var pl: Double }

    var body: some View {
        let wins = trades.filter { $0.profit > 0 }, losses = trades.filter { $0.profit < 0 }
        let gp = wins.reduce(0) { $0 + $1.profit }, gl = -losses.reduce(0) { $0 + $1.profit }
        let net = gp - gl, n = Double(trades.count)
        let avgW = wins.isEmpty ? 0 : gp / Double(wins.count), avgL = losses.isEmpty ? 0 : gl / Double(losses.count)
        let winRate = Double(wins.count) / max(n, 1) * 100
        let need = avgW + avgL > 0 ? avgL / (avgW + avgL) * 100 : 0
        var cum = 0.0, peak = 0.0, dd = 0.0
        for t in trades { cum += t.profit; peak = max(peak, cum); dd = min(dd, cum - peak) }
        let hours = Self.byHour(trades)
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                cell("Profit factor", gl > 0 ? String(format: "%.2f", gp / gl) : (gp > 0 ? "∞" : "–"), gl > 0 && gp / gl < 1 ? .red : .green)
                cell("Kỳ vọng mỗi lệnh", BotLedgerView.money(net / max(n, 1)), net >= 0 ? .green : .red)
                cell("Sụt giảm lớn nhất", BotLedgerView.money(dd), dd < 0 ? .red : .secondary)
                cell("Cần thắng ≥ \(Int(need.rounded()))%", "đang \(Int(winRate.rounded()))%", winRate >= need ? .green : .red)
            }
            HStack(spacing: 12) {
                Text("Lời TB ").font(.caption).foregroundColor(.secondary) + Text(BotLedgerView.money(avgW)).font(.caption.bold()).foregroundColor(.green)
                Text("Lỗ TB ").font(.caption).foregroundColor(.secondary) + Text(BotLedgerView.money(-avgL)).font(.caption.bold()).foregroundColor(.red)
            }
            if avgW > 0, avgL > 0, winRate < need {
                Text("Mỗi lệnh thua mất ≈ \(String(format: "%.1f", avgL / avgW)) lần một lệnh thắng → phải thắng trên \(Int(need.rounded()))% mới hoà vốn; đang \(Int(winRate.rounded()))% nên vẫn lỗ.")
                    .font(.caption2).foregroundColor(.orange)
            }
            section("Theo phiên (giờ VN)", rows: Self.bySession(trades))
            section("Theo chiều", rows: Self.group(trades) { $0.side == "long" ? "BUY" : "SELL" })
            section("Theo cách đóng lệnh", rows: Self.group(trades) { BotReason.close($0.reason, kind: $0.stopKind).label })
            VStack(alignment: .leading, spacing: 4) {
                Text("Theo giờ trong ngày").font(.caption.bold())
                HourBars(values: hours).frame(height: 54)
                let worst = hours.enumerated().filter { $0.element < 0 }.sorted { $0.element < $1.element }.prefix(3)
                if !worst.isEmpty {
                    Text("Giờ lỗ nhiều nhất: " + worst.map { "\($0.offset)h \(BotLedgerView.money($0.element))" }.joined(separator: ", "))
                        .font(.caption2).foregroundColor(.red)
                }
            }
            if trades.count < 100 {
                Text("Mới \(trades.count) lệnh: chạy thêm vài ngày (qua phiên Mỹ và ngày có tin) để số liệu đáng tin hơn.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func cell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            Text(value).font(.subheadline.bold()).foregroundColor(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemGroupedBackground)))
    }

    private func section(_ title: String, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.bold())
            ForEach(rows) { r in
                HStack {
                    Text(r.name).font(.caption)
                    Spacer()
                    Text("\(r.n) lệnh · \(r.n > 0 ? Int((Double(r.wins) / Double(r.n) * 100).rounded()) : 0)%").font(.caption2).foregroundColor(.secondary).monospacedDigit()
                    Text(BotLedgerView.money(r.pl)).font(.caption.bold()).foregroundColor(r.pl >= 0 ? .green : .red).monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    /// Vietnam time (UTC+7) hour of a close, as a fraction (19.5 = 19:30).
    private static func vnHour(_ t: Double) -> Double { ((t + 7 * 3600).truncatingRemainder(dividingBy: 86400)) / 3600 }

    private static func group(_ trades: [BotBook.Closed], _ key: (BotBook.Closed) -> String) -> [Row] {
        var out: [String: Row] = [:]
        for t in trades {
            let k = key(t)
            var r = out[k] ?? Row(id: k, name: k, n: 0, wins: 0, pl: 0)
            r.n += 1; r.wins += t.profit > 0 ? 1 : 0; r.pl += t.profit
            out[k] = r
        }
        return out.values.sorted { $0.pl < $1.pl }
    }

    private static func bySession(_ trades: [BotBook.Closed]) -> [Row] {
        let names = ["Á (06:00–14:00)", "Âu (14:00–19:30)", "Mỹ (19:30–04:00)", "Đêm (04:00–06:00)"]
        var rows = names.map { Row(id: $0, name: $0, n: 0, wins: 0, pl: 0) }
        for t in trades {
            guard let c = t.closeTime else { continue }
            let h = vnHour(c)
            let i = h >= 6 && h < 14 ? 0 : h >= 14 && h < 19.5 ? 1 : (h >= 19.5 || h < 4) ? 2 : 3
            rows[i].n += 1; rows[i].wins += t.profit > 0 ? 1 : 0; rows[i].pl += t.profit
        }
        return rows.filter { $0.n > 0 }
    }

    private static func byHour(_ trades: [BotBook.Closed]) -> [Double] {
        var out = Array(repeating: 0.0, count: 24)
        for t in trades { if let c = t.closeTime { out[Int(vnHour(c)) % 24] += t.profit } }
        return out
    }
}

/// 24 bars, one an hour (Vietnam time): green up for a profit, red down for a loss.
private struct HourBars: View {
    var values: [Double]

    var body: some View {
        Canvas { ctx, size in
            let top = values.map { abs($0) }.max() ?? 0
            guard top > 0 else { return }
            let labelH: CGFloat = 12, h = size.height - labelH, mid = h / 2
            let w = size.width / CGFloat(values.count)
            var zero = Path(); zero.move(to: CGPoint(x: 0, y: mid)); zero.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(zero, with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
            for (i, v) in values.enumerated() where v != 0 {
                let bh = max(1, CGFloat(abs(v) / top) * (mid - 2))
                let rect = CGRect(x: CGFloat(i) * w + 1, y: v > 0 ? mid - bh : mid, width: max(1, w - 2), height: bh)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(v > 0 ? .green : .red))
            }
            for i in stride(from: 0, to: values.count, by: 6) {
                ctx.draw(Text("\(i)h").font(.system(size: 8)).foregroundColor(.secondary),
                         at: CGPoint(x: CGFloat(i) * w + w / 2, y: size.height - labelH / 2), anchor: .center)
            }
        }
    }
}

/// The time "Lệnh đã đóng" covers.
enum BotPeriod: String, CaseIterable {
    case today, yesterday, week, custom
    var label: String {
        switch self {
        case .today: return "Hôm nay"
        case .yesterday: return "Hôm qua"
        case .week: return "7 ngày"
        case .custom: return "Tuỳ chọn"
        }
    }
}

private extension View {
    func botCard() -> some View {
        padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// The bot's reasons in plain words: why a position opened, and which SL / exit closed it.
enum BotReason {
    /// "mở rổ theo tín hiệu: nến 1m tăng 60%, bật hỗ trợ 3583.05, tick +0.44/10s" → "Mở rổ · nến 1m tăng 60% · …".
    static func entry(_ why: String) -> String {
        var t = why
        for (old, new) in [("mở rổ theo tín hiệu: ", "Mở rổ · "), ("mở rổ theo tín hiệu", "Mở rổ theo tín hiệu"), ("mở rổ", "Mở rổ"),
                           ("nhồi dương lớp", "Nhồi dương lớp"), ("nhồi âm lớp", "Nhồi âm lớp")] {
            if t.hasPrefix(old) { t = new + t.dropFirst(old.count); break }
        }
        return t.replacingOccurrences(of: ", ", with: " · ")
    }

    /// The exit's short label and colour; the broker's "SL trên sàn" names which SL it was when known.
    static func close(_ reason: String?, kind: String?) -> (label: String, color: Color) {
        let r = reason ?? kind ?? ""
        switch r {
        case "chốt rổ", "chốt lời", "TP trên sàn": return (r == "TP trên sàn" ? "TP trên sàn" : "Chốt rổ", .green)
        case "trailing": return ("Trailing SL", .teal)
        case "khoá lời nhồi": return ("SL khoá lời", .teal)
        case "SL rổ", "cắt lỗ lệnh": return ("SL rổ", .red)
        case "cắt lỗ chung": return ("Cắt lỗ chung", .red)
        case "tín hiệu ngược", "nến đảo chiều": return ("Tín hiệu đảo", .orange)
        case "tránh giờ mạnh": return ("Tránh tin / phiên Mỹ", .orange)
        case "đóng tay": return ("Đóng tay", .gray)
        case "cháy (stop out)": return ("Cháy (stop out)", .red)
        case "SL trên sàn":
            if let kind, kind != "SL trên sàn" {
                let k = close(kind, kind: nil)
                return ("SL trên sàn · " + k.label, k.color)
            }
            return ("SL trên sàn", .red)
        default: return (r.isEmpty ? "Đóng" : r, .secondary)
        }
    }

    static let legend: [(String, String)] = [
        ("chốt rổ", "Cả rổ đủ số tiền lời cài sẵn nên đóng hết."),
        ("trailing", "Lệnh đã lời, SL dời theo giá; giá quay lại chạm SL nên đóng (giữ phần lời)."),
        ("khoá lời nhồi", "Rổ nhồi dương: SL chung ở lớp trước / giá vốn; giá quay lại chạm nên đóng cả rổ."),
        ("SL rổ", "Giá chạy ngược quá khoảng SL rổ, hoặc rổ âm quá số tiền cài: cắt lỗ cả rổ."),
        ("cắt lỗ chung", "Tổng các lệnh của bot âm tới mức cắt lỗ chung: đóng hết rồi nghỉ."),
        ("tín hiệu ngược", "Tín hiệu đảo sang chiều kia nên đóng rổ đang ngược."),
        ("tránh giờ mạnh", "Sắp có tin đỏ / vào giờ phiên Mỹ: đóng trước để tránh giật."),
        ("đóng tay", "Bạn bấm \"Đóng hết lệnh của bot\"."),
    ]
}

/// The MT5 account (/mt5/trading): who, demo or real, its money.
struct BotAccount: Decodable {
    struct Position: Decodable { var ticket: Int?; var profit: Double? }
    var login: Int?
    var server: String?
    var mode: String?
    var balance: Double?
    var equity: Double?
    var positions: [Position]?
}

/// The bot's market (/mt5/candles): bars [time, open, high, low, close, volume], the quote and digits.
struct BotChartData: Decodable {
    var candles: [[Double]]
    var bid: Double?
    var ask: Double?
    var digits: Int?
}

/// Candles of the bot's market with a dashed line at each open position's entry (BUY blue, SELL red, its P/L on
/// the label) and the current price. No drawings: a view of what the bot is doing.
struct BotChartView: View {
    var data: BotChartData
    var positions: [BotBook.Open]
    /// Candles across the chart (two-finger pinch to zoom) and how many of the newest are scrolled past (drag
    /// sideways to look back); a double tap puts both back.
    @State private var visible = 90
    @State private var shift = 0
    @State private var pinchFrom: Int?
    @State private var dragFrom: Int?
    /// How much the price scale is stretched (drag the price axis up to stretch the candles, down to squeeze).
    @State private var yScale = 1.0
    @State private var scaleFrom: Double?

    private var all: [[Double]] { data.candles.filter { $0.count >= 5 } }

    var body: some View {
        GeometryReader { geo in
            chart
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            let from = pinchFrom ?? visible
                            pinchFrom = from
                            visible = min(max(Int((Double(from) / max(Double(scale), 0.05)).rounded()), 15), max(15, all.count))
                            shift = min(shift, max(0, all.count - visible))
                        }
                        .onEnded { _ in pinchFrom = nil }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { g in
                            guard abs(g.translation.width) > abs(g.translation.height) else { return }
                            let from = dragFrom ?? shift
                            dragFrom = from
                            let step = max(1, (geo.size.width - 62) / CGFloat(max(visible, 1)))
                            shift = min(max(from + Int((g.translation.width / step).rounded()), 0), max(0, all.count - visible))
                        }
                        .onEnded { _ in dragFrom = nil }
                )
                .onTapGesture(count: 2) { visible = 90; shift = 0; yScale = 1 }
                .overlay(alignment: .trailing) {
                    // The price axis: drag up / down to stretch / squeeze the candles (as TradingView's price scale).
                    Color.clear
                        .frame(width: 62)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { g in
                                    let from = scaleFrom ?? yScale
                                    scaleFrom = from
                                    yScale = min(max(from * exp(-Double(g.translation.height) / 120), 0.3), 8)
                                }
                                .onEnded { _ in scaleFrom = nil }
                        )
                        .onTapGesture(count: 2) { yScale = 1 }
                }
                .overlay(alignment: .topLeading) {
                    if shift > 0 {
                        Button { shift = 0 } label: {
                            Label("Về nến mới nhất", systemImage: "arrow.right.to.line").font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color(.systemBackground).opacity(0.9)))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
        }
    }

    private var chart: some View {
        Canvas { ctx, size in
            let candles = all
            let count = min(max(visible, 15), candles.count)
            let back = min(shift, max(0, candles.count - count))
            let rows = Array(candles[max(0, candles.count - back - count)..<(candles.count - back)])
            guard rows.count > 1 else { return }
            let digits = max(0, min(data.digits ?? 2, 5))
            let axisW: CGFloat = 62, timeH: CGFloat = 16
            let plot = CGRect(x: 0, y: 8, width: size.width - axisW, height: size.height - timeH - 8)
            var lo = rows.map { $0[3] }.min() ?? 0, hi = rows.map { $0[2] }.max() ?? 1
            for p in positions {
                if let e = p.entry { lo = min(lo, e); hi = max(hi, e) }
                if let sl = p.stop { lo = min(lo, sl); hi = max(hi, sl) }
            }
            if let b = data.bid { lo = min(lo, b); hi = max(hi, b) }
            let pad = max((hi - lo) * 0.06, 1e-6)
            lo -= pad; hi += pad
            if yScale != 1 {
                // Stretched / squeezed around the middle by the price axis drag.
                let mid = (lo + hi) / 2, half = (hi - lo) / 2 / yScale
                lo = mid - half; hi = mid + half
            }
            func y(_ v: Double) -> CGFloat { plot.minY + CGFloat((hi - v) / (hi - lo)) * plot.height }
            func price(_ v: Double) -> String { String(format: "%.\(digits)f", v) }
            let grid = Color.secondary.opacity(0.15)
            // Price grid and its labels on the right.
            for i in 0...4 {
                let v = lo + (hi - lo) * Double(i) / 4, yy = y(v)
                var line = Path(); line.move(to: CGPoint(x: 0, y: yy)); line.addLine(to: CGPoint(x: plot.maxX, y: yy))
                ctx.stroke(line, with: .color(grid), lineWidth: 0.5)
                ctx.draw(Text(price(v)).font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: plot.maxX + 4, y: yy), anchor: .leading)
            }
            // Candles.
            let step = plot.width / CGFloat(rows.count), bw = max(1, step * 0.65)
            let up = Color(red: 0.08, green: 0.72, blue: 0.54), down = Color(red: 0.94, green: 0.27, blue: 0.35)
            ctx.drawLayer { layer in
                // Candles stretched past the plot (price axis dragged) are cut at its edges.
                layer.clip(to: Path(plot))
                for (i, r) in rows.enumerated() {
                    let x = CGFloat(i) * step + step / 2, color = r[4] >= r[1] ? up : down
                    var wick = Path(); wick.move(to: CGPoint(x: x, y: y(r[2]))); wick.addLine(to: CGPoint(x: x, y: y(r[3])))
                    layer.stroke(wick, with: .color(color), lineWidth: 1)
                    let top = y(max(r[1], r[4])), bottom = y(min(r[1], r[4]))
                    layer.fill(Path(CGRect(x: x - bw / 2, y: top, width: bw, height: max(1, bottom - top))), with: .color(color))
                }
            }
            // A few times along the bottom.
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            for i in stride(from: 0, to: rows.count, by: max(1, rows.count / 4)) {
                let x = CGFloat(i) * step + step / 2
                ctx.draw(Text(f.string(from: Date(timeIntervalSince1970: rows[i][0]))).font(.system(size: 9)).foregroundColor(.secondary),
                         at: CGPoint(x: x, y: size.height - timeH / 2), anchor: .center)
            }
            // A label in a filled box, on the price axis.
            func label(_ text: String, at v: Double, color: Color) {
                let t = ctx.resolve(Text(text).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                let s = t.measure(in: CGSize(width: 200, height: 20))
                let rect = CGRect(x: plot.maxX + 2, y: y(v) - s.height / 2 - 2, width: min(s.width + 8, axisW - 2), height: s.height + 4)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
                ctx.draw(t, at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading)
            }
            // The current price.
            if let b = data.bid {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y(b))); line.addLine(to: CGPoint(x: plot.maxX, y: y(b)))
                ctx.stroke(line, with: .color(.secondary.opacity(0.7)), lineWidth: 0.8)
                label(price(b), at: b, color: .gray)
            }
            // The running positions, as a trading chart shows them: from the candle each opened on, a band from its
            // entry to the price now (green in profit, red in loss), its entry line and an arrow where it opened, its
            // SL dotted with its kind, and a label with side, lots and P/L.
            func xAt(_ t: Double?) -> CGFloat {
                guard let t, let i = rows.lastIndex(where: { $0[0] <= t }) else { return 0 }
                return CGFloat(i) * step + step / 2
            }
            let now = data.bid ?? rows.last?[4]
            for p in positions {
                guard let e = p.entry else { continue }
                let long = p.side == "long"
                let color: Color = long ? .blue : down
                let x0 = xAt(p.openTime)
                if let now {
                    let top = min(y(e), y(now)), h = max(1, abs(y(e) - y(now)))
                    ctx.fill(Path(CGRect(x: x0, y: top, width: max(1, plot.maxX - x0), height: h)),
                             with: .color((p.profit >= 0 ? up : down).opacity(0.13)))
                }
                var line = Path(); line.move(to: CGPoint(x: x0, y: y(e))); line.addLine(to: CGPoint(x: plot.maxX, y: y(e)))
                ctx.stroke(line, with: .color(color), lineWidth: 1.2)
                if x0 > 0 {
                    // The arrow where it opened: under the candle for a buy, over it for a sell.
                    let ay = long ? y(e) + 9 : y(e) - 9
                    var arrow = Path()
                    arrow.move(to: CGPoint(x: x0, y: long ? ay - 6 : ay + 6))
                    arrow.addLine(to: CGPoint(x: x0 - 5, y: long ? ay + 3 : ay - 3))
                    arrow.addLine(to: CGPoint(x: x0 + 5, y: long ? ay + 3 : ay - 3))
                    arrow.closeSubpath()
                    ctx.fill(arrow, with: .color(color))
                }
                if let sl = p.stop {
                    let kind = BotReason.close(p.stopKind ?? "SL rổ", kind: nil)
                    var dash = Path(); dash.move(to: CGPoint(x: x0, y: y(sl))); dash.addLine(to: CGPoint(x: plot.maxX, y: y(sl)))
                    ctx.stroke(dash, with: .color(kind.color), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    ctx.draw(Text(kind.label).font(.system(size: 8, weight: .semibold)).foregroundColor(kind.color),
                             at: CGPoint(x: max(x0, 2) + 2, y: y(sl) - 2), anchor: .bottomLeading)
                    label(price(sl), at: sl, color: kind.color)
                }
                let text = "\(long ? "BUY" : "SELL") \(p.lots.map { String(format: "%g", $0) } ?? "") \(p.profit >= 0 ? "+" : "")\(String(format: "%.2f", p.profit))"
                let t = ctx.resolve(Text(text).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                let s = t.measure(in: CGSize(width: 200, height: 20))
                let rect = CGRect(x: max(2, plot.maxX - s.width - 12), y: y(e) - s.height - 5, width: s.width + 8, height: s.height + 4)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color.opacity(0.9)))
                ctx.draw(t, at: CGPoint(x: rect.minX + 4, y: rect.midY), anchor: .leading)
                label(price(e), at: e, color: color)
            }
        }
    }
}

// MARK: - /bots

struct BotLedger: Decodable {
    var tick: ServerBot?
    var grid: ServerBot?
    var sr: ServerBot?
    var stop: ServerBot?
    var strategy: StrategyBot?
    var own: OwnLedger?

    /// The grid ("nhồi lệnh") bot only: the other bots are gone from the app and the website.
    var books: [BotBook] {
        var out: [BotBook] = []
        if let grid { out.append(grid.book(id: "grid", title: "🕸️ Nhồi lệnh")) }
        return out
    }
}

struct OwnLedger: Decodable {
    var tick: ServerBot?
    var grid: ServerBot?
    var sr: ServerBot?
    var stop: ServerBot?
    var strategy: StrategyBot?
    var error: String?

    var books: [BotBook] { BotLedger(tick: tick, grid: grid, sr: sr, stop: stop, strategy: strategy, own: nil).books }
}

struct ServerBot: Decodable {
    struct Config: Decodable { var running: Bool?; var paper: Bool?; var symbol: String?; var interval: String? }
    struct Position: Decodable {
        var side: String?; var lots: Double?; var entry: Double?; var profit: Double?
        var why: String?; var stop: Double?; var trail: Double?; var stopKind: String?; var openTime: Double?
        var ticket: Int?
    }
    struct Trade: Decodable {
        var side: String?; var lots: Double?; var entry: Double?; var exit: Double?; var closeTime: Double?; var profit: Double?
        var reason: String?; var why: String?; var stopKind: String?
    }
    struct Paper: Decodable { var balance: Double? }
    var config: Config?
    var positions: [Position]?
    var history: [Trade]?
    var paper: Paper?
    var error: String?

    func book(id: String, title: String) -> BotBook {
        BotBook(id: id, title: title, running: config?.running ?? false, paper: config?.paper ?? false,
                market: [config?.symbol, config?.interval].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                symbol: config?.symbol ?? "",
                balance: paper?.balance,
                positions: (positions ?? []).enumerated().map { i, p in
                    BotBook.Open(id: i, side: p.side ?? "", lots: p.lots, entry: p.entry, profit: p.profit ?? 0,
                                 why: p.why, stop: p.trail ?? p.stop, stopKind: p.trail != nil ? "trailing" : p.stopKind, openTime: p.openTime,
                                 ticket: p.ticket)
                },
                history: Self.closed(history ?? []),
                error: error)
    }

    static func closed(_ trades: [Trade]) -> [BotBook.Closed] {
        trades.enumerated().map { i, t in
            BotBook.Closed(id: i, side: t.side ?? "", lots: t.lots, entry: t.entry, exit: t.exit, closeTime: t.closeTime, profit: t.profit ?? 0,
                           reason: t.reason, why: t.why, stopKind: t.stopKind)
        }
    }
}

struct StrategyBot: Decodable {
    struct Settings: Decodable { var strategyName: String?; var symbol: String?; var interval: String?; var broker: String? }
    struct Position: Decodable { var side: String?; var lots: Double?; var entryPrice: Double?; var profit: Double? }
    struct Trade: Decodable { var side: String?; var lots: Double?; var entryPrice: Double?; var exitPrice: Double?; var exitTime: Double?; var profit: Double? }
    var running: Bool?
    var settings: Settings?
    var positions: [Position]?
    var history: [Trade]?

    var book: BotBook {
        BotBook(id: "strategy", title: "📈 Chiến lược" + (settings?.strategyName.map { ": " + $0 } ?? ""), running: running ?? false,
                paper: settings?.broker != "mt5",
                market: [settings?.symbol, settings?.interval].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                balance: nil,
                positions: (positions ?? []).enumerated().map { BotBook.Open(id: $0.offset, side: $0.element.side ?? "", lots: $0.element.lots, entry: $0.element.entryPrice, profit: $0.element.profit ?? 0) },
                history: (history ?? []).enumerated().map { BotBook.Closed(id: $0.offset, side: $0.element.side ?? "", lots: $0.element.lots, entry: $0.element.entryPrice, exit: $0.element.exitPrice, closeTime: $0.element.exitTime, profit: $0.element.profit ?? 0) },
                error: nil)
    }
}

/// One bot as the ledger shows it.
struct BotBook: Identifiable {
    struct Open: Identifiable {
        var id: Int; var side: String; var lots: Double?; var entry: Double?; var profit: Double
        /// Why it opened (the bot's signal / layer), its SL price and which SL that is.
        var why: String? = nil; var stop: Double? = nil; var stopKind: String? = nil; var openTime: Double? = nil
        var ticket: Int? = nil
    }
    struct Closed: Identifiable {
        var id: Int; var side: String; var lots: Double?; var entry: Double?; var exit: Double?; var closeTime: Double?; var profit: Double
        var reason: String? = nil; var why: String? = nil; var stopKind: String? = nil
    }
    var id: String
    var title: String
    var running: Bool
    var paper: Bool
    var market: String
    var symbol: String = ""
    var balance: Double?
    var positions: [Open]
    var history: [Closed]
    var error: String?
}

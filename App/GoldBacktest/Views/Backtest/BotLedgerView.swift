import SwiftUI

/// The grid ("nhồi lệnh") bot on the server, compact: its state and account, a chart of its market with the open
/// positions' entry lines, its numbers, open positions and closed trades. Read only: the bot runs 24/7 on the
/// server, set up and switched on / off on the website.
struct BotLedgerView: View {
    @State private var ledger: BotLedger?
    @State private var error: String?
    /// The bot's own account (the second MT5, an Exness demo while it is tested) first when there is one.
    @State private var showOwn = true
    @State private var account: BotAccount?
    @State private var chart: BotChartData?
    @State private var chartError: String?
    @AppStorage("bot.chartTf") private var tf = "1m"
    @State private var showAll = false

    private var useOwn: Bool { showOwn && ledger?.own != nil }
    private var book: BotBook? { ((useOwn ? ledger?.own?.books : ledger?.books) ?? []).first }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error {
                    Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).botCard()
                }
                if ledger?.own != nil {
                    Picker("Tài khoản", selection: $showOwn) {
                        Text("MT5 thứ 2 (bot)").tag(true)
                        Text("Tài khoản chart").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: showOwn) { _, _ in chart = nil; account = nil; Task { await load() } }
                }
                if let book {
                    header(book)
                    chartCard(book)
                    stats(book)
                    if !book.positions.isEmpty { positions(book) }
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
        .refreshable { await load() }
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
                BotChartView(data: chart, positions: book.positions).frame(height: 250)
            } else if let chartError {
                Text(chartError).font(.caption).foregroundColor(.orange).frame(height: 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: 250)
            }
        }
        .botCard()
    }

    private func stats(_ book: BotBook) -> some View {
        let net = book.history.reduce(0) { $0 + $1.profit }
        let open = book.positions.reduce(0) { $0 + $1.profit }
        let wins = book.history.filter { $0.profit > 0 }.count
        let balance = book.paper ? book.balance : account?.balance
        let equity = book.paper ? book.balance.map { $0 + open } : account?.equity
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("Lãi/lỗ đã chốt", Self.money(net), net >= 0 ? .green : .red)
            tile("Đang mở", "\(book.positions.count) · \(Self.money(open))", open >= 0 ? .green : .red)
            tile("Thắng", book.history.isEmpty ? "–" : "\(wins)/\(book.history.count) · \(Int((Double(wins) / Double(book.history.count) * 100).rounded()))%", .primary)
            tile(book.paper ? "Số dư ảo / Equity" : "Balance / Equity",
                 balance.map { String(format: "%.2f", $0) + (equity.map { String(format: " / %.2f", $0) } ?? "") } ?? "–", .primary)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Lệnh đã đóng").font(.subheadline.bold())
            if book.history.isEmpty {
                Text("Chưa có lệnh đã đóng").font(.caption).foregroundColor(.secondary)
            }
            ForEach(showAll ? book.history : Array(book.history.prefix(8))) { t in
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
                if t.id != (showAll ? book.history : Array(book.history.prefix(8))).last?.id { Divider() }
            }
            if book.history.count > 8 {
                Button(showAll ? "Thu gọn" : "Xem tất cả \(book.history.count) lệnh") { showAll.toggle() }.font(.caption)
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
        guard let client = RemoteBotSettings.client() else {
            error = "Chưa nối máy chủ: bấm \"Kết nối máy chủ\" bên dưới"
            return
        }
        do {
            let data = try await client.send("/bots", timeout: 30)
            ledger = try JSONDecoder().decode(BotLedger.self, from: data)
            error = nil
        } catch let e as RemoteBotClient.ServerError {
            error = e.message
            return
        } catch {
            self.error = error.localizedDescription
            return
        }
        // The account and market the bot trades: its second MT5 (through the main server) or the chart's.
        let prefix = useOwn ? "/acct2" : ""
        if let data = try? await client.send(prefix + "/mt5/trading", timeout: 20) {
            account = try? JSONDecoder().decode(BotAccount.self, from: data)
        }
        guard let symbol = book?.symbol, !symbol.isEmpty else { return }
        do {
            let path = "\(prefix)/mt5/candles?symbol=\(RemoteBotClient.queryValue(symbol))&interval=\(tf)&count=90"
            chart = try JSONDecoder().decode(BotChartData.self, from: try await client.send(path, timeout: 20))
            chartError = nil
        } catch let e as RemoteBotClient.ServerError {
            chartError = e.code == 404 ? "Cập nhật máy chủ để xem chart của bot" : e.message
        } catch {
            chartError = error.localizedDescription
        }
    }

    static func money(_ v: Double) -> String { String(format: "%@%.2f$", v >= 0 ? "+" : "−", abs(v)) }
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
    var login: Int?
    var server: String?
    var mode: String?
    var balance: Double?
    var equity: Double?
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

    var body: some View {
        Canvas { ctx, size in
            let rows = data.candles.filter { $0.count >= 5 }
            guard rows.count > 1 else { return }
            let digits = max(0, min(data.digits ?? 2, 5))
            let axisW: CGFloat = 62, timeH: CGFloat = 16
            let plot = CGRect(x: 0, y: 8, width: size.width - axisW, height: size.height - timeH - 8)
            var lo = rows.map { $0[3] }.min() ?? 0, hi = rows.map { $0[2] }.max() ?? 1
            for p in positions { if let e = p.entry { lo = min(lo, e); hi = max(hi, e) } }
            if let b = data.bid { lo = min(lo, b); hi = max(hi, b) }
            let pad = max((hi - lo) * 0.06, 1e-6)
            lo -= pad; hi += pad
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
            for (i, r) in rows.enumerated() {
                let x = CGFloat(i) * step + step / 2, color = r[4] >= r[1] ? up : down
                var wick = Path(); wick.move(to: CGPoint(x: x, y: y(r[2]))); wick.addLine(to: CGPoint(x: x, y: y(r[3])))
                ctx.stroke(wick, with: .color(color), lineWidth: 1)
                let top = y(max(r[1], r[4])), bottom = y(min(r[1], r[4]))
                ctx.fill(Path(CGRect(x: x - bw / 2, y: top, width: bw, height: max(1, bottom - top))), with: .color(color))
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
            // The open positions' entries.
            for p in positions {
                guard let e = p.entry else { continue }
                let color: Color = p.side == "long" ? .blue : down
                var line = Path(); line.move(to: CGPoint(x: 0, y: y(e))); line.addLine(to: CGPoint(x: plot.maxX, y: y(e)))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                let text = "\(p.side == "long" ? "BUY" : "SELL") \(p.lots.map { String(format: "%g", $0) } ?? "") \(p.profit >= 0 ? "+" : "")\(String(format: "%.2f", p.profit))"
                let t = ctx.resolve(Text(text).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                let s = t.measure(in: CGSize(width: 200, height: 20))
                let rect = CGRect(x: max(2, plot.maxX - s.width - 12), y: y(e) - s.height - 5, width: s.width + 8, height: s.height + 4)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color.opacity(0.85)))
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
        var why: String?; var stop: Double?; var trail: Double?; var stopKind: String?
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
                                 why: p.why, stop: p.trail ?? p.stop, stopKind: p.trail != nil ? "trailing" : p.stopKind)
                },
                history: (history ?? []).enumerated().map { i, t in
                    BotBook.Closed(id: i, side: t.side ?? "", lots: t.lots, entry: t.entry, exit: t.exit, closeTime: t.closeTime, profit: t.profit ?? 0,
                                   reason: t.reason, why: t.why, stopKind: t.stopKind)
                },
                error: error)
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
        var why: String? = nil; var stop: Double? = nil; var stopKind: String? = nil
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

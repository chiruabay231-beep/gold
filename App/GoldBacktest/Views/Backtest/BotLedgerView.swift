import SwiftUI

/// "Sổ lệnh các bot": every bot on the VPS at a glance — running or not, on the virtual account or MT5,
/// its numbers, open positions and closed trades (from the server's /bots). Read only; the bots run 24/7
/// on the VPS whether the app or the website is open or not.
struct BotLedgerView: View {
    @State private var ledger: BotLedger?
    @State private var error: String?
    @State private var showOwn = false

    var body: some View {
        List {
            if let error {
                Section { Label(error, systemImage: "wifi.exclamationmark").foregroundColor(.orange) }
            }
            if let ledger {
                if ledger.own != nil {
                    Section {
                        Picker("Tài khoản", selection: $showOwn) {
                            Text("Tài khoản chính").tag(false)
                            Text("Tài khoản riêng (máy tính)").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                let books = (showOwn ? ledger.own?.books : ledger.books) ?? []
                if showOwn, let ownError = ledger.own?.error {
                    Section { Text(ownError).foregroundColor(.orange) }
                }
                summary(books)
                ForEach(books) { book in
                    BotBookSection(book: book)
                }
            } else if error == nil {
                Section { ProgressView("Đang tải…") }
            }
            Section {
                NavigationLink { RemoteBotView() } label: {
                    Label("Kết nối & điều khiển bot trên VPS", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Bot chạy 24/24 trên VPS, kể cả khi tắt app hay web. Bật / tắt và chỉnh bot ở web (tab Bot) hoặc ở mục trên.")
            }
        }
        .navigationTitle("Bot")
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .refreshable { await load() }
    }

    private func summary(_ books: [BotBook]) -> some View {
        let closed = books.flatMap(\.history)
        let net = closed.reduce(0) { $0 + $1.profit }
        let open = books.flatMap(\.positions).reduce(0) { $0 + $1.profit }
        let wins = closed.filter { $0.profit > 0 }.count
        return Section("Tổng các bot") {
            LabeledContent("Lãi/lỗ đã chốt") { Text(Self.money(net)).foregroundColor(net >= 0 ? .green : .red).monospacedDigit() }
            LabeledContent("Đang mở") { Text("\(books.flatMap(\.positions).count) lệnh · \(Self.money(open))").foregroundColor(open >= 0 ? .green : .red).monospacedDigit() }
            LabeledContent("Thắng") { Text(closed.isEmpty ? "–" : "\(wins)/\(closed.count) · \(Int((Double(wins) / Double(closed.count) * 100).rounded()))%").monospacedDigit() }
            LabeledContent("Bot đang chạy") { Text("\(books.filter(\.running).count)/\(books.count)") }
        }
    }

    private func load() async {
        guard let client = RemoteBotSettings.client() else {
            error = "Chưa nối máy chủ VPS: bấm \"Kết nối & điều khiển bot trên VPS\" bên dưới"
            return
        }
        do {
            let data = try await client.send("/bots", timeout: 30)
            ledger = try JSONDecoder().decode(BotLedger.self, from: data)
            error = nil
        } catch let e as RemoteBotClient.ServerError {
            error = e.code == 404 ? "Cập nhật máy chủ lên bản 4.8 để xem sổ lệnh các bot" : e.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func money(_ v: Double) -> String { String(format: "%@%.2f$", v >= 0 ? "+" : "−", abs(v)) }
}

private struct BotBookSection: View {
    var book: BotBook
    @State private var showAll = false

    var body: some View {
        Section {
            HStack {
                Text(book.title).font(.headline)
                Spacer()
                Text(book.running ? (book.paper ? "ĐANG CHẠY ẢO" : "ĐANG CHẠY MT5") : "Đang tắt")
                    .font(.caption.bold())
                    .foregroundColor(book.running ? (book.paper ? .blue : .orange) : .secondary)
            }
            if !book.market.isEmpty { LabeledContent("Mã · khung", value: book.market) }
            if let balance = book.balance { LabeledContent("Số dư ảo") { Text(String(format: "%.2f$", balance)).monospacedDigit() } }
            let net = book.history.reduce(0) { $0 + $1.profit }
            let wins = book.history.filter { $0.profit > 0 }.count
            LabeledContent("Lãi/lỗ đã chốt") { Text(BotLedgerView.money(net)).foregroundColor(net >= 0 ? .green : .red).monospacedDigit() }
            LabeledContent("Lệnh đã đóng") { Text(book.history.isEmpty ? "0" : "\(book.history.count) · thắng \(Int((Double(wins) / Double(book.history.count) * 100).rounded()))%").monospacedDigit() }
            if let error = book.error, !error.isEmpty { Text(error).font(.caption).foregroundColor(.orange) }
            ForEach(book.positions) { p in
                HStack {
                    Text("\(p.side == "long" ? "BUY" : "SELL") \(Self.lots(p.lots))").foregroundColor(p.side == "long" ? .blue : .red).font(.subheadline.bold())
                    Text(p.entry.map { String(format: "@ %.2f", $0) } ?? "").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", p.profit)).foregroundColor(p.profit >= 0 ? .blue : .red).monospacedDigit()
                }
            }
            ForEach(showAll ? book.history : Array(book.history.prefix(8))) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.side == "long" ? "BUY" : "SELL") \(Self.lots(t.lots)) · \(t.entry.map { String(format: "%.2f", $0) } ?? "–") → \(t.exit.map { String(format: "%.2f", $0) } ?? "–")")
                            .font(.caption)
                        if let time = t.closeTime {
                            Text(Date(timeIntervalSince1970: time), format: .dateTime.day().month().hour().minute())
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(BotLedgerView.money(t.profit)).foregroundColor(t.profit >= 0 ? .green : .red).font(.caption.bold()).monospacedDigit()
                }
            }
            if book.history.count > 8 {
                Button(showAll ? "Thu gọn" : "Xem tất cả \(book.history.count) lệnh") { showAll.toggle() }.font(.caption)
            }
        }
    }

    static func lots(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "" }
}

// MARK: - /bots

struct BotLedger: Decodable {
    var tick: ServerBot?
    var grid: ServerBot?
    var sr: ServerBot?
    var stop: ServerBot?
    var strategy: StrategyBot?
    var own: OwnLedger?

    var books: [BotBook] {
        var out: [BotBook] = []
        if let tick { out.append(tick.book(id: "tick", title: "⚡ Nến tick")) }
        if let grid { out.append(grid.book(id: "grid", title: "🕸️ Nhồi lệnh")) }
        if let sr { out.append(sr.book(id: "sr", title: "🧱 Cản & Hỗ trợ")) }
        if let stop { out.append(stop.book(id: "stop", title: "🎯 Stop theo nến")) }
        if let strategy { out.append(strategy.book) }
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
    struct Position: Decodable { var side: String?; var lots: Double?; var entry: Double?; var profit: Double? }
    struct Trade: Decodable { var side: String?; var lots: Double?; var entry: Double?; var exit: Double?; var closeTime: Double?; var profit: Double? }
    struct Paper: Decodable { var balance: Double? }
    var config: Config?
    var positions: [Position]?
    var history: [Trade]?
    var paper: Paper?
    var error: String?

    func book(id: String, title: String) -> BotBook {
        BotBook(id: id, title: title, running: config?.running ?? false, paper: config?.paper ?? false,
                market: [config?.symbol, config?.interval].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
                balance: paper?.balance,
                positions: (positions ?? []).enumerated().map { BotBook.Open(id: $0.offset, side: $0.element.side ?? "", lots: $0.element.lots, entry: $0.element.entry, profit: $0.element.profit ?? 0) },
                history: (history ?? []).enumerated().map { BotBook.Closed(id: $0.offset, side: $0.element.side ?? "", lots: $0.element.lots, entry: $0.element.entry, exit: $0.element.exit, closeTime: $0.element.closeTime, profit: $0.element.profit ?? 0) },
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
    struct Open: Identifiable { var id: Int; var side: String; var lots: Double?; var entry: Double?; var profit: Double }
    struct Closed: Identifiable { var id: Int; var side: String; var lots: Double?; var entry: Double?; var exit: Double?; var closeTime: Double?; var profit: Double }
    var id: String
    var title: String
    var running: Bool
    var paper: Bool
    var market: String
    var balance: Double?
    var positions: [Open]
    var history: [Closed]
    var error: String?
}

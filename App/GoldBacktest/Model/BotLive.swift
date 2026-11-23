import Foundation
import Observation
import SwiftUI

/// The grid bot's numbers kept current the whole time the app runs, not only while its tab is open: its account's
/// balance, equity and each open position's P/L every 2 s, the bot's state, positions and trades every 8 s.
/// The Bot tab reads it (so it opens already up to date) and the tab's badge shows the open P/L.
@MainActor
@Observable
final class BotLive {
    static let shared = BotLive()

    var ledger: BotLedger?
    var account: BotAccount?
    var error: String?
    /// The bot's own account (the second MT5, an Exness demo while it is tested) first when there is one.
    var showOwn = true

    var useOwn: Bool { showOwn && ledger?.own != nil }
    /// Requests to the bot's own account go through the main server.
    var prefix: String { useOwn ? "/acct2" : "" }

    @ObservationIgnored private var running = false
    @ObservationIgnored private var ledgerAt = Date.distantPast

    /// The grid bot as last read, its positions' P/L from the account read every 2 s.
    var book: BotBook? {
        guard var b = ((useOwn ? ledger?.own?.books : ledger?.books) ?? []).first else { return nil }
        b.positions = withLiveProfits(b.positions)
        return b
    }

    /// The open P/L on the tab's badge while the bot holds positions.
    var badge: Text? {
        guard let book, !book.positions.isEmpty else { return nil }
        let pl = book.positions.reduce(0) { $0 + $1.profit }
        return Text(String(format: "%+.2f", pl))
    }

    /// Runs until the app's tabs go away; a second call while it runs returns at once.
    func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func refresh(force: Bool = false) async {
        guard let client = RemoteBotSettings.client() else {
            error = "Chưa nối máy chủ: bấm \"Kết nối máy chủ\" bên dưới"
            return
        }
        if force || ledger == nil || Date().timeIntervalSince(ledgerAt) >= 8 {
            do {
                ledger = try JSONDecoder().decode(BotLedger.self, from: try await client.send("/bots", timeout: 30))
                ledgerAt = Date()
                error = nil
            } catch let failure as RemoteBotClient.ServerError {
                error = failure.message
                return
            } catch let failure {
                error = failure.localizedDescription
                return
            }
        }
        if let data = try? await client.send(prefix + "/mt5/trading", timeout: 15),
           let fresh = try? JSONDecoder().decode(BotAccount.self, from: data) {
            account = fresh
        }
    }

    /// Each MT5 position's P/L from the account read last (every 2 s) instead of the bot's (every 8 s).
    func withLiveProfits(_ positions: [BotBook.Open]) -> [BotBook.Open] {
        guard let live = account?.positions, !live.isEmpty else { return positions }
        var byTicket: [Int: Double] = [:]
        for p in live { if let t = p.ticket, let profit = p.profit { byTicket[t] = profit } }
        return positions.map { p in
            var q = p
            if let t = p.ticket, let profit = byTicket[t] { q.profit = profit }
            return q
        }
    }
}

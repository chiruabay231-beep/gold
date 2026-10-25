import Foundation
import Observation
import BacktestKit

/// Bar replay on the live chart, like TradingView's: pick a bar, the chart
/// hides everything after it, then bars are revealed one by one (stepping
/// or playing) while the replay demo account trades them.
@MainActor
@Observable
final class ReplaySession {
    /// Bars per second while playing.
    static let speeds: [Double] = [0.5, 1, 2, 5, 10, 20]

    private(set) var isActive = false
    /// Waiting for a tap on the chart to choose the start bar.
    private(set) var isPicking = false
    /// The bar tapped while picking: shown on the chart, started from with "Bắt đầu".
    private(set) var candidate: Int?
    private(set) var isPlaying = false
    var speed: Double = 2
    private(set) var history: [Candle] = []
    /// Index of the last visible bar.
    private(set) var cursor = 0
    private(set) var symbolKey = ""

    @ObservationIgnored private weak var trader: PaperTrader?
    @ObservationIgnored private var playTask: Task<Void, Never>?

    /// Bars shown on the chart: everything up to the cursor.
    private(set) var visibleCandles: [Candle] = []

    private func refresh() {
        visibleCandles = isActive && !history.isEmpty ? Array(history[...min(cursor, history.count - 1)]) : []
    }

    var currentBar: Candle? { history.indices.contains(cursor) ? history[cursor] : nil }
    var atEnd: Bool { cursor >= history.count - 1 }

    /// Enters replay with a snapshot of the chart's bars and waits for the start bar.
    func begin(candles: [Candle], symbolKey: String, trader: PaperTrader) {
        guard candles.count > 20 else { return }
        history = candles
        cursor = candles.count - 1
        self.symbolKey = symbolKey
        self.trader = trader
        isActive = true
        isPicking = true
        isPlaying = false
        candidate = nil
        refresh()
        trader.beginReplay()
    }

    /// Marks the tapped bar as the start (another tap moves it); nothing is hidden yet.
    func choose(index: Int) {
        guard isActive, isPicking else { return }
        candidate = min(max(index, 10), history.count - 2)
    }

    /// Starts from the chosen bar.
    func startFromCandidate() {
        guard let candidate else { return }
        pick(index: candidate)
    }

    /// Starts the replay right after `index`; later bars are hidden.
    func pick(index: Int) {
        guard isActive else { return }
        pause()
        cursor = min(max(index, 10), history.count - 2)
        isPicking = false
        candidate = nil
        refresh()
        trader?.beginReplay()
    }

    /// Lets the user choose a new start bar.
    func repick() {
        pause()
        cursor = history.count - 1
        isPicking = true
        candidate = nil
        refresh()
    }

    /// Reveals the next bar and lets the replay account trade it.
    func step() {
        guard isActive, !isPicking, cursor < history.count - 1 else {
            pause()
            return
        }
        cursor += 1
        visibleCandles.append(history[cursor])
        trader?.replay(bar: history[cursor], symbol: symbolKey, closed: visibleCandles)
    }

    func play() {
        guard isActive, !isPicking, !atEnd else { return }
        isPlaying = true
        playTask?.cancel()
        playTask = Task { [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                self.step()
                let delay = 1 / max(self.speed, 0.1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func pause() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    /// The replay's "now": the end of the last bar shown.
    func currentTime(barSeconds: TimeInterval) -> Date? {
        currentBar.map { $0.time.addingTimeInterval(barSeconds) }
    }

    /// Another timeframe's bars: the replay goes on from the same moment (the last bar
    /// closed by `time`), or, while choosing the start bar, shows them all to pick from.
    func switchTimeframe(candles: [Candle], until time: Date?, barSeconds: TimeInterval) {
        guard isActive, candles.count > 20 else { return }
        pause()
        history = candles
        if let time, !isPicking {
            let last = candles.lastIndex { $0.time.addingTimeInterval(barSeconds) <= time } ?? 10
            cursor = min(max(last, 10), candles.count - 2)
        } else {
            cursor = candles.count - 1
        }
        refresh()
    }

    /// Older bars loaded while replaying go in front; the cursor keeps its bar.
    func prepend(_ older: [Candle]) {
        guard isActive, let first = history.first else { return }
        let fresh = older.filter { $0.time < first.time }
        guard !fresh.isEmpty else { return }
        history.insert(contentsOf: fresh, at: 0)
        cursor += fresh.count
        refresh()
    }

    /// Leaves replay; returns the replay account for a summary.
    @discardableResult
    func end() -> PaperAccount? {
        pause()
        isActive = false
        isPicking = false
        history = []
        cursor = 0
        refresh()
        return trader?.endReplay()
    }
}

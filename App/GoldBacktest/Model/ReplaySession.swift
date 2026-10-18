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
        refresh()
        trader.beginReplay()
    }

    /// Starts the replay right after `index`; later bars are hidden.
    func pick(index: Int) {
        guard isActive else { return }
        pause()
        cursor = min(max(index, 10), history.count - 2)
        isPicking = false
        refresh()
        trader?.beginReplay()
    }

    /// Lets the user choose a new start bar.
    func repick() {
        pause()
        cursor = history.count - 1
        isPicking = true
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

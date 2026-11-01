import Foundation

/// The mood a chart mascot shows. The buyer is glad when the price runs up, the seller when it runs down.
public enum MascotMood: String, CaseIterable, Sendable {
    case rich, happy, tea, sleep, nervous, cry, shock, angry, trophy

    /// What the mood means, for a tooltip or an accessibility label.
    public var title: String {
        switch self {
        case .rich: return "Lãi đậm"
        case .happy: return "Vui mừng"
        case .tea: return "Nhâm nhi trà (đi ngang)"
        case .sleep: return "Ngủ gật (im lìm)"
        case .nervous: return "Hồi hộp (sắp có tin)"
        case .cry: return "Khóc (giá đi ngược)"
        case .shock: return "Hồn lìa khỏi xác"
        case .angry: return "Tức điên (dính SL)"
        case .trophy: return "Ăn mừng TP"
        }
    }

    /// - Parameters:
    ///   - wantsUp: the buyer (true) or the seller (false).
    ///   - newsSoon: a red news comes within the next minutes.
    ///   - tradeResult: a trade closed a moment ago: true in profit, false at a loss.
    /// The last five bars' move against the average bar range of the last 40 decides the rest: past 2.2
    /// ranges rich / shock, past 0.6 happy / cry; otherwise asleep when the bars are tiny, else tea.
    public static func of(_ candles: [Candle], wantsUp: Bool, newsSoon: Bool = false, tradeResult: Bool? = nil) -> MascotMood {
        if let win = tradeResult { return win ? .trophy : .angry }
        if newsSoon { return .nervous }
        let n = candles.count
        guard n >= 12 else { return .tea }
        func range(_ bars: ArraySlice<Candle>) -> Double { bars.reduce(0) { $0 + $1.high - $1.low } / Double(bars.count) }
        var average = range(candles.suffix(40))
        if average <= 0 { average = 1 }
        let move = (candles[n - 1].close - candles[n - 6].close) / average * (wantsUp ? 1 : -1)
        if move >= 2.2 { return .rich }
        if move >= 0.6 { return .happy }
        if move <= -2.2 { return .shock }
        if move <= -0.6 { return .cry }
        if n > 40, range(candles.suffix(8)) < average * 0.4 { return .sleep }
        return .tea
    }
}

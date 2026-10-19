import Foundation

/// What a headline is about, as far as gold is concerned.
public enum NewsCategory: String, CaseIterable, Sendable {
    case geopolitics, trade, centralBank, economic, politics, dollar, risk, flows

    public var title: String {
        switch self {
        case .geopolitics: return "Địa chính trị / chiến sự"
        case .trade: return "Thuế quan / thương mại"
        case .centralBank: return "Fed / ngân hàng trung ương"
        case .economic: return "Số liệu kinh tế"
        case .politics: return "Chính trị Mỹ"
        case .dollar: return "USD / lợi suất"
        case .risk: return "Thị trường / khủng hoảng"
        case .flows: return "Dòng tiền vàng"
        }
    }

    public var symbol: String {
        switch self {
        case .geopolitics: return "⚔️"
        case .trade: return "🚢"
        case .centralBank: return "🏦"
        case .economic: return "📊"
        case .politics: return "🏛️"
        case .dollar: return "💵"
        case .risk: return "📉"
        case .flows: return "🪙"
        }
    }

    /// Keywords, lower case. Single English words match whole words; phrases
    /// and Vietnamese match anywhere in the title.
    var keywords: [String] {
        switch self {
        case .geopolitics:
            return ["war", "missile", "missiles", "attack", "attacks", "airstrike", "airstrikes", "strike on", "iran", "israel",
                    "gaza", "hamas", "hezbollah", "houthi", "houthis", "russia", "ukraine", "putin", "zelensky", "nato",
                    "taiwan", "north korea", "military", "troops", "ceasefire", "drone", "drones", "nuclear", "invasion",
                    "geopolitical", "middle east",
                    "chiến sự", "chiến tranh", "xung đột", "tên lửa", "tấn công", "không kích", "ngừng bắn", "hạt nhân",
                    "địa chính trị", "trung đông", "quân sự"]
        case .trade:
            return ["tariff", "tariffs", "trade war", "trade deal", "trade talks", "sanction", "sanctions", "export ban",
                    "export controls", "thuế quan", "thương mại", "trừng phạt", "áp thuế"]
        case .centralBank:
            return ["fed", "fomc", "powell", "rate cut", "rate cuts", "rate hike", "rate hikes", "interest rate",
                    "interest rates", "ecb", "lagarde", "boj", "pboc", "central bank", "central banks", "monetary policy",
                    "lãi suất", "ngân hàng trung ương", "cắt giảm lãi suất", "chính sách tiền tệ"]
        case .economic:
            return ["cpi", "inflation", "jobs report", "payrolls", "nonfarm", "nfp", "gdp", "pmi", "unemployment",
                    "jobless", "retail sales", "pce", "ppi", "lạm phát", "việc làm", "bảng lương", "thất nghiệp", "tăng trưởng gdp"]
        case .politics:
            return ["trump", "white house", "congress", "senate", "election", "shutdown", "impeachment", "debt ceiling",
                    "executive order", "nhà trắng", "bầu cử", "quốc hội", "đóng cửa chính phủ", "tổng thống"]
        case .dollar:
            return ["dollar", "dxy", "greenback", "treasury", "treasuries", "yield", "yields", "bond", "bonds",
                    "đồng usd", "đồng đô la", "lợi suất", "trái phiếu", "chỉ số usd"]
        case .risk:
            return ["sell-off", "selloff", "crash", "plunge", "plunges", "rout", "crisis", "recession", "bank failure",
                    "panic", "safe haven", "safe-haven", "khủng hoảng", "suy thoái", "bán tháo", "lao dốc", "trú ẩn"]
        case .flows:
            return ["etf", "spdr", "gold reserves", "gold buying", "gold demand", "central bank buying", "record high",
                    "all-time high", "mua vàng", "dự trữ vàng", "kỷ lục", "nhu cầu vàng"]
        }
    }

    /// The most important category a title mentions (geopolitics first), if any.
    public static func classify(_ title: String) -> NewsCategory? {
        let lower = title.lowercased()
        let words = Set(lower.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init))
        for category in allCases {
            for keyword in category.keywords {
                let isWord = !keyword.contains(" ") && keyword.unicodeScalars.allSatisfy { $0.isASCII }
                if isWord ? words.contains(keyword) : lower.contains(keyword) { return category }
            }
        }
        return nil
    }
}

/// A headline with its category.
public struct TaggedHeadline: Hashable, Identifiable, Sendable {
    public var headline: NewsHeadline
    public var category: NewsCategory?
    public var id: String { headline.id }

    public init(headline: NewsHeadline, category: NewsCategory?) {
        self.headline = headline
        self.category = category
    }
}

/// A sudden move: price went `change` within a few bars.
public struct PriceSpike: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var startPrice: Double
    public var endPrice: Double

    public var change: Double { endPrice - startPrice }
    public var percent: Double { startPrice == 0 ? 0 : change / startPrice * 100 }
    public var isUp: Bool { change > 0 }
}

/// A sudden move with the news around it.
public struct MoveExplanation: Identifiable, Sendable {
    public var spike: PriceSpike
    /// Calendar events released right before or during the move.
    public var events: [EconomicEvent]
    /// Related headlines from shortly before to shortly after, most likely first.
    public var headlines: [TaggedHeadline]

    public var id: Date { spike.start }

    /// Best guess: the economic release, else the top headline's topic; nil = no news found.
    public var cause: NewsCategory? { events.isEmpty ? headlines.first?.category : .economic }
}

public enum MarketMoves {
    /// Moves over `window` bars that are at least `multiplier` times the usual
    /// move of that length and at least `minPercent` %. Overlapping bars are
    /// merged into one move, measured to its most extreme point.
    public static func spikes(_ c: [Candle], window: Int = 5, multiplier: Double = 4,
                              minPercent: Double = 0.2) -> [PriceSpike] {
        let w = max(window, 1)
        guard c.count > w * 4 else { return [] }
        let moves = (w..<c.count).map { c[$0].close - c[$0 - w].close }
        let typical = median(moves.map(abs))
        var result: [PriceSpike] = []
        var k = 0
        while k < moves.count {
            let i = k + w
            let threshold = max(typical * multiplier, c[i - w].close * minPercent / 100)
            guard abs(moves[k]) >= threshold, threshold > 0 else {
                k += 1
                continue
            }
            // Extend while the move keeps going the same way, keep the strongest point.
            let up = moves[k] > 0
            var best = k
            var j = k + 1
            while j < moves.count, (moves[j] > 0) == up, abs(moves[j]) >= threshold * 0.6 {
                if abs(moves[j]) > abs(moves[best]) { best = j }
                j += 1
            }
            let endIndex = best + w
            let startIndex = best
            result.append(PriceSpike(start: c[startIndex].time, end: c[endIndex].time,
                                     startPrice: c[startIndex].close, endPrice: c[endIndex].close))
            k = j + w   // the next move starts after this one
        }
        return result
    }

    /// Matches each move with calendar events and categorised headlines around it.
    public static func explain(_ spikes: [PriceSpike], events: [EconomicEvent], headlines: [NewsHeadline],
                               before: TimeInterval = 90 * 60, after: TimeInterval = 30 * 60) -> [MoveExplanation] {
        let important = events.filter { $0.impact >= .medium }
        let tagged = headlines.compactMap { h -> TaggedHeadline? in
            guard h.date != nil, let category = NewsCategory.classify(h.title) else { return nil }
            return TaggedHeadline(headline: h, category: category)
        }
        return spikes.map { spike in
            let released = important.filter {
                $0.date >= spike.start.addingTimeInterval(-10 * 60) && $0.date <= spike.end.addingTimeInterval(2 * 60)
            }
            let nearby = tagged.filter {
                guard let date = $0.headline.date else { return false }
                return date >= spike.start.addingTimeInterval(-before) && date <= spike.end.addingTimeInterval(after)
            }
            let order = NewsCategory.allCases
            let ranked = nearby.sorted { a, b in
                let ra = order.firstIndex(of: a.category ?? .flows) ?? 99
                let rb = order.firstIndex(of: b.category ?? .flows) ?? 99
                if ra != rb { return ra < rb }
                return abs(a.headline.date!.timeIntervalSince(spike.start)) < abs(b.headline.date!.timeIntervalSince(spike.start))
            }
            return MoveExplanation(spike: spike, events: released, headlines: Array(ranked.prefix(5)))
        }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

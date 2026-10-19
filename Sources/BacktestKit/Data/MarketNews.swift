import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One event of the weekly economic calendar (Forex Factory feed).
public struct EconomicEvent: Hashable, Identifiable, Sendable {
    public enum Impact: String, Sendable, Comparable {
        case high = "High", medium = "Medium", low = "Low", holiday = "Holiday", none = ""

        /// Red, orange, yellow, grey in the usual calendar colours.
        public var rank: Int {
            switch self {
            case .high: return 3
            case .medium: return 2
            case .low: return 1
            case .holiday, .none: return 0
            }
        }

        public static func < (a: Impact, b: Impact) -> Bool { a.rank < b.rank }
    }

    public var id: String { "\(country)-\(date.timeIntervalSince1970)-\(title)" }
    public var title: String
    public var country: String
    public var date: Date
    public var impact: Impact
    public var forecast: String
    public var previous: String
}

/// A news headline from an RSS feed.
public struct NewsHeadline: Hashable, Identifiable, Sendable {
    public var id: String { link }
    public var title: String
    public var link: String
    public var source: String
    public var date: Date?
}

/// Downloads the economic calendar and gold headlines.
public enum MarketNews {
    /// This week's calendar from Forex Factory (free JSON mirror).
    public static let calendarURL = URL(string: "https://nfs.faireconomy.media/ff_calendar_thisweek.json")!

    /// Google News search for gold / XAUUSD headlines.
    public static func headlinesURL(vietnamese: Bool) -> URL {
        let query = vietnamese ? "giá vàng thế giới OR XAUUSD" : "gold price OR XAUUSD OR Fed"
        return googleNewsURL(query: query + " when:2d", vietnamese: vietnamese)
    }

    /// Searches for news that moves gold besides the calendar: geopolitics,
    /// tariffs, the Fed, US politics, the dollar and market stress (last day).
    public static func breakingURLs(vietnamese: Bool) -> [URL] {
        var queries = [
            "gold OR XAUUSD OR bullion when:1d",
            "Fed OR Powell OR tariff OR tariffs OR sanctions OR Trump when:1d",
            "war OR missile OR attack OR Iran OR Israel OR Russia OR Ukraine OR Taiwan OR ceasefire when:1d",
            "dollar OR treasury yields OR sell-off OR crisis when:1d",
        ].map { googleNewsURL(query: $0, vietnamese: false) }
        if vietnamese {
            queries += [
                "giá vàng when:1d",
                "chiến sự OR xung đột OR thuế quan OR Fed OR lãi suất when:1d",
            ].map { googleNewsURL(query: $0, vietnamese: true) }
        }
        return queries
    }

    static func googleNewsURL(query: String, vietnamese: Bool) -> URL {
        var components = URLComponents(string: "https://news.google.com/rss/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: vietnamese ? "vi" : "en-US"),
            URLQueryItem(name: "gl", value: vietnamese ? "VN" : "US"),
            URLQueryItem(name: "ceid", value: vietnamese ? "VN:vi" : "US:en"),
        ]
        return components.url!
    }

    /// Parses the Forex Factory JSON: `[{"title","country","date","impact","forecast","previous"}]`.
    public static func parseCalendar(_ data: Data) throws -> [EconomicEvent] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return rows.compactMap { row in
            guard let title = row["title"] as? String, let dateText = row["date"] as? String,
                  let date = iso.date(from: dateText) else { return nil }
            return EconomicEvent(title: title, country: row["country"] as? String ?? "", date: date,
                                 impact: EconomicEvent.Impact(rawValue: row["impact"] as? String ?? "") ?? .none,
                                 forecast: row["forecast"] as? String ?? "", previous: row["previous"] as? String ?? "")
        }
        .sorted { $0.date < $1.date }
    }

    /// Events that move gold: USD news at the given minimum impact.
    public static func goldEvents(_ events: [EconomicEvent], minimum: EconomicEvent.Impact = .medium,
                                  currencies: Set<String> = ["USD"]) -> [EconomicEvent] {
        events.filter { $0.impact >= minimum && (currencies.isEmpty || currencies.contains($0.country)) }
    }

    /// Parses RSS 2.0 `<item>`s (title, link, pubDate, source).
    public static func parseRSS(_ data: Data) -> [NewsHeadline] {
        let delegate = RSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    public static func load(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("GoldBacktest/1.0", forHTTPHeaderField: "User-Agent")
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continuation.resume(throwing: URLError(.badServerResponse))
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }.resume()
        }
    }
}

private final class RSSParser: NSObject, XMLParserDelegate {
    var items: [NewsHeadline] = []
    private var inItem = false
    private var element = ""
    private var title = "", link = "", source = "", date = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        if elementName == "item" {
            inItem = true
            title = ""; link = ""; source = ""; date = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "source": source += string
        case "pubDate": date += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            inItem = false
            var headline = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceName = source.trimmingCharacters(in: .whitespacesAndNewlines)
            // Google News appends " - Source" to titles.
            if !sourceName.isEmpty, headline.hasSuffix(" - " + sourceName) {
                headline = String(headline.dropLast(sourceName.count + 3))
            }
            let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !headline.isEmpty, !url.isEmpty {
                items.append(NewsHeadline(title: headline, link: url, source: sourceName,
                                          date: Self.dateFormatter.date(from: date.trimmingCharacters(in: .whitespacesAndNewlines))))
            }
        }
        element = ""
    }
}

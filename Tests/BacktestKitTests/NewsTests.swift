import XCTest
@testable import BacktestKit

final class NewsTests: XCTestCase {
    func testCalendarParsingAndGoldFilter() throws {
        let json = """
        [{"title":"Non-Farm Employment Change","country":"USD","date":"2026-10-23T08:30:00-04:00","impact":"High","forecast":"150K","previous":"142K"},
         {"title":"German ifo","country":"EUR","date":"2026-10-22T04:00:00-04:00","impact":"High","forecast":"","previous":""},
         {"title":"Crude Oil Inventories","country":"USD","date":"2026-10-22T10:30:00-04:00","impact":"Medium","forecast":"","previous":""},
         {"title":"Bank Holiday","country":"USD","date":"2026-10-21T00:00:00-04:00","impact":"Holiday","forecast":"","previous":""}]
        """
        let events = try MarketNews.parseCalendar(Data(json.utf8))
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first?.title, "Bank Holiday")   // sorted by time
        let gold = MarketNews.goldEvents(events)
        XCTAssertEqual(gold.map(\.title), ["Crude Oil Inventories", "Non-Farm Employment Change"])
        XCTAssertEqual(MarketNews.goldEvents(events, minimum: .high).first?.forecast, "150K")
        XCTAssertEqual(gold.last?.date, Date(timeIntervalSince1970: 1_792_758_600))
    }

    func testRSSParsing() {
        let xml = """
        <?xml version="1.0"?><rss><channel><title>x</title>
        <item><title>Gold hits record as Fed cuts - Reuters</title><link>https://example.com/a</link>
        <pubDate>Mon, 19 Oct 2026 07:00:00 GMT</pubDate><source url="https://reuters.com">Reuters</source></item>
        <item><title>No link</title></item>
        </channel></rss>
        """
        let items = MarketNews.parseRSS(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Gold hits record as Fed cuts")
        XCTAssertEqual(items[0].source, "Reuters")
        XCTAssertNotNil(items[0].date)
    }
}

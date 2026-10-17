import XCTest
@testable import BacktestKit

final class DataTests: XCTestCase {
    func testHeaderCSV() throws {
        let csv = """
        time,open,high,low,close,volume
        2024-01-02 01:00:00,2063.5,2065.1,2061.0,2064.2,1200
        2024-01-02 00:00:00,2062.0,2064.0,2060.5,2063.5,900
        """
        let candles = try CSVParser().parse(csv)
        XCTAssertEqual(candles.count, 2)
        XCTAssertEqual(candles[0].open, 2062.0)   // sorted by time
        XCTAssertEqual(candles[1].volume, 1200)
    }

    func testMT5Export() throws {
        let csv = "<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\t<TICKVOL>\t<VOL>\t<SPREAD>\n"
            + "2024.01.02\t00:00:00\t2062.0\t2064.0\t2060.5\t2063.5\t900\t0\t12\n"
            + "2024.01.02\t01:00:00\t2063.5\t2065.1\t2061.0\t2064.2\t1200\t0\t12\n"
        let candles = try CSVParser().parse(csv)
        XCTAssertEqual(candles.count, 2)
        XCTAssertEqual(candles[1].time.timeIntervalSince(candles[0].time), 3600)
        XCTAssertEqual(candles[1].volume, 1200)
    }

    func testDecodeUTF16() throws {
        let csv = "<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\n2024.01.02\t00:00\t1\t2\t0.5\t1.5\n"
        var data = Data([0xFF, 0xFE])
        data.append(csv.data(using: .utf16LittleEndian)!)
        let text = try XCTUnwrap(CSVParser.decodeText(data))
        XCTAssertEqual(try CSVParser().parse(text).first?.close, 1.5)
        XCTAssertEqual(CSVParser.decodeText(Data("\u{FEFF}a,b".utf8)), "a,b")
    }

    func testHeaderlessUnixMillis() throws {
        let csv = "1704153600000;100;110;90;105\n1704157200000;105;115;95;110\n"
        let candles = try CSVParser().parse(csv)
        XCTAssertEqual(candles.count, 2)
        XCTAssertEqual(candles[0].time, Date(timeIntervalSince1970: 1_704_153_600))
        XCTAssertEqual(candles[1].close, 110)
    }

    func testRoundTripAndErrors() throws {
        let original = SampleData.candles(count: 50)
        let parsed = try CSVParser().parse(CSVParser.export(original))
        XCTAssertEqual(parsed.count, 50)
        XCTAssertEqual(parsed[10].close, original[10].close, accuracy: 1e-9)
        XCTAssertEqual(parsed[10].time, original[10].time)

        XCTAssertThrowsError(try CSVParser().parse(""))
        XCTAssertThrowsError(try CSVParser().parse("time,open,high,low\n2024-01-01,1,2,0\n"))
        XCTAssertThrowsError(try CSVParser().parse("time,open,high,low,close\nabc,1,2,0,1\n"))
    }

    func testFastDateParserMatchesFormatter() {
        let utc = DateParser(timeZone: TimeZone(identifier: "UTC")!)
        let reference = Date(timeIntervalSince1970: 1_704_164_645)   // 2024-01-02 03:04:05 UTC
        for text in ["2024-01-02 03:04:05", "2024-01-02T03:04:05Z", "2024.01.02 03:04:05",
                     "02.01.2024 03:04:05", "2024-01-02T10:04:05+07:00", "2024-01-01T22:04:05-05:00",
                     "2024/01/02 03:04:05"] {
            XCTAssertEqual(utc.fastParse(text), reference, text)
        }
        XCTAssertEqual(utc.fastParse("2024-01-02 03:04:05.250")?.timeIntervalSince1970 ?? 0, 1_704_164_645.25, accuracy: 1e-6)
        XCTAssertEqual(utc.fastParse("2024-01-02"), Date(timeIntervalSince1970: 1_704_153_600))
        XCTAssertNil(utc.fastParse("01/02/2024 03:04"))   // ambiguous: left to DateFormatter
        XCTAssertNil(utc.fastParse("2024-13-02"))

        let vietnam = DateParser(timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!)
        XCTAssertEqual(vietnam.fastParse("2024-01-02 10:04:05"), reference)
        // MM/dd/yyyy still works through DateFormatter.
        XCTAssertEqual(utc.parse("01/02/2024 03:04:05"), reference)
    }

    func testBinanceParsing() throws {
        let json = """
        [[1704153600000,"42000.1","42100.0","41900.5","42050.0","12.5",1704157199999,"0",1,"0","0","0"]]
        """
        let candles = try BinanceClient.parseKlines(Data(json.utf8))
        XCTAssertEqual(candles.count, 1)
        XCTAssertEqual(candles[0].high, 42100)
        XCTAssertEqual(candles[0].time, Date(timeIntervalSince1970: 1_704_153_600))
    }

    func testCandleCodecRoundTrip() throws {
        let candles = SampleData.candles(count: 300)
        XCTAssertEqual(try CandleCodec.decode(CandleCodec.encode(candles)), candles)
        XCTAssertEqual(try CandleCodec.decode(CandleCodec.encode([])), [])
        XCTAssertThrowsError(try CandleCodec.decode(Data("nope".utf8)))
    }

    func testSampleDataIsDeterministicAndValid() {
        XCTAssertEqual(SampleData.candles(count: 100), SampleData.candles(count: 100))
        for c in SampleData.candles(count: 500) {
            XCTAssertLessThanOrEqual(c.low, min(c.open, c.close))
            XCTAssertGreaterThanOrEqual(c.high, max(c.open, c.close))
        }
    }
}

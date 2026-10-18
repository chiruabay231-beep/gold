import XCTest
@testable import BacktestKit

final class LiveTests: XCTestCase {
    func testParseCombinedKline() throws {
        let json = """
        {"stream":"btcusdt@kline_1m","data":{"e":"kline","E":1700000005000,"s":"BTCUSDT","k":{"t":1700000000000,"T":1700000059999,"s":"BTCUSDT","i":"1m","f":1,"L":2,"o":"37000.10","c":"37010.50","h":"37020.00","l":"36990.00","v":"12.5","n":10,"x":false,"q":"0","V":"0","Q":"0","B":"0"}}}
        """
        guard case .kline(let symbol, let candle, let closed)? = BinanceStreamEvent.parse(Data(json.utf8)) else {
            return XCTFail("not parsed")
        }
        XCTAssertEqual(symbol, "BTCUSDT")
        XCTAssertFalse(closed)
        XCTAssertEqual(candle.time, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(candle.close, 37010.5)
        XCTAssertEqual(candle.volume, 12.5)
    }

    func testParseTicker() {
        let json = """
        {"e":"24hrTicker","E":1,"s":"PAXGUSDT","p":"5.0","P":"0.21","c":"2410.5","h":"2420.0","l":"2390.0","v":"1500","q":"3600000"}
        """
        guard case .ticker(let t)? = BinanceStreamEvent.parse(Data(json.utf8)) else { return XCTFail() }
        XCTAssertEqual(t.lastPrice, 2410.5)
        XCTAssertEqual(t.changePercent, 0.21)
        XCTAssertEqual(t.quoteVolume, 3_600_000)
        XCTAssertNil(BinanceStreamEvent.parse(Data("{\"result\":null,\"id\":1}".utf8)))
    }

    func testStreamURL() {
        let url = BinanceStreamEvent.url(host: BinanceClient.streamHosts[0], symbol: "PAXGUSDT", interval: .m15)
        XCTAssertEqual(url.absoluteString, "wss://stream.binance.com:9443/stream?streams=paxgusdt@kline_15m/paxgusdt@ticker")
        let futures = BinanceStreamEvent.url(host: BinanceClient.Market.futures.streamHosts[0], symbol: "XAUUSDT", interval: .m1)
        XCTAssertEqual(futures.absoluteString, "wss://fstream.binance.com/market/stream?streams=xauusdt@kline_1m/xauusdt@ticker")
        XCTAssertEqual(BinanceClient.Market.futures.apiPrefix, "fapi/v1")
    }

    func testBuffer() {
        let t0 = Date(timeIntervalSince1970: 0)
        var buffer = LiveCandleBuffer(candles: [Candle(time: t0, open: 1, high: 1, low: 1, close: 1)], maxCount: 2)
        XCTAssertEqual(buffer.apply(Candle(time: t0, open: 1, high: 2, low: 1, close: 2)), .updatedLast)
        XCTAssertEqual(buffer.candles.last?.close, 2)
        XCTAssertEqual(buffer.apply(Candle(time: t0.addingTimeInterval(60), open: 2, high: 2, low: 2, close: 2)), .appended)
        XCTAssertEqual(buffer.apply(Candle(time: t0.addingTimeInterval(-60), open: 0, high: 0, low: 0, close: 0)), .ignored)
        XCTAssertEqual(buffer.apply(Candle(time: t0.addingTimeInterval(120), open: 3, high: 3, low: 3, close: 3)), .appended)
        XCTAssertEqual(buffer.candles.count, 2)
        XCTAssertEqual(buffer.candles.first?.time, t0.addingTimeInterval(60))
    }

    func testScannerListsSignalsWithLevels() throws {
        let candles = SampleData.candles(count: 800)
        let strategy = Samples.strategies[0]   // EMA cross with ATR stops
        let scan = try LiveSignalScanner.scan(strategy: strategy, candles: candles, config: BacktestConfig(),
                                              library: .standard)
        XCTAssertFalse(scan.signals.isEmpty)
        let entry = try XCTUnwrap(scan.signals.first { $0.kind == .longEntry })
        XCTAssertNotNil(entry.stop)
        XCTAssertLessThan(entry.stop!, entry.price)
        XCTAssertGreaterThan(entry.target!, entry.price)
        XCTAssertEqual(scan.plots.count, 2)
        // Disallowed directions are not reported.
        let longOnly = try LiveSignalScanner.scan(strategy: strategy, candles: candles,
                                                  config: BacktestConfig(allowShort: false), library: .standard)
        XCTAssertFalse(longOnly.signals.contains { $0.kind == .shortEntry })
    }

    func testParseOandaCandles() throws {
        let json = """
        {"instrument":"XAU_USD","granularity":"M15","candles":[
          {"complete":true,"volume":412,"time":"1700000000.000000000","bid":{"o":"1980.105","h":"1982.500","l":"1979.010","c":"1981.900"}},
          {"complete":false,"volume":37,"time":"1700000900.000000000","bid":{"o":"1981.900","h":"1982.100","l":"1981.300","c":"1981.700"}}]}
        """
        let candles = try OandaClient.parseCandles(Data(json.utf8))
        XCTAssertEqual(candles.count, 2)
        XCTAssertEqual(candles[0].candle.time, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(candles[0].candle.high, 1982.5)
        XCTAssertEqual(candles[0].candle.volume, 412)
        XCTAssertTrue(candles[0].complete)
        XCTAssertFalse(candles[1].complete)
        XCTAssertThrowsError(try OandaClient.parseCandles(Data("{\"errorMessage\":\"x\"}".utf8)))
        XCTAssertEqual(OandaClient.errorMessage(Data("{\"errorMessage\":\"Insufficient authorization\"}".utf8)),
                       "Insufficient authorization")
    }

    func testOandaTokenAndGranularity() {
        XCTAssertTrue(OandaClient.looksLikeToken(" " + String(repeating: "a1", count: 16) + "-" + String(repeating: "f0", count: 16) + "\n"))
        XCTAssertFalse(OandaClient.looksLikeToken("efa4bf7b-9387-462d-b287-9e952173b57f"))
        XCTAssertEqual(OandaClient.granularity(.m15), "M15")
        XCTAssertEqual(OandaClient.granularity(.d1), "D")
    }
}

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

    func testSecondsBarsFromTrades() throws {
        let t0 = 1_700_000_010.0   // a multiple of 5, 15 and 30 seconds
        let trades = [TradeTick(time: Date(timeIntervalSince1970: t0 + 1), price: 10, quantity: 1),
                      TradeTick(time: Date(timeIntervalSince1970: t0 + 3), price: 12, quantity: 2),
                      TradeTick(time: Date(timeIntervalSince1970: t0 + 4.9), price: 9, quantity: 1),
                      TradeTick(time: Date(timeIntervalSince1970: t0 + 6), price: 11, quantity: 1)]
        let bars = CandleAggregator.candles(from: trades, seconds: 5)
        XCTAssertEqual(bars.count, 2)
        XCTAssertEqual(bars[0].time, Date(timeIntervalSince1970: t0))
        XCTAssertEqual([bars[0].open, bars[0].high, bars[0].low, bars[0].close, bars[0].volume], [10, 12, 9, 9, 4])
        XCTAssertEqual(bars[1].time, Date(timeIntervalSince1970: t0 + 5))

        var buffer = LiveCandleBuffer(candles: bars)
        XCTAssertEqual(buffer.apply(trade: TradeTick(time: Date(timeIntervalSince1970: t0 + 9), price: 13, quantity: 1), seconds: 5), .updatedLast)
        XCTAssertEqual(buffer.candles.last?.high, 13)
        XCTAssertEqual(buffer.apply(trade: TradeTick(time: Date(timeIntervalSince1970: t0 + 10), price: 14, quantity: 1), seconds: 5), .appended)
        XCTAssertEqual(buffer.candles.last?.open, 14)

        let oneSecond: [Candle] = (0..<30).map { (i: Int) -> Candle in
            let v = Double(i)
            return Candle(time: Date(timeIntervalSince1970: t0 + v), open: v, high: v + 1, low: v - 1, close: v + 0.5, volume: 1)
        }
        let resampled = CandleAggregator.resample(oneSecond, seconds: 15)
        XCTAssertEqual(resampled.count, 2)
        XCTAssertEqual(resampled[0].open, 0)
        XCTAssertEqual(resampled[0].high, 15)
        XCTAssertEqual(resampled[0].low, -1)
        XCTAssertEqual(resampled[0].close, 14.5)
        XCTAssertEqual(resampled[1].volume, 15)
    }

    func testAggTradeMessagesAndURL() throws {
        let json = """
        {"stream":"xauusdt@aggTrade","data":{"e":"aggTrade","E":1700000001000,"s":"XAUUSDT","a":5,"p":"4012.35","q":"0.250","f":1,"l":2,"T":1700000000500,"m":false}}
        """
        guard case .trade(let symbol, let tick)? = BinanceStreamEvent.parse(Data(json.utf8)) else { return XCTFail() }
        XCTAssertEqual(symbol, "XAUUSDT")
        XCTAssertEqual(tick.price, 4012.35)
        XCTAssertEqual(tick.time, Date(timeIntervalSince1970: 1_700_000_000.5))
        let url = BinanceStreamEvent.url(host: BinanceClient.Market.futures.streamHosts[0], symbol: "XAUUSDT", interval: .s5)
        XCTAssertEqual(url.absoluteString, "wss://fstream.binance.com/market/stream?streams=xauusdt@aggTrade/xauusdt@ticker")
        let rest = try BinanceClient.parseAggTrades(Data("""
        [{"a":26129,"p":"0.01633102","q":"4.70443515","f":27781,"l":27781,"T":1498793709153,"m":true,"M":true}]
        """.utf8))
        XCTAssertEqual(rest.first?.id, 26129)
        XCTAssertEqual(rest.first?.tick.quantity, 4.70443515)
        XCTAssertEqual(OandaClient.granularity(.s30), "S30")
        XCTAssertTrue(BinanceClient.Interval.s15.isSeconds)
        XCTAssertFalse(BinanceClient.Interval.m1.isSeconds)
    }

    func testPrependOlderBars() {
        let t = { (i: Int) in Date(timeIntervalSince1970: Double(i) * 60) }
        var buffer = LiveCandleBuffer(candles: [Candle(time: t(10), open: 1, high: 1, low: 1, close: 1)], maxCount: 3)
        let older = [Candle(time: t(9), open: 2, high: 2, low: 2, close: 2), Candle(time: t(10), open: 9, high: 9, low: 9, close: 9),
                     Candle(time: t(7), open: 3, high: 3, low: 3, close: 3), Candle(time: t(8), open: 4, high: 4, low: 4, close: 4)]
        XCTAssertEqual(buffer.prepend(older), 2)   // only room for 2; the newest older bars are kept
        XCTAssertEqual(buffer.candles.map(\.time), [t(8), t(9), t(10)])
        XCTAssertEqual(buffer.candles.last?.close, 1)
    }
}

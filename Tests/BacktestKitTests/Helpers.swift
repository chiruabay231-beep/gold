import Foundation
import XCTest
@testable import BacktestKit

/// Builds hourly candles from closes; open is the previous close.
func makeData(closes: [Double], spread: Double = 1) -> PriceData {
    var candles: [Candle] = []
    for (i, close) in closes.enumerated() {
        let open = i == 0 ? close : closes[i - 1]
        candles.append(Candle(time: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 3600),
                              open: open,
                              high: max(open, close) + spread,
                              low: min(open, close) - spread,
                              close: close,
                              volume: 100))
    }
    return PriceData(candles: candles)
}

func makeData(_ bars: [(o: Double, h: Double, l: Double, c: Double)]) -> PriceData {
    PriceData(candles: bars.enumerated().map { i, b in
        Candle(time: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 3600),
               open: b.o, high: b.h, low: b.l, close: b.c, volume: 100)
    })
}

func evaluate(_ script: String, _ data: PriceData, library: FunctionLibrary = .standard,
              bindings: [String: Value] = [:]) throws -> Series {
    let context = EvaluationContext(data: data, library: library)
    let result = try Evaluator.run(script, context: context, bindings: bindings)
    return result.lastValue?.series(count: data.count) ?? []
}

func assertSeries(_ actual: Series, _ expected: Series, accuracy: Double = 1e-9,
                  file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.count, expected.count, "length", file: file, line: line)
    for (i, (a, e)) in zip(actual, expected).enumerated() {
        if e.isNaN {
            XCTAssertTrue(a.isNaN, "index \(i): expected NaN, got \(a)", file: file, line: line)
        } else {
            XCTAssertEqual(a, e, accuracy: accuracy, "index \(i)", file: file, line: line)
        }
    }
}

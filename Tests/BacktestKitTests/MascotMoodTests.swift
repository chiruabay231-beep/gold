import Foundation
import XCTest
@testable import BacktestKit

final class MascotMoodTests: XCTestCase {
    private func bars(_ closes: [Double], range: Double = 1) -> [Candle] {
        closes.enumerated().map { i, c in
            Candle(time: Date(timeIntervalSince1970: Double(i) * 60), open: c, high: c + range / 2, low: c - range / 2, close: c)
        }
    }

    func testDirectionMakesOneGladAndTheOtherSad() {
        let flat = Array(repeating: 100.0, count: 40)
        let up = bars(flat + [100.5, 101, 101.5, 102, 102.5, 103])
        XCTAssertEqual(MascotMood.of(up, wantsUp: true), .rich)
        XCTAssertEqual(MascotMood.of(up, wantsUp: false), .shock)
        let small = bars(flat + [100.2, 100.4, 100.6, 100.8, 101])
        XCTAssertEqual(MascotMood.of(small, wantsUp: true), .happy)
        XCTAssertEqual(MascotMood.of(small, wantsUp: false), .cry)
    }

    func testQuietAndFlat() {
        let quiet = bars(Array(repeating: 100.0, count: 40), range: 1) + bars(Array(repeating: 100.0, count: 10), range: 0.1)
        XCTAssertEqual(MascotMood.of(quiet, wantsUp: true), .sleep)
        XCTAssertEqual(MascotMood.of(bars(Array(repeating: 100.0, count: 50)), wantsUp: false), .tea)
        XCTAssertEqual(MascotMood.of(bars([100, 101]), wantsUp: true), .tea)
    }

    func testTradesAndNewsComeFirst() {
        let up = bars(Array(repeating: 100.0, count: 40) + [101, 102, 103, 104, 105, 106])
        XCTAssertEqual(MascotMood.of(up, wantsUp: true, newsSoon: true), .nervous)
        XCTAssertEqual(MascotMood.of(up, wantsUp: true, newsSoon: true, tradeResult: false), .angry)
        XCTAssertEqual(MascotMood.of(up, wantsUp: false, tradeResult: true), .trophy)
    }
}

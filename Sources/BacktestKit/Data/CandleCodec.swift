import Foundation

/// Compact binary storage for candles: a 4-byte magic + version, then six
/// little-endian Float64 values per bar. Loading 100k bars takes milliseconds,
/// unlike re-parsing CSV or JSON.
public enum CandleCodec {
    private static let magic: [UInt8] = Array("BTK1".utf8)

    public enum CodecError: LocalizedError {
        case invalidData

        public var errorDescription: String? { "File dữ liệu nến bị hỏng." }
    }

    public static func encode(_ candles: [Candle]) -> Data {
        var values: [Double] = []
        values.reserveCapacity(candles.count * 6)
        for c in candles {
            values.append(c.time.timeIntervalSince1970)
            values.append(c.open)
            values.append(c.high)
            values.append(c.low)
            values.append(c.close)
            values.append(c.volume)
        }
        var data = Data(magic)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func decode(_ data: Data) throws -> [Candle] {
        let bytes = [UInt8](data)
        guard bytes.count >= magic.count, Array(bytes[0..<magic.count]) == magic,
              (bytes.count - magic.count) % 48 == 0
        else { throw CodecError.invalidData }
        let count = (bytes.count - magic.count) / 48
        var candles: [Candle] = []
        candles.reserveCapacity(count)
        bytes.withUnsafeBytes { raw in
            func value(_ index: Int) -> Double {
                let offset = magic.count + index * 8
                var bits: UInt64 = 0
                for k in 0..<8 { bits |= UInt64(raw[offset + k]) << (8 * UInt64(k)) }
                return Double(bitPattern: UInt64(littleEndian: bits))
            }
            for i in 0..<count {
                let base = i * 6
                candles.append(Candle(time: Date(timeIntervalSince1970: value(base)),
                                      open: value(base + 1), high: value(base + 2), low: value(base + 3),
                                      close: value(base + 4), volume: value(base + 5)))
            }
        }
        return candles
    }
}

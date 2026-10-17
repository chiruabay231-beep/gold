import Foundation

public enum CSVParseError: LocalizedError, Equatable {
    case empty
    case missingColumn(String)
    case badRow(line: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "File CSV không có dữ liệu."
        case .missingColumn(let name):
            return "Không tìm thấy cột \"\(name)\" trong file CSV."
        case .badRow(let line, let reason):
            return "Dòng \(line): \(reason)"
        }
    }
}

/// Parses OHLCV data exported by MetaTrader (MT4/MT5, Exness), TradingView,
/// Binance and most other tools.
///
/// Supported layouts:
/// - A header row with columns such as `time`/`date`/`timestamp`, `open`, `high`,
///   `low`, `close`, `volume` (case-insensitive, `<DATE>` style accepted).
/// - Separate date and time columns (MT5 export: `<DATE>\t<TIME>\t<OPEN>...`).
/// - No header: `time,open,high,low,close[,volume]`.
///
/// Delimiters `,` `;` and tab are detected automatically. Times can be unix
/// seconds / milliseconds or common date strings; they are read as UTC unless
/// `timeZone` says otherwise.
public struct CSVParser {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone = TimeZone(identifier: "UTC")!) {
        self.timeZone = timeZone
    }

    public func parse(_ text: String) throws -> [Candle] {
        let lines = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { throw CSVParseError.empty }

        let delimiter = Self.detectDelimiter(first)
        let firstFields = Self.split(first, delimiter)
        let hasHeader = firstFields.contains { field in
            let cleaned = field.trimmingCharacters(in: CharacterSet(charactersIn: "<>\" "))
            return Double(cleaned) == nil && cleaned.rangeOfCharacter(from: .letters) != nil
                && parseDate(cleaned) == nil
        }

        let layout: Layout
        if hasHeader {
            layout = try Self.layout(forHeader: firstFields)
        } else {
            guard firstFields.count >= 5 else {
                throw CSVParseError.badRow(line: 1, reason: "cần ít nhất 5 cột: time, open, high, low, close")
            }
            layout = Layout(date: 0, time: nil, open: 1, high: 2, low: 3, close: 4,
                            volume: firstFields.count > 5 ? 5 : nil)
        }

        var candles: [Candle] = []
        candles.reserveCapacity(lines.count)
        for (offset, line) in lines.enumerated() where !(hasHeader && offset == 0) {
            let fields = Self.split(line, delimiter)
            let lineNumber = offset + 1
            guard fields.count > layout.maxIndex else {
                throw CSVParseError.badRow(line: lineNumber, reason: "thiếu cột")
            }
            var timeText = fields[layout.date]
            if let timeColumn = layout.time {
                timeText += " " + fields[timeColumn]
            }
            guard let date = parseDate(timeText) else {
                throw CSVParseError.badRow(line: lineNumber, reason: "không đọc được thời gian \"\(timeText)\"")
            }
            func number(_ index: Int, _ name: String) throws -> Double {
                guard let value = Double(fields[index]) else {
                    throw CSVParseError.badRow(line: lineNumber, reason: "giá trị \(name) không hợp lệ \"\(fields[index])\"")
                }
                return value
            }
            let volume = try layout.volume.map { try number($0, "volume") } ?? 0
            candles.append(Candle(time: date,
                                  open: try number(layout.open, "open"),
                                  high: try number(layout.high, "high"),
                                  low: try number(layout.low, "low"),
                                  close: try number(layout.close, "close"),
                                  volume: volume))
        }
        guard !candles.isEmpty else { throw CSVParseError.empty }
        return Self.normalize(candles)
    }

    /// Decodes file bytes as text. MetaTrader exports UTF-16 with a byte-order
    /// mark, most other tools UTF-8.
    public static func decodeText(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian).map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") }
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian).map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") }
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.replacingOccurrences(of: "\u{FEFF}", with: "")
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Sorts by time and drops duplicated timestamps (keeping the last one).
    public static func normalize(_ candles: [Candle]) -> [Candle] {
        var byTime: [Date: Candle] = [:]
        for candle in candles { byTime[candle.time] = candle }
        return byTime.values.sorted { $0.time < $1.time }
    }

    /// Serialises candles back to a simple CSV with an ISO-8601 time column.
    public static func export(_ candles: [Candle]) -> String {
        let formatter = ISO8601DateFormatter()
        var out = "time,open,high,low,close,volume\n"
        for c in candles {
            out += "\(formatter.string(from: c.time)),\(c.open),\(c.high),\(c.low),\(c.close),\(c.volume)\n"
        }
        return out
    }

    // MARK: - Layout

    struct Layout {
        var date: Int
        var time: Int?
        var open: Int
        var high: Int
        var low: Int
        var close: Int
        var volume: Int?

        var maxIndex: Int {
            [date, time ?? 0, open, high, low, close, volume ?? 0].max() ?? 0
        }
    }

    static func layout(forHeader fields: [String]) throws -> Layout {
        let names = fields.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "<>\" ")).lowercased()
        }
        func find(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let index = names.firstIndex(of: candidate) { return index }
            }
            return nil
        }
        var dateIndex = find(["time", "date", "datetime", "timestamp", "open time", "open_time", "opentime", "gmt time", "local time"])
        // MT5 exports separate <DATE> and <TIME> columns.
        var timeIndex: Int?
        if let d = names.firstIndex(of: "date"), let t = names.firstIndex(of: "time") {
            dateIndex = d
            timeIndex = t
        }
        guard let date = dateIndex else { throw CSVParseError.missingColumn("time") }
        guard let open = find(["open", "o"]) else { throw CSVParseError.missingColumn("open") }
        guard let high = find(["high", "h"]) else { throw CSVParseError.missingColumn("high") }
        guard let low = find(["low", "l"]) else { throw CSVParseError.missingColumn("low") }
        guard let close = find(["close", "c", "price"]) else { throw CSVParseError.missingColumn("close") }
        let volume = find(["volume", "tickvol", "tick_volume", "tick volume", "vol", "v"])
        return Layout(date: date, time: timeIndex, open: open, high: high, low: low, close: close, volume: volume)
    }

    static func detectDelimiter(_ line: String) -> Character {
        let candidates: [Character] = ["\t", ";", ","]
        return candidates.max { a, b in
            line.filter { $0 == a }.count < line.filter { $0 == b }.count
        } ?? ","
    }

    static func split(_ line: String, _ delimiter: Character) -> [String] {
        line.split(separator: delimiter, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
    }

    // MARK: - Dates

    static let dateFormats = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy.MM.dd HH:mm:ss",
        "yyyy.MM.dd HH:mm",
        "yyyy.MM.dd",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/MM/dd",
        "dd.MM.yyyy HH:mm:ss.SSS",
        "dd.MM.yyyy HH:mm:ss",
        "dd.MM.yyyy HH:mm",
        "dd.MM.yyyy",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy",
        "yyyyMMdd HH:mm:ss",
        "yyyyMMdd",
    ]

    func parseDate(_ text: String) -> Date? {
        dateParser.parse(text)
    }

    private var dateParser: DateParser { DateParser.shared(for: timeZone) }
}

/// Tries the known formats, remembering the last one that matched so large
/// files only pay for format detection once.
final class DateParser {
    private let formatter: DateFormatter
    private var lastFormat: String?
    private let lock = NSLock()

    private static var cache: [String: DateParser] = [:]
    private static let cacheLock = NSLock()

    static func shared(for timeZone: TimeZone) -> DateParser {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let parser = cache[timeZone.identifier] { return parser }
        let parser = DateParser(timeZone: timeZone)
        cache[timeZone.identifier] = parser
        return parser
    }

    private let timeZone: TimeZone

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
    }

    func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let number = Double(trimmed), !trimmed.contains("."), trimmed.count >= 9 {
            // Unix timestamp: 13 digits are milliseconds.
            return Date(timeIntervalSince1970: trimmed.count >= 13 ? number / 1000 : number)
        }
        if let date = fastParse(trimmed) { return date }
        lock.lock()
        defer { lock.unlock() }
        if let format = lastFormat {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        for format in CSVParser.dateFormats where format != lastFormat {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                lastFormat = format
                return date
            }
        }
        return nil
    }
    /// Parses `yyyy-MM-dd[ T]HH:mm[:ss[.SSS]][Z|±hh:mm]` (any of `-./` as date
    /// separator) and `dd.MM.yyyy HH:mm[:ss]` without DateFormatter, which is
    /// slow for large files.
    func fastParse(_ text: String) -> Date? {
        var groups: [Int] = []
        var groupLengths: [Int] = []
        var current = 0
        var length = 0
        var offsetSign = 0
        var offsetStart: Int?
        var isUTC = false
        var dateSeparator: Character?
        for character in text {
            if let digit = character.wholeNumberValue, character.isASCII {
                current = current * 10 + digit
                length += 1
                continue
            }
            if length > 0 {
                groups.append(current)
                groupLengths.append(length)
                current = 0
                length = 0
            }
            switch character {
            case "-", ".", "/":
                if groups.count < 3 {
                    if dateSeparator == nil { dateSeparator = character }
                    guard character == dateSeparator else { return nil }
                } else if character == "-", offsetStart == nil, groups.count >= 5 {
                    offsetSign = -1
                    offsetStart = groups.count
                } else if character != "." {
                    return nil
                }
            case "+":
                guard groups.count >= 5, offsetStart == nil else { return nil }
                offsetSign = 1
                offsetStart = groups.count
            case "Z", "z":
                isUTC = true
            case " ", "T", ":":
                break
            default:
                return nil
            }
        }
        if length > 0 {
            groups.append(current)
            groupLengths.append(length)
        }
        guard groups.count >= 3, dateSeparator != "/" || groupLengths[0] == 4 else { return nil }

        var year: Int, month: Int, day: Int
        if groupLengths[0] == 4 {
            (year, month, day) = (groups[0], groups[1], groups[2])
        } else if groupLengths[2] == 4, dateSeparator == "." {
            (year, month, day) = (groups[2], groups[1], groups[0])
        } else {
            return nil
        }
        let timeEnd = offsetStart ?? groups.count
        let time = Array(groups[3..<timeEnd])
        let lengths = Array(groupLengths[3..<timeEnd])
        guard (1...12).contains(month), (1...31).contains(day), time.count <= 4 else { return nil }
        let hour = time.count > 0 ? time[0] : 0
        let minute = time.count > 1 ? time[1] : 0
        let second = time.count > 2 ? time[2] : 0
        let fraction = time.count > 3 ? Double(time[3]) / pow(10, Double(lengths[3])) : 0
        guard hour < 24, minute < 60, second < 61 else { return nil }

        // Days since 1970-01-01 for the proleptic Gregorian calendar.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        var seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second) + fraction

        if let start = offsetStart {
            let parts = Array(groups[start...])
            guard !parts.isEmpty else { return nil }
            var offset = 0
            if parts.count == 1, groupLengths[start] == 4 {
                offset = parts[0] / 100 * 3600 + parts[0] % 100 * 60
            } else {
                offset = parts[0] * 3600 + (parts.count > 1 ? parts[1] * 60 : 0)
            }
            seconds -= Double(offsetSign * offset)
        } else if !isUTC {
            let guess = Date(timeIntervalSince1970: seconds)
            seconds -= Double(timeZone.secondsFromGMT(for: guess))
        }
        return Date(timeIntervalSince1970: seconds)
    }
}

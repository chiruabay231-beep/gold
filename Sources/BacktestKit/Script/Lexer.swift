import Foundation

public struct SourceLocation: Hashable, Sendable, CustomStringConvertible {
    public var line: Int
    public var column: Int

    public var description: String { "dòng \(line), cột \(column)" }
}

public struct ScriptError: LocalizedError, Equatable {
    public var message: String
    public var location: SourceLocation?

    public init(_ message: String, at location: SourceLocation? = nil) {
        self.message = message
        self.location = location
    }

    public var errorDescription: String? {
        if let location { return "\(message) (\(location))" }
        return message
    }
}

enum TokenKind: Equatable {
    case number(Double)
    case identifier(String)
    case string(String)
    case op(String)
    case leftParen, rightParen, leftBracket, rightBracket, comma
    case question, colon
    case newline
    case end
}

struct Token: Equatable {
    var kind: TokenKind
    var location: SourceLocation
}

/// Splits script source into tokens. Newlines are significant (they end a
/// statement) except inside parentheses or brackets.
struct Lexer {
    private let chars: [Character]
    private var index = 0
    private var line = 1
    private var column = 1
    private var depth = 0

    init(_ source: String) {
        chars = Array(source)
    }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = try nextToken()
            if token.kind == .newline, tokens.last?.kind == .newline || tokens.isEmpty {
                continue
            }
            tokens.append(token)
            if token.kind == .end { break }
        }
        return tokens
    }

    private var current: Character? { index < chars.count ? chars[index] : nil }
    private func peek(_ offset: Int = 1) -> Character? {
        index + offset < chars.count ? chars[index + offset] : nil
    }

    private mutating func advance() {
        if chars[index] == "\n" || chars[index] == "\r\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private mutating func nextToken() throws -> Token {
        while let c = current {
            if c == "\n" || c == "\r\n" {
                let location = SourceLocation(line: line, column: column)
                advance()
                if depth == 0 { return Token(kind: .newline, location: location) }
            } else if c.isWhitespace {
                advance()
            } else if c == "#" || (c == "/" && peek() == "/") {
                while let c = current, c != "\n", c != "\r\n" { advance() }
            } else {
                break
            }
        }
        let location = SourceLocation(line: line, column: column)
        guard let c = current else { return Token(kind: .end, location: location) }

        if c.isNumber || (c == "." && (peek()?.isNumber ?? false)) {
            var text = ""
            while let d = current, d.isNumber || d == "." {
                text.append(d)
                advance()
            }
            if let e = current, e == "e" || e == "E",
               let next = peek(), next.isNumber || next == "-" || next == "+" {
                text.append(e)
                advance()
                text.append(current!)
                advance()
                while let d = current, d.isNumber {
                    text.append(d)
                    advance()
                }
            }
            guard let value = Double(text) else {
                throw ScriptError("Số không hợp lệ \"\(text)\"", at: location)
            }
            return Token(kind: .number(value), location: location)
        }

        if c.isLetter || c == "_" {
            var text = ""
            while let d = current, d.isLetter || d.isNumber || d == "_" || d == "." {
                text.append(d)
                advance()
            }
            return Token(kind: .identifier(text), location: location)
        }

        if c == "\"" || c == "'" {
            let quote = c
            advance()
            var text = ""
            while let d = current, d != quote {
                if d == "\n" { throw ScriptError("Chuỗi chưa đóng", at: location) }
                text.append(d)
                advance()
            }
            guard current == quote else { throw ScriptError("Chuỗi chưa đóng", at: location) }
            advance()
            return Token(kind: .string(text), location: location)
        }

        advance()
        switch c {
        case "(":
            depth += 1
            return Token(kind: .leftParen, location: location)
        case ")":
            depth = max(0, depth - 1)
            return Token(kind: .rightParen, location: location)
        case "[":
            depth += 1
            return Token(kind: .leftBracket, location: location)
        case "]":
            depth = max(0, depth - 1)
            return Token(kind: .rightBracket, location: location)
        case ",":
            return Token(kind: .comma, location: location)
        case "?":
            return Token(kind: .question, location: location)
        case ":":
            return Token(kind: .colon, location: location)
        case ";":
            return Token(kind: .newline, location: location)
        case "+", "-", "*", "/", "%", "^":
            return Token(kind: .op(String(c)), location: location)
        case "=", "!", "<", ">":
            if current == "=" {
                advance()
                return Token(kind: .op(String(c) + "="), location: location)
            }
            return Token(kind: .op(String(c)), location: location)
        case "&", "|":
            if current == c {
                advance()
                return Token(kind: .op(String(c) + String(c)), location: location)
            }
            throw ScriptError("Ký tự không hợp lệ \"\(c)\", ý bạn là \"\(c)\(c)\"?", at: location)
        default:
            throw ScriptError("Ký tự không hợp lệ \"\(c)\"", at: location)
        }
    }
}

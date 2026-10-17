import Foundation

/// Expression tree of the indicator script language.
public indirect enum Expr: Equatable, CustomStringConvertible {
    case number(Double)
    case string(String)
    case variable(String, SourceLocation)
    case unary(String, Expr, SourceLocation)
    case binary(String, Expr, Expr, SourceLocation)
    case ternary(Expr, Expr, Expr, SourceLocation)
    /// `series[n]`: value `n` bars ago.
    case history(Expr, Expr, SourceLocation)
    case call(String, [Expr], SourceLocation)

    public var description: String {
        switch self {
        case .number(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v)
        case .string(let s): return "\"\(s)\""
        case .variable(let name, _): return name
        case .unary(let op, let e, _): return "(\(op) \(e))"
        case .binary(let op, let l, let r, _): return "(\(l) \(op) \(r))"
        case .ternary(let c, let a, let b, _): return "(\(c) ? \(a) : \(b))"
        case .history(let e, let n, _): return "\(e)[\(n)]"
        case .call(let name, let args, _): return "\(name)(\(args.map(\.description).joined(separator: ", ")))"
        }
    }
}

public enum Statement: Equatable {
    case assign(String, Expr, SourceLocation)
    case expression(Expr)
}

public struct Program: Equatable {
    public var statements: [Statement]

    /// Names assigned anywhere in the program, in order of first assignment.
    public var assignedNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for case .assign(let name, _, _) in statements where seen.insert(name).inserted {
            names.append(name)
        }
        return names
    }
}

/// Recursive-descent parser.
///
/// ```
/// program    := statement { NEWLINE statement }
/// statement  := IDENT "=" expr | expr
/// expr       := or [ "?" expr ":" expr ]
/// or         := and { ("or" | "||") and }
/// and        := not { ("and" | "&&") not }
/// not        := ("not" | "!") not | comparison
/// comparison := additive [ ("<" | "<=" | ">" | ">=" | "==" | "!=") additive ]
/// additive   := term { ("+" | "-") term }
/// term       := unary { ("*" | "/" | "%") unary }
/// unary      := "-" unary | "+" unary | power
/// power      := postfix [ "^" unary ]
/// postfix    := primary { "[" expr "]" }
/// primary    := NUMBER | STRING | "true" | "false" | IDENT [ "(" args ")" ] | "(" expr ")"
/// ```
public struct Parser {
    private var tokens: [Token]
    private var position = 0

    public static func parse(_ source: String) throws -> Program {
        var lexer = Lexer(source)
        var parser = Parser(tokens: try lexer.tokenize())
        return try parser.parseProgram()
    }

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: Token { tokens[position] }
    private var next: Token { tokens[min(position + 1, tokens.count - 1)] }

    private mutating func advance() -> Token {
        let token = tokens[position]
        if position < tokens.count - 1 { position += 1 }
        return token
    }

    private mutating func expect(_ kind: TokenKind, _ what: String) throws {
        guard current.kind == kind else {
            throw ScriptError("Thiếu \(what)", at: current.location)
        }
        _ = advance()
    }

    private func isOp(_ op: String) -> Bool {
        if case .op(let value) = current.kind, value == op { return true }
        return false
    }

    private func isKeyword(_ word: String) -> Bool {
        if case .identifier(let value) = current.kind, value == word { return true }
        return false
    }

    mutating func parseProgram() throws -> Program {
        var statements: [Statement] = []
        while current.kind != .end {
            if current.kind == .newline {
                _ = advance()
                continue
            }
            statements.append(try parseStatement())
            switch current.kind {
            case .newline: _ = advance()
            case .end: break
            default: throw ScriptError("Ký hiệu thừa \(describe(current))", at: current.location)
            }
        }
        guard !statements.isEmpty else { throw ScriptError("Script trống") }
        return Program(statements: statements)
    }

    private mutating func parseStatement() throws -> Statement {
        if case .identifier(let name) = current.kind, case .op("=") = next.kind {
            let location = current.location
            guard !Self.reserved.contains(name) else {
                throw ScriptError("Không thể gán cho từ khoá \"\(name)\"", at: location)
            }
            _ = advance()
            _ = advance()
            return .assign(name, try parseExpr(), location)
        }
        return .expression(try parseExpr())
    }

    static let reserved: Set<String> = ["and", "or", "not", "true", "false"]

    private mutating func parseExpr() throws -> Expr {
        let condition = try parseOr()
        if current.kind == .question {
            let location = advance().location
            let a = try parseExpr()
            try expect(.colon, "\":\" trong biểu thức điều kiện")
            let b = try parseExpr()
            return .ternary(condition, a, b, location)
        }
        return condition
    }

    private mutating func parseOr() throws -> Expr {
        var left = try parseAnd()
        while isKeyword("or") || isOp("||") {
            let location = advance().location
            left = .binary("or", left, try parseAnd(), location)
        }
        return left
    }

    private mutating func parseAnd() throws -> Expr {
        var left = try parseNot()
        while isKeyword("and") || isOp("&&") {
            let location = advance().location
            left = .binary("and", left, try parseNot(), location)
        }
        return left
    }

    private mutating func parseNot() throws -> Expr {
        if isKeyword("not") || isOp("!") {
            let location = advance().location
            return .unary("not", try parseNot(), location)
        }
        return try parseComparison()
    }

    private mutating func parseComparison() throws -> Expr {
        let left = try parseAdditive()
        for op in ["<", "<=", ">", ">=", "==", "!="] where isOp(op) {
            let location = advance().location
            return .binary(op, left, try parseAdditive(), location)
        }
        if isOp("=") {
            throw ScriptError("Dùng \"==\" để so sánh bằng", at: current.location)
        }
        return left
    }

    private mutating func parseAdditive() throws -> Expr {
        var left = try parseTerm()
        while isOp("+") || isOp("-") {
            let token = advance()
            guard case .op(let op) = token.kind else { break }
            left = .binary(op, left, try parseTerm(), token.location)
        }
        return left
    }

    private mutating func parseTerm() throws -> Expr {
        var left = try parseUnary()
        while isOp("*") || isOp("/") || isOp("%") {
            let token = advance()
            guard case .op(let op) = token.kind else { break }
            left = .binary(op, left, try parseUnary(), token.location)
        }
        return left
    }

    private mutating func parseUnary() throws -> Expr {
        if isOp("-") {
            let location = advance().location
            return .unary("-", try parseUnary(), location)
        }
        if isOp("+") {
            _ = advance()
            return try parseUnary()
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Expr {
        let base = try parsePostfix()
        if isOp("^") {
            let location = advance().location
            return .binary("^", base, try parseUnary(), location)
        }
        return base
    }

    private mutating func parsePostfix() throws -> Expr {
        var expr = try parsePrimary()
        while current.kind == .leftBracket {
            let location = advance().location
            let offset = try parseExpr()
            try expect(.rightBracket, "\"]\"")
            expr = .history(expr, offset, location)
        }
        return expr
    }

    private mutating func parsePrimary() throws -> Expr {
        let token = advance()
        switch token.kind {
        case .number(let value):
            return .number(value)
        case .string(let value):
            return .string(value)
        case .identifier("true"):
            return .number(1)
        case .identifier("false"):
            return .number(0)
        case .identifier(let name):
            guard !Self.reserved.contains(name) else {
                throw ScriptError("Từ khoá \"\(name)\" đặt sai vị trí", at: token.location)
            }
            if current.kind == .leftParen {
                _ = advance()
                var args: [Expr] = []
                if current.kind != .rightParen {
                    repeat {
                        if current.kind == .comma { _ = advance() }
                        args.append(try parseExpr())
                    } while current.kind == .comma
                }
                try expect(.rightParen, "\")\" sau tham số của \(name)")
                return .call(name, args, token.location)
            }
            return .variable(name, token.location)
        case .leftParen:
            let expr = try parseExpr()
            try expect(.rightParen, "\")\"")
            return expr
        case .end:
            throw ScriptError("Biểu thức chưa hoàn chỉnh", at: token.location)
        default:
            throw ScriptError("Không mong đợi \(describe(token))", at: token.location)
        }
    }

    private func describe(_ token: Token) -> String {
        switch token.kind {
        case .number(let v): return "số \(v)"
        case .identifier(let s): return "\"\(s)\""
        case .string(let s): return "chuỗi \"\(s)\""
        case .op(let s): return "\"\(s)\""
        case .leftParen: return "\"(\""
        case .rightParen: return "\")\""
        case .leftBracket: return "\"[\""
        case .rightBracket: return "\"]\""
        case .comma: return "\",\""
        case .question: return "\"?\""
        case .colon: return "\":\""
        case .newline: return "xuống dòng"
        case .end: return "cuối script"
        }
    }
}

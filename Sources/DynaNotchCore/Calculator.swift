import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Small, safe expression evaluator for the Calculator tab (no NSExpression, no code execution).
/// Grammar: + - * / ^ %, parentheses, unary minus, "×" "÷" "x" between numbers, postfix % (percent),
/// functions sqrt sin cos tan asin acos atan log (base 10) ln abs round floor ceil, constants pi π e.
public enum Calculator {
    public static func evaluate(_ expression: String) -> Double? {
        var parser = Parser(tokens: tokenize(expression))
        guard !parser.tokens.isEmpty, let value = parser.parseExpression(), parser.isAtEnd,
              value.isFinite else { return nil }
        return value
    }

    /// "12", "0.5", "1,234,567.89", "1.23e+21"; at most 10 significant fraction digits, no "-0".
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }
        let v = abs(value) < 1e-12 ? 0 : value
        if abs(v) >= 1e15 || (abs(v) < 1e-6 && v != 0) {
            return String(format: "%.6g", v)
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case lparen, rparen
        case identifier(String)
    }

    static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s.lowercased())
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "," && i + 1 < chars.count && chars[i + 1].isNumber && isGroupingComma(chars, i) {
                i += 1
                continue
            }
            if c.isNumber || c == "." {
                var j = i
                var text = ""
                while j < chars.count, chars[j].isNumber || chars[j] == "." || (chars[j] == "," && isGroupingComma(chars, j)) {
                    if chars[j] != "," { text.append(chars[j]) }
                    j += 1
                }
                // Exponent: 1e5, 2.5e-3
                if j < chars.count, chars[j] == "e", j + 1 < chars.count,
                   chars[j + 1].isNumber || ((chars[j + 1] == "-" || chars[j + 1] == "+") && j + 2 < chars.count && chars[j + 2].isNumber) {
                    text.append("e")
                    j += 1
                    if chars[j] == "-" || chars[j] == "+" { text.append(chars[j]); j += 1 }
                    while j < chars.count, chars[j].isNumber { text.append(chars[j]); j += 1 }
                }
                guard let value = Double(text) else { return [] }
                tokens.append(.number(value))
                i = j
                continue
            }
            if c.isLetter || c == "π" {
                if c == "x", let last = tokens.last, case .number = last {
                    tokens.append(.op("*"))
                    i += 1
                    continue
                }
                var j = i
                var name = ""
                while j < chars.count, chars[j].isLetter || chars[j] == "π" {
                    name.append(chars[j])
                    j += 1
                }
                tokens.append(.identifier(name))
                i = j
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^", "%": tokens.append(.op(c))
            case "×": tokens.append(.op("*"))
            case "÷": tokens.append(.op("/"))
            case "−": tokens.append(.op("-"))
            case "(", "[": tokens.append(.lparen)
            case ")", "]": tokens.append(.rparen)
            case "=": break   // "2+2=" is fine
            default: return []
            }
            i += 1
        }
        return tokens
    }

    /// A comma between digits followed by exactly three digits is a thousands separator.
    private static func isGroupingComma(_ chars: [Character], _ i: Int) -> Bool {
        guard i > 0, chars[i - 1].isNumber, i + 3 < chars.count + 1 else { return false }
        for k in 1...3 {
            guard i + k < chars.count, chars[i + k].isNumber else { return false }
        }
        return i + 4 >= chars.count || !chars[i + 4].isNumber
    }

    // MARK: Parser (recursive descent)

    struct Parser {
        let tokens: [Token]
        var index = 0

        init(tokens: [Token]) { self.tokens = tokens }

        var isAtEnd: Bool { index >= tokens.count }
        private var current: Token? { isAtEnd ? nil : tokens[index] }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let t = current, case .op(let o) = t, o == "+" || o == "-" {
                index += 1
                guard var rhs = parseTerm() else { return nil }
                // "200 + 10%" → 220
                if case .op("%")? = previousOp, percentApplied { rhs = value * rhs; percentApplied = false }
                value = o == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private var previousOp: Token? { index > 0 ? tokens[index - 1] : nil }
        private var percentApplied = false

        mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let t = current, case .op(let o) = t, o == "*" || o == "/" || (o == "%" && isBinaryModulo) {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                switch o {
                case "*": value *= rhs
                case "/":
                    guard rhs != 0 else { return nil }
                    value /= rhs
                default:
                    guard rhs != 0 else { return nil }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
                percentApplied = false
            }
            return value
        }

        /// "%" followed by a number or "(" is modulo; otherwise it is a percent sign.
        private var isBinaryModulo: Bool {
            guard index + 1 < tokens.count else { return false }
            switch tokens[index + 1] {
            case .number, .lparen, .identifier: return true
            default: return false
            }
        }

        mutating func parseFactor() -> Double? {
            guard let base = parseUnary() else { return nil }
            if let t = current, case .op("^") = t {
                index += 1
                guard let exponent = parseFactor() else { return nil }   // right-associative
                return pow(base, exponent)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            if let t = current, case .op(let o) = t, o == "-" || o == "+" {
                index += 1
                guard let v = parseUnary() else { return nil }
                return o == "-" ? -v : v
            }
            return parsePostfix()
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while let t = current, case .op("%") = t, !isBinaryModulo {
                index += 1
                value /= 100
                percentApplied = true
            }
            return value
        }

        mutating func parsePrimary() -> Double? {
            guard let t = current else { return nil }
            index += 1
            switch t {
            case .number(let v):
                return v
            case .lparen:
                guard let v = parseExpression(), case .rparen? = current else { return nil }
                index += 1
                return v
            case .identifier(let name):
                switch name {
                case "pi", "π": return Double.pi
                case "e": return M_E
                default: break
                }
                guard let f = Parser.functions[name] else { return nil }
                guard let arg = parseUnary() else { return nil }
                return f(arg)
            default:
                return nil
            }
        }

        static let functions: [String: (Double) -> Double] = [
            "sqrt": { $0.squareRoot() }, "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
            "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
            "log": { log10($0) }, "ln": { log($0) }, "abs": { abs($0) },
            "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
        ]
    }
}

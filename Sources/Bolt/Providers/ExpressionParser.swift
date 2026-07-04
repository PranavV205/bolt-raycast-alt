import Foundation

// Small recursive-descent parser for arithmetic. Written by hand instead
// of NSExpression because NSExpression raises Objective-C exceptions on
// malformed input, which would crash on every half-typed query.
//
// Grammar:
//   expr    := term (("+" | "-") term)*
//   term    := factor (("*" | "/" | "%" | "x") factor)*
//   factor  := unary ("^" factor)?
//   unary   := "-" unary | primary
//   primary := number ("%")? | "(" expr ")" | func "(" expr ")" | const
enum ExpressionParser {

    static func evaluate(_ input: String) -> Double? {
        var text = input.lowercased()
        text = text.replacingOccurrences(of: ",", with: "")
        text = text.replacingOccurrences(of: "_", with: "")
        text = text.replacingOccurrences(of: "×", with: "*")
        text = text.replacingOccurrences(of: "÷", with: "/")

        var parser = Parser(chars: Array(text.replacingOccurrences(of: " ", with: "")))
        guard let value = parser.parseExpression(), parser.isAtEnd else { return nil }
        guard value.isFinite else { return nil }
        return value
    }

    // Quick pre-check so we don't attempt parsing on ordinary words.
    static func looksLikeMath(_ input: String) -> Bool {
        let t = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, t.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,_+-*/%^()x eπpisqrtabndulogcfhm×÷ ")
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        // Needs at least one operator, function, or parenthesis.
        let operators = CharacterSet(charactersIn: "+-*/%^(")
        if t.rangeOfCharacter(from: operators) != nil { return true }
        for fn in ["sqrt", "abs", "round", "floor", "ceil", "log", "ln", "sin", "cos", "tan", "pi"] {
            if t.contains(fn) { return true }
        }
        return false
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        var isAtEnd: Bool { pos >= chars.count }
        var current: Character? { pos < chars.count ? chars[pos] : nil }

        mutating func advance() { pos += 1 }

        mutating func parseExpression() -> Double? {
            guard var left = parseTerm() else { return nil }
            while let op = current, op == "+" || op == "-" {
                advance()
                guard let right = parseTerm() else { return nil }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        mutating func parseTerm() -> Double? {
            guard var left = parseFactor() else { return nil }
            while let op = current, op == "*" || op == "/" || op == "%" || op == "x" {
                advance()
                guard let right = parseFactor() else { return nil }
                switch op {
                case "*", "x": left *= right
                case "/":
                    guard right != 0 else { return nil }
                    left /= right
                default:
                    guard right != 0 else { return nil }
                    left = left.truncatingRemainder(dividingBy: right)
                }
            }
            return left
        }

        mutating func parseFactor() -> Double? {
            guard let base = parseUnary() else { return nil }
            if current == "^" {
                advance()
                guard let exponent = parseFactor() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            if current == "-" {
                advance()
                guard let value = parseUnary() else { return nil }
                return -value
            }
            if current == "+" {
                advance()
                return parseUnary()
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Double? {
            guard let c = current else { return nil }

            if c == "(" {
                advance()
                guard let value = parseExpression(), current == ")" else { return nil }
                advance()
                return value
            }

            if c.isNumber || c == "." {
                return parseNumber()
            }

            if c.isLetter || c == "π" {
                return parseWord()
            }

            return nil
        }

        mutating func parseNumber() -> Double? {
            var text = ""
            while let c = current, c.isNumber || c == "." {
                text.append(c)
                advance()
            }
            guard var value = Double(text) else { return nil }
            // Trailing percent: "18%" -> 0.18
            if current == "%" {
                // Only when not the modulo operator, i.e. next char is not
                // a digit or open paren.
                let next = pos + 1 < chars.count ? chars[pos + 1] : nil
                if next == nil || !(next!.isNumber || next! == "(" || next! == ".") {
                    advance()
                    value /= 100.0
                }
            }
            return value
        }

        mutating func parseWord() -> Double? {
            var word = ""
            while let c = current, c.isLetter || c == "π" {
                word.append(c)
                advance()
            }

            switch word {
            case "pi", "π": return Double.pi
            case "e": return M_E
            default: break
            }

            // Function call: word must be followed by "(".
            guard current == "(" else { return nil }
            advance()
            guard let arg = parseExpression(), current == ")" else { return nil }
            advance()

            switch word {
            case "sqrt": return arg >= 0 ? sqrt(arg) : nil
            case "abs": return abs(arg)
            case "round": return (arg).rounded()
            case "floor": return floor(arg)
            case "ceil": return ceil(arg)
            case "log": return arg > 0 ? log10(arg) : nil
            case "ln": return arg > 0 ? log(arg) : nil
            case "sin": return sin(arg)
            case "cos": return cos(arg)
            case "tan": return tan(arg)
            default: return nil
            }
        }
    }
}

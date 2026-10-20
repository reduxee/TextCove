import Foundation

struct JSONSyntaxError: Error, LocalizedError {
    let message: String
    let line: Int
    let column: Int
    let sourceLine: String?

    var errorDescription: String? {
        "第 \(line) 行，第 \(column) 列：\(message)"
    }

    var detailedDescription: String {
        var result = "第 \(line) 行，第 \(column) 列\n\(message)"
        if let sourceLine, !sourceLine.isEmpty {
            let normalizedLine = sourceLine.replacingOccurrences(of: "\t", with: "    ")
            let caretOffset = max(0, min(column - 1, normalizedLine.count))
            let caret = String(repeating: " ", count: caretOffset) + "^"
            result += "\n\n\(normalizedLine)\n\(caret)"
        }
        return result
    }

    static func make(message: String, source: String, characterOffset: Int) -> JSONSyntaxError {
        let characters = Array(source)
        let boundedOffset = max(0, min(characterOffset, characters.count))

        var line = 1
        var column = 1

        for character in characters[..<boundedOffset] {
            if character.isNewline {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }

        let lines = source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )
        let rawSourceLine = lines.indices.contains(line - 1) ? String(lines[line - 1]) : nil
        let trimmedSourceLine = rawSourceLine.map { String($0.prefix(240)) }

        return JSONSyntaxError(
            message: message,
            line: line,
            column: column,
            sourceLine: trimmedSourceLine
        )
    }
}

struct JSONToken: Equatable {
    enum Kind: Equatable {
        case objectStart
        case objectEnd
        case arrayStart
        case arrayEnd
        case colon
        case comma
        case string
        case number
        case boolean
        case null
    }

    let kind: Kind
    let raw: String
    let offset: Int
}

enum JSONFormatter {
    static func format(_ source: String, compact: Bool) throws -> String {
        let tokens = try JSONSyntaxValidator.validate(source)

        if compact {
            return tokens.map(\.raw).joined()
        }

        var output = ""
        var depth = 0
        let indentUnit = "  "

        for (index, token) in tokens.enumerated() {
            let previous = index > 0 ? tokens[index - 1] : nil
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil

            switch token.kind {
            case .objectStart, .arrayStart:
                output += token.raw
                depth += 1
                if let next, next.kind != .objectEnd, next.kind != .arrayEnd {
                    output += "\n"
                    output += String(repeating: indentUnit, count: depth)
                }

            case .objectEnd, .arrayEnd:
                depth = max(0, depth - 1)
                if let previous, previous.kind != .objectStart, previous.kind != .arrayStart {
                    output += "\n"
                    output += String(repeating: indentUnit, count: depth)
                }
                output += token.raw

            case .comma:
                output += token.raw
                output += "\n"
                output += String(repeating: indentUnit, count: depth)

            case .colon:
                output += ": "

            case .string, .number, .boolean, .null:
                output += token.raw
            }
        }

        return output
    }
}

enum JSONSyntaxValidator {
    static func validate(_ source: String) throws -> [JSONToken] {
        var lexer = JSONLexer(source: source)
        let tokens = try lexer.lex()
        guard !tokens.isEmpty else {
            throw JSONSyntaxError.make(
                message: "JSON 内容为空。",
                source: source,
                characterOffset: 0
            )
        }

        var parser = JSONParser(tokens: tokens, source: source)
        try parser.parseDocument()
        return tokens
    }
}

private struct JSONLexer {
    private let source: String
    private let characters: [Character]
    private var index = 0

    init(source: String) {
        self.source = source
        self.characters = Array(source)
    }

    mutating func lex() throws -> [JSONToken] {
        var tokens: [JSONToken] = []

        while true {
            skipWhitespace()
            guard let character = peek() else { break }
            let tokenOffset = index

            switch character {
            case "{":
                index += 1
                tokens.append(JSONToken(kind: .objectStart, raw: "{", offset: tokenOffset))
            case "}":
                index += 1
                tokens.append(JSONToken(kind: .objectEnd, raw: "}", offset: tokenOffset))
            case "[":
                index += 1
                tokens.append(JSONToken(kind: .arrayStart, raw: "[", offset: tokenOffset))
            case "]":
                index += 1
                tokens.append(JSONToken(kind: .arrayEnd, raw: "]", offset: tokenOffset))
            case ":":
                index += 1
                tokens.append(JSONToken(kind: .colon, raw: ":", offset: tokenOffset))
            case ",":
                index += 1
                tokens.append(JSONToken(kind: .comma, raw: ",", offset: tokenOffset))
            case "\"":
                tokens.append(try lexString())
            case "-", "0"..."9":
                tokens.append(try lexNumber())
            case "t":
                tokens.append(try lexLiteral(expected: "true", kind: .boolean))
            case "f":
                tokens.append(try lexLiteral(expected: "false", kind: .boolean))
            case "n":
                tokens.append(try lexLiteral(expected: "null", kind: .null))
            default:
                throw error("无法识别的字符 “\(character)”。", at: tokenOffset)
            }
        }

        return tokens
    }

    private mutating func skipWhitespace() {
        while let character = peek(),
              character == " " || character == "\t" || character.isNewline {
            index += 1
        }
    }

    private mutating func lexString() throws -> JSONToken {
        let start = index
        index += 1
        var raw = "\""

        while let character = peek() {
            index += 1

            if character == "\"" {
                raw.append(character)
                return JSONToken(kind: .string, raw: raw, offset: start)
            }

            if character == "\\" {
                raw.append(character)
                guard let escaped = peek() else {
                    throw error("字符串未闭合。", at: start)
                }
                index += 1
                raw.append(escaped)

                switch escaped {
                case "\"", "\\", "/", "b", "f", "n", "r", "t":
                    continue
                case "u":
                    for _ in 0..<4 {
                        guard let hex = peek(), hex.isHexDigit else {
                            throw error("Unicode 转义必须包含 4 位十六进制数字。", at: index)
                        }
                        index += 1
                        raw.append(hex)
                    }
                default:
                    throw error("无效的字符串转义序列 “\\\(escaped)”。", at: index - 1)
                }
                continue
            }

            if character.isNewline
                || character.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                throw error("字符串中不允许出现未转义的控制字符。", at: index - 1)
            }

            raw.append(character)
        }

        throw error("字符串未闭合。", at: start)
    }

    private mutating func lexNumber() throws -> JSONToken {
        let start = index
        var raw = ""

        if peek() == "-" {
            raw.append("-")
            index += 1
        }

        guard let first = peek(), first.isASCII, first.isNumber else {
            throw error("“-” 后必须紧跟数字。", at: start)
        }

        if first == "0" {
            raw.append(first)
            index += 1
            if let next = peek(), next.isASCII, next.isNumber {
                throw error("JSON 数字不能有前导零。", at: index)
            }
        } else {
            while let digit = peek(), digit.isASCII, digit.isNumber {
                raw.append(digit)
                index += 1
            }
        }

        if peek() == "." {
            raw.append(".")
            index += 1
            guard let digit = peek(), digit.isASCII, digit.isNumber else {
                throw error("小数点后必须至少有一位数字。", at: index)
            }
            while let digit = peek(), digit.isASCII, digit.isNumber {
                raw.append(digit)
                index += 1
            }
        }

        if let exponent = peek(), exponent == "e" || exponent == "E" {
            raw.append(exponent)
            index += 1

            if let sign = peek(), sign == "+" || sign == "-" {
                raw.append(sign)
                index += 1
            }

            guard let digit = peek(), digit.isASCII, digit.isNumber else {
                throw error("指数部分必须包含数字。", at: index)
            }
            while let digit = peek(), digit.isASCII, digit.isNumber {
                raw.append(digit)
                index += 1
            }
        }

        return JSONToken(kind: .number, raw: raw, offset: start)
    }

    private mutating func lexLiteral(expected: String, kind: JSONToken.Kind) throws -> JSONToken {
        let start = index
        let expectedCharacters = Array(expected)

        for expectedCharacter in expectedCharacters {
            guard peek() == expectedCharacter else {
                throw error("无效的字面量，应为 “\(expected)”。", at: start)
            }
            index += 1
        }

        return JSONToken(kind: kind, raw: expected, offset: start)
    }

    private func peek() -> Character? {
        characters.indices.contains(index) ? characters[index] : nil
    }

    private func error(_ message: String, at offset: Int) -> JSONSyntaxError {
        JSONSyntaxError.make(message: message, source: source, characterOffset: offset)
    }
}

private struct JSONParser {
    private let tokens: [JSONToken]
    private let source: String
    private var index = 0

    init(tokens: [JSONToken], source: String) {
        self.tokens = tokens
        self.source = source
    }

    mutating func parseDocument() throws {
        try parseValue(depth: 0)

        if let remaining = currentToken {
            throw error("JSON 结束后仍存在多余内容。", at: remaining)
        }
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= 512 else {
            throw error("JSON 嵌套层级过深。", at: currentToken)
        }
        guard let token = currentToken else {
            throw error("意外的文件结尾，此处需要一个 JSON 值。", atEnd: true)
        }

        switch token.kind {
        case .string, .number, .boolean, .null:
            index += 1
        case .objectStart:
            try parseObject(depth: depth)
        case .arrayStart:
            try parseArray(depth: depth)
        default:
            throw error("此处需要一个 JSON 值，但遇到了 “\(token.raw)”。", at: token)
        }
    }

    private mutating func parseObject(depth: Int) throws {
        index += 1

        if currentToken?.kind == .objectEnd {
            index += 1
            return
        }

        while true {
            guard let key = currentToken else {
                throw error("对象未闭合，缺少 “}”。", atEnd: true)
            }
            guard key.kind == .string else {
                throw error("对象的键必须使用双引号字符串。", at: key)
            }
            index += 1

            guard let colon = currentToken, colon.kind == .colon else {
                throw error("对象的键后缺少冒号。", at: currentToken)
            }
            index += 1

            try parseValue(depth: depth + 1)

            guard let separator = currentToken else {
                throw error("对象未闭合，缺少 “}”。", atEnd: true)
            }

            switch separator.kind {
            case .comma:
                index += 1
                if currentToken?.kind == .objectEnd {
                    throw error("对象末尾不允许多余的逗号。", at: separator)
                }
                if currentToken == nil {
                    throw error("对象未闭合，缺少 “}”。", atEnd: true)
                }
            case .objectEnd:
                index += 1
                return
            default:
                throw error("对象成员之间缺少逗号。", at: separator)
            }
        }
    }

    private mutating func parseArray(depth: Int) throws {
        index += 1

        if currentToken?.kind == .arrayEnd {
            index += 1
            return
        }

        while true {
            try parseValue(depth: depth + 1)

            guard let separator = currentToken else {
                throw error("数组未闭合，缺少 “]”。", atEnd: true)
            }

            switch separator.kind {
            case .comma:
                index += 1
                if currentToken?.kind == .arrayEnd {
                    throw error("数组末尾不允许多余的逗号。", at: separator)
                }
                if currentToken == nil {
                    throw error("数组未闭合，缺少 “]”。", atEnd: true)
                }
            case .arrayEnd:
                index += 1
                return
            default:
                throw error("数组元素之间缺少逗号。", at: separator)
            }
        }
    }

    private var currentToken: JSONToken? {
        tokens.indices.contains(index) ? tokens[index] : nil
    }

    private func error(_ message: String, at token: JSONToken?) -> JSONSyntaxError {
        JSONSyntaxError.make(
            message: message,
            source: source,
            characterOffset: token?.offset ?? source.count
        )
    }

    private func error(_ message: String, atEnd: Bool) -> JSONSyntaxError {
        JSONSyntaxError.make(
            message: message,
            source: source,
            characterOffset: source.count
        )
    }
}

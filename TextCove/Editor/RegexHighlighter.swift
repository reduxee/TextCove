import Foundation

fileprivate struct RegexRule {
    let pattern: String
    let capture: String
    var options: NSRegularExpression.Options = []
    var group: Int = 0
}

/// 内置正则高亮：用于 CodeEditLanguages 里没有 tree-sitter 语法的常见文本类型。
/// 产出的 capture 名与 tree-sitter 一致，交给 EditorTheme 统一上色。
enum RegexHighlighter {
    private struct Match {
        let start: Int
        let end: Int
        let priority: Int
        let capture: String
    }

    static func tokens(text: String, syntax: RegexSyntax) -> [HighlightToken] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var found: [Match] = []

        for (index, entry) in CompiledRules.rules(for: syntax).enumerated() {
            entry.expression.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
                guard let result else { return }
                let range = entry.group > 0 ? result.range(at: entry.group) : result.range
                guard range.length > 0 else { return }
                found.append(
                    Match(
                        start: range.location,
                        end: range.location + range.length,
                        priority: index,
                        capture: entry.capture
                    )
                )
            }
        }

        // 起点靠前的先占位；同一起点按规则声明顺序取胜，之后与已选区间重叠的匹配全部丢弃。
        found.sort { lhs, rhs in
            lhs.start == rhs.start ? lhs.priority < rhs.priority : lhs.start < rhs.start
        }

        var tokens: [HighlightToken] = []
        var lastEnd = 0

        for match in found {
            guard match.start >= lastEnd else { continue }
            tokens.append(
                HighlightToken(
                    range: NSRange(location: match.start, length: match.end - match.start),
                    captureName: match.capture
                )
            )
            lastEnd = match.end
        }

        return tokens
    }
}

private enum CompiledRules {
    struct Entry {
        let expression: NSRegularExpression
        let capture: String
        let group: Int
    }

    static func rules(for syntax: RegexSyntax) -> [Entry] {
        switch syntax {
        case .xml: return xml
        case .propertyList: return propertyList
        case .diff: return diff
        case .nginx: return nginx
        case .graphQL: return graphQL
        case .gitignore: return gitignore
        case .environment: return environment
        }
    }

    static let xml: [Entry] = compile(RegexSyntaxTable.rules(for: .xml))
    static let propertyList: [Entry] = compile(RegexSyntaxTable.rules(for: .propertyList))
    static let diff: [Entry] = compile(RegexSyntaxTable.rules(for: .diff))
    static let nginx: [Entry] = compile(RegexSyntaxTable.rules(for: .nginx))
    static let graphQL: [Entry] = compile(RegexSyntaxTable.rules(for: .graphQL))
    static let gitignore: [Entry] = compile(RegexSyntaxTable.rules(for: .gitignore))
    static let environment: [Entry] = compile(RegexSyntaxTable.rules(for: .environment))

    private static func compile(_ rules: [RegexRule]) -> [Entry] {
        rules.compactMap { rule in
            guard let expression = try? NSRegularExpression(
                pattern: rule.pattern,
                options: rule.options
            ) else {
                return nil
            }
            return Entry(expression: expression, capture: rule.capture, group: rule.group)
        }
    }
}

private enum RegexSyntaxTable {
    static func rules(for syntax: RegexSyntax) -> [RegexRule] {
        switch syntax {
        case .xml:
            return xmlRules
        case .propertyList:
            return [
                RegexRule(pattern: "(?<=<key>)[\\s\\S]*?(?=</key>)", capture: "property"),
                RegexRule(pattern: "<(?:true|false)/>", capture: "constant")
            ] + xmlRules
        case .diff:
            return diffRules
        case .nginx:
            return nginxRules
        case .graphQL:
            return graphQLRules
        case .gitignore:
            return gitignoreRules
        case .environment:
            return envRules
        }
    }

    private static let lineAnchors: NSRegularExpression.Options = .anchorsMatchLines

    private static var xmlRules: [RegexRule] {
        [
            RegexRule(pattern: "<!--[\\s\\S]*?-->", capture: "comment"),
            RegexRule(pattern: "<!\\[CDATA\\[[\\s\\S]*?\\]\\]>", capture: "string"),
            RegexRule(pattern: "<!DOCTYPE[^>]*>", capture: "comment", options: .caseInsensitive),
            RegexRule(pattern: "<\\?[\\s\\S]*?\\?>", capture: "attribute"),
            RegexRule(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'", capture: "string"),
            RegexRule(pattern: "&[A-Za-z][A-Za-z0-9]*;|&#[0-9]+;|&#x[0-9A-Fa-f]+;", capture: "constant"),
            RegexRule(pattern: "</?[A-Za-z_:][\\w:.-]*|/?>", capture: "tag"),
            RegexRule(pattern: "[A-Za-z_:][\\w:.-]*(?=\\s*=)", capture: "attribute")
        ]
    }

    private static var diffRules: [RegexRule] {
        [
            RegexRule(pattern: "^@@[^\\n]*", capture: "diff.chunk", options: lineAnchors),
            RegexRule(pattern: "^\\+\\+\\+[^\\n]*", capture: "diff.header", options: lineAnchors),
            RegexRule(pattern: "^---[^\\n]*", capture: "diff.header", options: lineAnchors),
            RegexRule(
                pattern: "^(?:diff --git|index |new file|deleted file|similarity |rename |old mode|new mode|Binary files)[^\\n]*",
                capture: "diff.command",
                options: lineAnchors
            ),
            RegexRule(pattern: "^\\+[^\\n]*", capture: "diff.inserted", options: lineAnchors),
            RegexRule(pattern: "^-[^\\n]*", capture: "diff.deleted", options: lineAnchors)
        ]
    }

    private static var nginxRules: [RegexRule] {
        [
            RegexRule(pattern: "#[^\\n]*", capture: "comment"),
            RegexRule(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'", capture: "string"),
            RegexRule(pattern: "\\$\\{[^}]*\\}|\\$[A-Za-z_][\\w]*", capture: "property"),
            RegexRule(
                pattern: "^[ \\t]*([A-Za-z_][\\w]*)(?=[ \\t;{])",
                capture: "keyword",
                options: lineAnchors,
                group: 1
            ),
            RegexRule(pattern: "\\b(?:on|off)\\b", capture: "constant"),
            RegexRule(pattern: "\\b\\d+(?:\\.\\d+)?[kKmMgG]?\\b", capture: "number"),
            RegexRule(pattern: "[;{}]", capture: "punctuation")
        ]
    }

    private static var graphQLRules: [RegexRule] {
        [
            RegexRule(pattern: "\"\"\"[\\s\\S]*?\"\"\"", capture: "string"),
            RegexRule(pattern: "#[^\\n]*", capture: "comment"),
            RegexRule(pattern: "\"[^\"\\n]*\"", capture: "string"),
            RegexRule(
                pattern: "\\b(?:query|mutation|subscription|fragment|type|input|interface|enum|union|scalar|schema|extend|implements|directive|repeatable|on|null)\\b",
                capture: "keyword"
            ),
            RegexRule(pattern: "@[A-Za-z_][\\w]*", capture: "attribute"),
            RegexRule(pattern: "\\$[A-Za-z_][\\w]*", capture: "property"),
            RegexRule(pattern: "[A-Za-z_][\\w]*(?=\\s*\\()", capture: "function"),
            RegexRule(pattern: "\\b[A-Z][A-Za-z0-9_]*\\b", capture: "type"),
            RegexRule(pattern: "\\b(?:true|false)\\b", capture: "constant"),
            RegexRule(pattern: "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", capture: "number"),
            RegexRule(pattern: "[{}()\\[\\]:=,!&|.@-]+", capture: "punctuation")
        ]
    }

    private static var gitignoreRules: [RegexRule] {
        [
            RegexRule(pattern: "^[ \\t]*#[^\\n]*", capture: "comment", options: lineAnchors),
            RegexRule(pattern: "^[ \\t]*!", capture: "operator", options: lineAnchors),
            RegexRule(pattern: "\\*\\*|\\*|\\?|\\[[^\\]\\n]*\\]", capture: "keyword")
        ]
    }

    private static var envRules: [RegexRule] {
        [
            RegexRule(pattern: "#[^\\n]*", capture: "comment"),
            RegexRule(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'", capture: "string"),
            RegexRule(
                pattern: "^[ \\t]*(export)[ \\t]+(?=[A-Za-z_])",
                capture: "keyword",
                options: lineAnchors,
                group: 1
            ),
            RegexRule(
                pattern: "^[ \\t]*([A-Za-z_][A-Za-z0-9_.-]*)(?=[ \\t]*=)",
                capture: "property",
                options: lineAnchors,
                group: 1
            ),
            RegexRule(pattern: "\\$\\{[^}]*\\}|\\$[A-Za-z_][\\w]*", capture: "constant"),
            RegexRule(pattern: "(?<==)[ \\t]*-?\\d+(?:\\.\\d+)?", capture: "number"),
            RegexRule(pattern: "=", capture: "punctuation")
        ]
    }
}

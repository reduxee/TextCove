import CodeEditLanguages
import Foundation

/// Vue 单文件组件高亮：按 UTF-16 长度不变的“投影文本”把同一份文档分别喂给
/// html / js|ts / css 语法，得到的 range 可直接落回原文，无需偏移换算。
enum VueHighlighter {
    private struct EmbeddedBlock {
        let body: NSRange
        let language: CodeLanguage
    }

    static func tokens(text: String) -> [HighlightToken] {
        let units = Array(text.utf16)
        let blocks = embeddedBlocks(in: units)

        var tokens: [HighlightToken] = []

        let template = project(units, hiding: blocks.map(\.body))
        for token in TreeSitterEngine.tokens(text: template, language: .html) {
            guard !blocks.contains(where: { overlaps(token.range, $0.body) }) else { continue }
            tokens.append(token)
        }

        for block in blocks {
            let embedded = project(units, showing: block.body)
            for token in TreeSitterEngine.tokens(text: embedded, language: block.language) {
                guard contains(block.body, token.range) else { continue }
                tokens.append(token)
            }
        }

        tokens.sort { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            if lhs.range.length != rhs.range.length {
                return lhs.range.length > rhs.range.length
            }
            return lhs.captureName < rhs.captureName
        }

        return tokens
    }

    private static func project(_ units: [UniChar], hiding hidden: [NSRange]) -> String {
        var visible = [Bool](repeating: true, count: units.count)
        for range in hidden {
            let start = max(0, range.location)
            let end = min(units.count, range.location + range.length)
            guard start < end else { continue }
            for index in start..<end {
                visible[index] = false
            }
        }
        return render(units, visible: visible)
    }

    private static func project(_ units: [UniChar], showing shown: NSRange) -> String {
        var visible = [Bool](repeating: false, count: units.count)
        let start = max(0, shown.location)
        let end = min(units.count, shown.location + shown.length)
        guard start < end else { return render(units, visible: visible) }
        for index in start..<end {
            visible[index] = true
        }
        return render(units, visible: visible)
    }

    /// 隐藏处用空格替换并保留换行，保证 UTF-16 长度与原文完全一致。
    private static func render(_ units: [UniChar], visible: [Bool]) -> String {
        var output = units
        for index in output.indices where !visible[index] {
            let unit = output[index]
            if unit != linefeedUnit && unit != carriageUnit {
                output[index] = spaceUnit
            }
        }
        return String(utf16CodeUnits: output, count: output.count)
    }

    private static func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        a.location < b.location + b.length && b.location < a.location + a.length
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location
            && inner.location + inner.length <= outer.location + outer.length
    }

    // MARK: - script / style 区块扫描

    private static let gtUnit: UniChar = 62
    private static let slashUnit: UniChar = 47
    private static let spaceUnit: UniChar = 32
    private static let tabUnit: UniChar = 9
    private static let linefeedUnit: UniChar = 10
    private static let carriageUnit: UniChar = 13

    private static let blockKeywords: [(name: String, needle: [UniChar])] = [
        (name: "script", needle: Array("<script".utf16)),
        (name: "style", needle: Array("<style".utf16))
    ]

    private static func embeddedBlocks(in units: [UniChar]) -> [EmbeddedBlock] {
        var blocks: [EmbeddedBlock] = []
        var index = 0
        let shortest = blockKeywords.map(\.needle.count).min() ?? 0

        while index + shortest <= units.count {
            guard let keyword = blockKeywords.first(where: {
                matches($0.needle, at: index, in: units)
                    && isTagBoundary(at: index + $0.needle.count, in: units)
            }) else {
                index += 1
                continue
            }

            let tagStart = index + keyword.needle.count
            var tagEnd = tagStart
            while tagEnd < units.count, units[tagEnd] != gtUnit {
                tagEnd += 1
            }
            guard tagEnd < units.count else { break }

            let bodyStart = tagEnd + 1
            let close = closingTag(name: keyword.name, from: bodyStart, in: units)
            let bodyEnd = close?.bodyEnd ?? units.count
            let tagText = String(utf16CodeUnits: Array(units[tagStart..<tagEnd]), count: tagEnd - tagStart)

            blocks.append(
                EmbeddedBlock(
                    body: NSRange(location: bodyStart, length: bodyEnd - bodyStart),
                    language: language(forBlock: keyword.name, tagText: tagText)
                )
            )

            index = close?.scanResume ?? units.count
        }

        return blocks
    }

    private static func closingTag(name: String, from start: Int, in units: [UniChar])
        -> (bodyEnd: Int, scanResume: Int)? {
        let needle = Array("</\(name)".utf16)
        var index = start

        while index + needle.count <= units.count {
            if matches(needle, at: index, in: units),
               isTagBoundary(at: index + needle.count, in: units) {
                var tagEnd = index + needle.count
                while tagEnd < units.count, units[tagEnd] != gtUnit {
                    tagEnd += 1
                }
                return (bodyEnd: index, scanResume: min(tagEnd + 1, units.count))
            }
            index += 1
        }

        return nil
    }

    private static func matches(_ needle: [UniChar], at index: Int, in units: [UniChar]) -> Bool {
        guard index >= 0, index + needle.count <= units.count else { return false }
        for offset in needle.indices where units[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    private static func isTagBoundary(at index: Int, in units: [UniChar]) -> Bool {
        guard index < units.count else { return false }
        switch units[index] {
        case gtUnit, slashUnit, spaceUnit, tabUnit, linefeedUnit, carriageUnit:
            return true
        default:
            return false
        }
    }

    private static let languagePattern = try? NSRegularExpression(
        pattern: "(?i)lang\\s*=\\s*[\"']?([a-z0-9]+)"
    )

    private static func language(forBlock name: String, tagText: String) -> CodeLanguage {
        guard name == "script" else { return .css }

        let range = NSRange(tagText.startIndex..., in: tagText)
        guard let match = languagePattern?.firstMatch(in: tagText, range: range),
              let swiftRange = Range(match.range(at: 1), in: tagText) else {
            return .javascript
        }

        switch tagText[swiftRange].lowercased() {
        case "ts", "typescript":
            return .typescript
        case "tsx":
            return .tsx
        case "jsx":
            return .jsx
        default:
            return .javascript
        }
    }
}

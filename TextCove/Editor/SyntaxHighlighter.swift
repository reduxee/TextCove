import CodeEditLanguages
import Foundation
import SwiftTreeSitter

struct HighlightToken {
    let range: NSRange
    let captureName: String
}

/// 高亮入口：按文件类型分派到 tree-sitter、Vue 分区投影或内置正则规则。
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    static let maximumHighlightUnits = 1_000_000

    private let queue = DispatchQueue(
        label: "com.textcove.TextCove.syntax-highlighting",
        qos: .userInitiated
    )

    private init() {}

    func highlight(
        text: String,
        fileURL: URL,
        completion: @escaping ([HighlightToken]) -> Void
    ) {
        guard !text.isEmpty, text.utf16.count <= Self.maximumHighlightUnits else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let engine = FileKind(fileURL: fileURL).highlighting
        let url = fileURL

        queue.async {
            let tokens = Self.tokens(for: engine, text: text, fileURL: url)
            DispatchQueue.main.async {
                completion(tokens)
            }
        }
    }

    private static func tokens(
        for engine: HighlightEngine,
        text: String,
        fileURL: URL
    ) -> [HighlightToken] {
        switch engine {
        case .treeSitter:
            return TreeSitterEngine.tokens(
                text: text,
                language: TreeSitterEngine.detectLanguage(text: text, fileURL: fileURL)
            )
        case .vueSFC:
            return VueHighlighter.tokens(text: text)
        case .regex(let syntax):
            return RegexHighlighter.tokens(text: text, syntax: syntax)
        case .none:
            return []
        }
    }
}

enum TreeSitterEngine {
    /// 扩展名之外还带上首尾缓冲，让 shebang 与 vim/emacs modeline 也能决定语言。
    static func detectLanguage(text: String, fileURL: URL) -> CodeLanguage {
        CodeLanguage.detectLanguageFrom(
            url: fileURL,
            prefixBuffer: String(String(text.prefix(400))),
            suffixBuffer: String(String(text.suffix(400)))
        )
    }

    static func tokens(text: String, language: CodeLanguage) -> [HighlightToken] {
        guard let tsLanguage = language.language,
              let query = TreeSitterModel.shared.query(for: language.id) else {
            return []
        }

        do {
            let parser = Parser()
            try parser.setLanguage(tsLanguage)

            guard let tree = parser.parse(text) else {
                return []
            }

            let cursor = query.execute(in: tree)
            let sequence = ResolvingQueryMatchSequence(
                sequence: cursor,
                context: Predicate.Context(string: text)
            )

            var tokens: [HighlightToken] = []

            for match in sequence {
                for capture in match.captures {
                    guard let name = capture.name,
                          name != "none",
                          capture.range.length > 0 else {
                        continue
                    }

                    tokens.append(HighlightToken(range: capture.range, captureName: name))
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
        } catch {
            return []
        }
    }
}

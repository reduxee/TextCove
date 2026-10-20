import Foundation
import JavaScriptCore

@MainActor
enum CodeFormatter {
    static func format(_ source: String, kind: FileKind, compactJSON: Bool = false) throws -> String {
        switch kind {
        case .json:
            return try JSONFormatter.format(source, compact: compactJSON)
        case .javascript, .html, .css:
            return try JavaScriptBeautifier.shared.beautify(source, kind: kind)
        default:
            throw FormattingError.unsupportedFileType
        }
    }
}

enum FormattingError: LocalizedError {
    case unsupportedFileType
    case missingResource(String)
    case scriptFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "当前文件类型不支持格式化。"
        case .missingResource(let name):
            return "找不到内置格式化资源 \(name)，请检查 App Bundle 中的 Resources。"
        case .scriptFailure(let message):
            return "内置格式化引擎执行失败：\(message)"
        }
    }
}

@MainActor
private final class JavaScriptBeautifier {
    static let shared = JavaScriptBeautifier()

    private var context: JSContext?
    private var initializationError: Error?
    private var didInitialize = false

    private init() {}

    func beautify(_ source: String, kind: FileKind) throws -> String {
        try initializeIfNeeded()

        guard let context else {
            throw initializationError ?? FormattingError.scriptFailure("JavaScript 运行环境不可用。")
        }

        let functionName: String
        switch kind {
        case .javascript:
            functionName = "js_beautify"
        case .html:
            functionName = "html_beautify"
        case .css:
            functionName = "css_beautify"
        default:
            throw FormattingError.unsupportedFileType
        }

        guard let function = context.objectForKeyedSubscript(functionName), function.isObject else {
            throw FormattingError.scriptFailure("未找到 \(functionName) 函数。")
        }

        let options: [String: Any] = [
            "indent_size": 2,
            "indent_char": " ",
            "preserve_newlines": true,
            "max_preserve_newlines": 2,
            "end_with_newline": false,
            "wrap_line_length": 120
        ]

        context.exception = nil
        let result = function.call(withArguments: [source, options])

        if let exception = context.exception {
            let message = exception.toString() ?? "未知 JavaScript 错误"
            context.exception = nil
            throw FormattingError.scriptFailure(message)
        }

        guard let result, result.isString, let output = result.toString() else {
            throw FormattingError.scriptFailure("格式化函数没有返回字符串。")
        }

        return output
    }

    private func initializeIfNeeded() throws {
        if didInitialize {
            if let initializationError {
                throw initializationError
            }
            return
        }
        didInitialize = true

        guard let context = JSContext() else {
            let error = FormattingError.scriptFailure("无法创建 JavaScriptCore 上下文。")
            initializationError = error
            throw error
        }
        self.context = context

        // js-beautify 的 UMD 构建会探测 self/window/global；JavaScriptCore 默认没有这些浏览器全局量。
        if let globalObject = context.globalObject {
            globalObject.setValue(globalObject, forProperty: "self")
            globalObject.setValue(globalObject, forProperty: "window")
            globalObject.setValue(globalObject, forProperty: "global")
        }

        do {
            for resourceName in ["beautify-js", "beautify-html", "beautify-css"] {
                guard let url = Bundle.main.url(forResource: resourceName, withExtension: "js") else {
                    throw FormattingError.missingResource("\(resourceName).js")
                }
                let scriptData = try Data(contentsOf: url)
                let script = String(decoding: scriptData, as: UTF8.self)

                context.exception = nil
                context.evaluateScript(script, withSourceURL: url)
                if let exception = context.exception {
                    let message = exception.toString() ?? "JavaScript 脚本加载失败"
                    context.exception = nil
                    throw FormattingError.scriptFailure(message)
                }
            }
        } catch {
            initializationError = error
            throw error
        }
    }
}

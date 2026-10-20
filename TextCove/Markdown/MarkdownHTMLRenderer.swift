import Foundation
import JavaScriptCore

enum MarkdownRenderError: LocalizedError {
    case missingResource
    case invalidRuntime
    case javascript(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "找不到内置的 markdown-it 资源。"
        case .invalidRuntime:
            return "Markdown 渲染器初始化失败。"
        case .javascript(let message):
            return "Markdown 渲染失败：\(message)"
        case .emptyResult:
            return "Markdown 渲染器没有返回 HTML。"
        }
    }
}

@MainActor
final class MarkdownHTMLRenderer {
    static let shared = MarkdownHTMLRenderer()

    private var context: JSContext?
    private var markdownIt: JSValue?
    private var initializationError: Error?
    private var didInitialize = false

    private init() {}

    func renderMarkdownToHTML(_ markdown: String) throws -> String {
        try initializeIfNeeded()

        guard let context, let markdownIt else {
            throw initializationError ?? MarkdownRenderError.invalidRuntime
        }

        context.exception = nil
        let value = markdownIt.invokeMethod("render", withArguments: [markdown])

        if let exception = context.exception {
            let message = exception.toString() ?? "未知 JavaScript 错误"
            context.exception = nil
            throw MarkdownRenderError.javascript(message)
        }

        guard let value, value.isString, let html = value.toString() else {
            throw MarkdownRenderError.emptyResult
        }

        return html
    }

    func renderDocuments(rawHTML: String) -> String {
        MarkdownHTMLDocument.make(bodyHTML: rawHTML)
    }

    func renderErrorPage(message: String) -> String {
        MarkdownHTMLDocument.makeError(message: message)
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
            let error = MarkdownRenderError.invalidRuntime
            initializationError = error
            throw error
        }
        self.context = context

        do {
            guard let url = Bundle.main.url(
                forResource: "markdown-it.min",
                withExtension: "js"
            ) else {
                throw MarkdownRenderError.missingResource
            }

            let scriptData = try Data(contentsOf: url)
            let script = String(decoding: scriptData, as: UTF8.self)

            context.exception = nil
            context.evaluateScript(script, withSourceURL: url)
            if let exception = context.exception {
                let message = exception.toString() ?? "脚本加载失败"
                context.exception = nil
                throw MarkdownRenderError.javascript(message)
            }

            guard let factory = context.objectForKeyedSubscript("markdownit"),
                  !factory.isUndefined else {
                throw MarkdownRenderError.invalidRuntime
            }

            let options: [String: Any] = [
                "html": true,
                "linkify": true,
                "typographer": false,
                "breaks": false,
                "xhtmlOut": false
            ]

            context.exception = nil
            guard let instance = factory.call(withArguments: [options]) else {
                throw MarkdownRenderError.invalidRuntime
            }
            if let exception = context.exception {
                let message = exception.toString() ?? "markdown-it 初始化失败"
                context.exception = nil
                throw MarkdownRenderError.javascript(message)
            }

            context.globalObject?.setValue(instance, forProperty: "__textcoveMarkdown")
            context.exception = nil
            context.evaluateScript(
                """
                (function(md) {
                  var fallback = md.renderer.rules.image;
                  md.renderer.rules.image = function(tokens, idx, options, env, self) {
                    var token = tokens[idx];
                    var index = token.attrIndex('src');
                    if (index >= 0) {
                      var src = token.attrs[index][1];
                      var hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(src);
                      if (src && src.charAt(0) !== '#' && src.indexOf('//') !== 0 && !hasScheme) {
                        token.attrs[index][1] =
                          'textcove-asset://local/' + src.replace(/^\\/+/, '');
                      }
                    }
                    if (fallback) {
                      return fallback(tokens, idx, options, env, self);
                    }
                    return self.renderToken(tokens, idx, options);
                  };

                  function renderNumberedCodeBlock(content, info) {
                    var normalized = content || '';
                    if (normalized.length > 0 && normalized.charAt(normalized.length - 1) === '\\n') {
                      normalized = normalized.slice(0, -1);
                    }

                    var count = normalized.length === 0 ? 1 : normalized.split('\\n').length;
                    var numbers = [];
                    for (var line = 1; line <= count; line++) {
                      numbers.push(line);
                    }

                    var language = '';
                    var languageName = info ? info.trim().split(/\\s+/)[0] : '';
                    if (languageName) {
                      language = ' class="language-' + md.utils.escapeHtml(languageName) + '"';
                    }

                    return '<pre class="code-block"><code' + language + '>'
                      + '<span class="code-line-numbers" aria-hidden="true">'
                      + numbers.join('\\n')
                      + '</span>'
                      + '<span class="code-block-lines">'
                      + md.utils.escapeHtml(normalized)
                      + '</span></code></pre>\\n';
                  }

                  md.renderer.rules.fence = function(tokens, idx) {
                    return renderNumberedCodeBlock(tokens[idx].content, tokens[idx].info || '');
                  };
                  md.renderer.rules.code_block = function(tokens, idx) {
                    return renderNumberedCodeBlock(tokens[idx].content, '');
                  };

                  md.core.ruler.after('inline', 'textcove-task-lists', function(state) {
                    var tokens = state.tokens;
                    for (var i = 2; i < tokens.length; i++) {
                      if (tokens[i].type !== 'inline' || tokens[i - 2].type !== 'list_item_open') {
                        continue;
                      }
                      var children = tokens[i].children;
                      if (!children || children.length === 0) {
                        continue;
                      }
                      var first = children[0];
                      if (!first || first.type !== 'text') {
                        continue;
                      }
                      var match = first.content.match(/^\\[([ xX])\\]\\s+/);
                      if (!match) {
                        continue;
                      }
                      first.content = first.content.slice(match[0].length);
                      var checkbox = new state.Token('html_inline', '', 0);
                      checkbox.content = '<input class="task-list-item-checkbox" type="checkbox" disabled'
                        + (match[1].toLowerCase() === 'x' ? ' checked' : '') + '>';
                      children.unshift(checkbox);
                      tokens[i - 2].attrJoin('class', 'task-list-item');
                      for (var j = i - 3; j >= 0; j--) {
                        if (tokens[j].type === 'bullet_list_open'
                            || tokens[j].type === 'ordered_list_open') {
                          tokens[j].attrJoin('class', 'contains-task-list');
                          break;
                        }
                      }
                    }
                  });
                })(__textcoveMarkdown);
                """
            )
            if let exception = context.exception {
                let message = exception.toString() ?? "Markdown 图片代理初始化失败"
                context.exception = nil
                throw MarkdownRenderError.javascript(message)
            }

            self.markdownIt = instance
        } catch {
            initializationError = error
            throw error
        }
    }
}

enum MarkdownHTMLDocument {
    static func make(bodyHTML: String) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <meta name="referrer" content="no-referrer">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data: https: http: textcove-asset:; media-src file: https: http:; style-src 'unsafe-inline'; font-src data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'">
          <style>\(MarkdownPreviewStyles.css)</style>
        </head>
        <body>
          <article class="markdown-body">\(bodyHTML)</article>
        </body>
        </html>
        """
    }

    static func makeError(message: String) -> String {
        let escapedMessage = escapeHTML(message)
        let body = """
        <section class="textcove-error">
          <div class="textcove-error-icon">!</div>
          <h1>无法渲染 Markdown</h1>
          <p>\(escapedMessage)</p>
        </section>
        """
        return make(bodyHTML: body)
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

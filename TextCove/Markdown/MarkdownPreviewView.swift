import AppKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()

        let assetHandler = LocalAssetSchemeHandler(baseDirectory: baseURL)
        context.coordinator.assetHandler = assetHandler
        configuration.setURLSchemeHandler(
            assetHandler,
            forURLScheme: PreviewAssetScheme.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        context.coordinator.applyAppearance(colorScheme, to: webView)

        context.coordinator.load(
            markdown: markdown,
            baseURL: baseURL,
            into: webView
        )

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyAppearance(colorScheme, to: webView)
        context.coordinator.load(
            markdown: markdown,
            baseURL: baseURL,
            into: webView
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var assetHandler: LocalAssetSchemeHandler?
        private var lastMarkdown: String?
        private var lastBaseURL: URL?
        private var lastColorScheme: ColorScheme?

        func applyAppearance(_ colorScheme: ColorScheme, to webView: WKWebView) {
            guard lastColorScheme != colorScheme else { return }
            lastColorScheme = colorScheme

            if colorScheme == .dark {
                webView.appearance = NSAppearance(named: .darkAqua)
                webView.underPageBackgroundColor = NSColor(
                    srgbRed: 30.0 / 255.0,
                    green: 30.0 / 255.0,
                    blue: 30.0 / 255.0,
                    alpha: 1
                )
            } else {
                webView.appearance = NSAppearance(named: .aqua)
                webView.underPageBackgroundColor = .white
            }
        }

        func load(markdown: String, baseURL: URL, into webView: WKWebView) {
            guard markdown != lastMarkdown || baseURL != lastBaseURL else { return }
            lastMarkdown = markdown
            lastBaseURL = baseURL

            let html: String
            do {
                let body = try MarkdownHTMLRenderer.shared.renderMarkdownToHTML(markdown)
                html = MarkdownHTMLRenderer.shared.renderDocuments(rawHTML: body)
            } catch {
                html = MarkdownHTMLRenderer.shared.renderErrorPage(
                    message: error.localizedDescription
                )
            }

            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            if let url = navigationAction.request.url {
                let scheme = url.scheme?.lowercased()
                if url.isFileURL || scheme == "http" || scheme == "https" || scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                }
            }

            decisionHandler(.cancel)
        }
    }
}

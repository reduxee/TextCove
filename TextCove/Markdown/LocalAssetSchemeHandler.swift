import Foundation
import UniformTypeIdentifiers
import WebKit

enum PreviewAssetScheme {
    static let scheme = "textcove-asset"
    static let host = "local"
}

final class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private let baseDirectory: URL

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory.standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let requestURL = urlSchemeTask.request.url else {
                throw LocalAssetError.invalidRequest
            }

            let fileExtension = requestURL.pathExtension
            guard let contentType = UTType(filenameExtension: fileExtension),
                  contentType.conforms(to: .image) else {
                throw LocalAssetError.unsupportedType
            }

            let data = try loadAsset(for: requestURL)
            let mimeType = contentType.preferredMIMEType ?? "application/octet-stream"

            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
            )

            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func loadAsset(for url: URL?) throws -> Data {
        guard let url,
              url.scheme == PreviewAssetScheme.scheme,
              url.host == PreviewAssetScheme.host else {
            throw LocalAssetError.invalidRequest
        }

        let path = url.path
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relativePath.isEmpty else {
            throw LocalAssetError.notFound
        }

        let fileURL = baseDirectory
            .appendingPathComponent(relativePath)
            .standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw LocalAssetError.notFound
        }

        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }
}

private enum LocalAssetError: LocalizedError {
    case invalidRequest
    case notFound
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "无效的预览资源请求。"
        case .notFound:
            return "找不到图片资源。"
        case .unsupportedType:
            return "预览代理只允许加载图片资源。"
        }
    }
}

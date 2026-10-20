import Combine
import Foundation

enum MarkdownMode: String, CaseIterable, Identifiable {
    case edit = "编辑"
    case preview = "预览"

    var id: String { rawValue }
}

@MainActor
final class EditorDocument: ObservableObject, Identifiable {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum DocumentError: LocalizedError {
        case notLoaded
        case cannotEncode

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "文件尚未成功读取，无法保存。"
            case .cannotEncode:
                return "当前内容无法编码为 UTF-8。"
            }
        }
    }

    let id = UUID()
    let fileURL: URL
    let kind: FileKind

    @Published var text = ""
    @Published private(set) var savedText = ""
    @Published private(set) var loadState: LoadState
    @Published private(set) var sourceEncoding: String.Encoding = .utf8
    @Published private(set) var encodingLabel = "UTF-8"
    @Published var markdownMode: MarkdownMode = .preview

    private var loadTask: Task<Void, Never>?
    private var strippedBOM = Data()

    init(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        self.fileURL = standardizedURL
        self.kind = FileKind(fileURL: standardizedURL)
        self.loadState = .loading
    }

    var path: String { fileURL.path }
    var name: String { fileURL.lastPathComponent }
    var directoryURL: URL { fileURL.deletingLastPathComponent() }

    var isDirty: Bool {
        loadState == .loaded && text != savedText
    }

    var canSave: Bool {
        isDirty
    }

    var canFormat: Bool {
        kind.supportsFormatting && loadState == .loaded
    }

    var displayTitle: String {
        name + (isDirty ? " *" : "")
    }

    func load() {
        guard loadState != .loaded else { return }

        loadTask?.cancel()
        loadState = .loading
        let url = fileURL
        text = ""
        savedText = ""

        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                TextFileReader.read(from: url)
            }.value

            guard !Task.isCancelled, let self else { return }

            switch result {
            case .success(let content):
                self.text = content.text
                self.savedText = content.text
                self.sourceEncoding = content.encoding
                self.encodingLabel = content.label
                self.strippedBOM = content.bom
                self.loadState = .loaded
            case .failure(let message):
                self.loadState = .failed(message)
            }
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    func save() throws {
        guard loadState == .loaded else {
            throw DocumentError.notLoaded
        }
        guard var data = text.data(using: sourceEncoding) else {
            throw DocumentError.cannotEncode
        }
        if !strippedBOM.isEmpty {
            data = strippedBOM + data
        }

        try data.write(to: fileURL, options: .atomic)
        savedText = text
    }

    func replaceText(with newText: String) {
        guard text != newText else { return }
        text = newText
    }
}

private struct TextFileContent: Sendable {
    let text: String
    let encoding: String.Encoding
    let label: String
    let bom: Data
}

private enum TextFileReadResult: Sendable {
    case success(TextFileContent)
    case failure(String)
}

private enum TextFileReader {
    static func read(from url: URL) -> TextFileReadResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure("文件不存在，或已被移动到其他位置。")
        }
        if isDirectory.boolValue {
            return .failure("这是一个文件夹，TextCove 目前只能打开文件。")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return .failure("读取文件失败：\(error.localizedDescription)")
        }

        if data.isEmpty {
            return .success(TextFileContent(text: "", encoding: .utf8, label: "UTF-8", bom: Data()))
        }

        // UTF-16/UTF-32 靠 BOM 识别；识别不了再按“含 NUL 即二进制”处理。
        if let wide = decodeWide(data) {
            return .success(wide)
        }

        if data.contains(0) {
            return .failure("文件包含二进制数据，无法作为文本打开。")
        }

        var payload = data
        var bom = Data()
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            bom = payload.prefix(3)
            payload.removeFirst(3)
        }

        if let content = String(data: payload, encoding: .utf8) {
            return .success(TextFileContent(text: content, encoding: .utf8, label: "UTF-8", bom: bom))
        }

        // 非 UTF-8 时按“严格编码优先、无损单字节编码兜底”的顺序回退。
        // 新 SDK 移除了 String.Encoding 的中文常量，只能按 CoreFoundation 的编码值取。
        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
        )
        if let content = String(data: payload, encoding: gbk),
           content.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            return .success(TextFileContent(text: content, encoding: gbk, label: "GBK", bom: bom))
        }

        let singleByte: [(String.Encoding, String)] = [
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO-8859-1")
        ]
        for (encoding, label) in singleByte {
            if let content = String(data: payload, encoding: encoding) {
                return .success(TextFileContent(text: content, encoding: encoding, label: label, bom: bom))
            }
        }

        return .failure("无法解码该文件。请先将文件转换为 UTF-8 编码后重试。")
    }

    private static func decodeWide(_ data: Data) -> TextFileContent? {
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]), let text = String(data: data, encoding: .utf32) {
            return TextFileContent(text: text, encoding: .utf32, label: "UTF-32", bom: Data())
        }
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]), let text = String(data: data, encoding: .utf32BigEndian) {
            return TextFileContent(text: text, encoding: .utf32BigEndian, label: "UTF-32 BE", bom: Data())
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return TextFileContent(text: text, encoding: .utf16, label: "UTF-16", bom: Data())
        }
        return nil
    }
}

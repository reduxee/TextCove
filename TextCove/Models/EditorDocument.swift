import Combine
import Foundation

enum TextFileLimits {
    /// 超长行阈值：超过就改用只读折行预览，避免 TextKit 为单行几百万字符做全量排版。
    static let longLineThreshold = 50_000
}

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

    @Published var text = "" {
        didSet { revision &+= 1 }
    }
    @Published private(set) var loadState: LoadState
    @Published private(set) var sourceEncoding: String.Encoding = .utf8
    @Published private(set) var encodingLabel = "UTF-8"
    @Published private(set) var longestLineLength = 0
    @Published private(set) var wrappedPreview = ""
    @Published var prefersEditingLongLineFile = false
    @Published var markdownMode: MarkdownMode = .preview

    /// 只有加载、格式化这类“外部文本”才会推进；编辑器据此决定是否覆盖自身内容，
    /// 避免每次更新都拿 9MB 字符串做比较（桥接字符串比较会走 NFC 归一化，单次可达数百毫秒）。
    private(set) var externalEditToken = 0
    private(set) var revision = 0
    @Published private var savedRevision = 0

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
        loadState == .loaded && revision != savedRevision
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

    var isLongLineHeavy: Bool {
        loadState == .loaded && longestLineLength >= TextFileLimits.longLineThreshold
    }

    var showsWrappedPreview: Bool {
        isLongLineHeavy && !prefersEditingLongLineFile
    }

    func load() {
        guard loadState != .loaded else { return }

        loadTask?.cancel()
        loadState = .loading
        let url = fileURL
        text = ""
        longestLineLength = 0
        wrappedPreview = ""

        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                TextFileReader.read(from: url)
            }.value

            guard !Task.isCancelled, let self else { return }

            switch result {
            case .success(let content):
                self.text = content.text
                self.savedRevision = self.revision
                self.externalEditToken &+= 1
                self.longestLineLength = content.longestLine
                self.wrappedPreview = content.wrappedPreview
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
        savedRevision = revision
    }

    func replaceText(with newText: String) {
        text = newText
        externalEditToken &+= 1
    }
}

private struct TextFileContent: Sendable {
    let text: String
    let encoding: String.Encoding
    let label: String
    let bom: Data
    let longestLine: Int
    let wrappedPreview: String
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
            return success("", encoding: .utf8, label: "UTF-8", bom: Data())
        }

        // UTF-16/UTF-32 靠 BOM 识别；识别不了再按“含 NUL 即二进制”处理。
        if let wide = decodeWide(data) {
            return success(wide.0, encoding: wide.1, label: wide.2, bom: wide.3)
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
            return success(content, encoding: .utf8, label: "UTF-8", bom: bom)
        }

        // 非 UTF-8 时按“严格编码优先、无损单字节编码兜底”的顺序回退。
        // 新 SDK 移除了 String.Encoding 的中文常量，只能按 CoreFoundation 的编码值取。
        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
        )
        if let content = String(data: payload, encoding: gbk),
           content.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            return success(content, encoding: gbk, label: "GBK", bom: bom)
        }

        let singleByte: [(String.Encoding, String)] = [
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO-8859-1")
        ]
        for (encoding, label) in singleByte {
            if let content = String(data: payload, encoding: encoding) {
                return success(content, encoding: encoding, label: label, bom: bom)
            }
        }

        return .failure("无法解码该文件。请先将文件转换为 UTF-8 编码后重试。")
    }

    private static func decodeWide(_ data: Data) -> (String, String.Encoding, String, Data)? {
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]), let text = String(data: data, encoding: .utf32) {
            return (text, .utf32, "UTF-32", Data())
        }
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]), let text = String(data: data, encoding: .utf32BigEndian) {
            return (text, .utf32BigEndian, "UTF-32 BE", Data())
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return (text, .utf16, "UTF-16", Data())
        }
        return nil
    }

    private static func success(
        _ text: String,
        encoding: String.Encoding,
        label: String,
        bom: Data
    ) -> TextFileReadResult {
        let longest = longestLineLength(in: text)
        let preview = longest >= TextFileLimits.longLineThreshold ? wrappedPreview(text) : ""
        return .success(
            TextFileContent(
                text: text,
                encoding: encoding,
                label: label,
                bom: bom,
                longestLine: longest,
                wrappedPreview: preview
            )
        )
    }

    private static func longestLineLength(in text: String) -> Int {
        var longest = 0
        var current = 0
        for unit in text.utf16 {
            if unit == 10 || unit == 13 {
                if current > longest { longest = current }
                current = 0
            } else {
                current += 1
            }
        }
        return max(longest, current)
    }

    /// 只读预览用：按 160 字符硬折行，把超长行拆成大量短行，TextKit 排版成本从秒级降到毫秒级。
    private static func wrappedPreview(_ text: String, width: Int = 160) -> String {
        var output = String()
        output.reserveCapacity(text.utf16.count + text.utf16.count / width)
        var column = 0
        for character in text {
            if character == "\n" {
                column = 0
                output.append(character)
                continue
            }
            if column >= width {
                output.append("\n")
                column = 0
            }
            output.append(character)
            column += 1
        }
        return output
    }
}

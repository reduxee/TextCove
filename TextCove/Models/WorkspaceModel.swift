import AppKit
import Combine
import Foundation

@MainActor
enum WorkspaceAlert {
    case confirmSave(EditorDocument)
    case message(title: String, message: String)

    var title: String {
        switch self {
        case .confirmSave:
            return "确认保存？"
        case .message(let title, _):
            return title
        }
    }

    var message: String {
        switch self {
        case .confirmSave(let document):
            return "将使用编辑器中的内容覆盖磁盘文件：\n\(document.path)\n\n此操作会立即写入原始文件。"
        case .message(_, let message):
            return message
        }
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var documents: [EditorDocument] = []
    @Published var selectedID: EditorDocument.ID?
    @Published var activeAlert: WorkspaceAlert?
    @Published var pendingCloseDocumentID: EditorDocument.ID?

    private struct DocumentSummary: Equatable {
        let canSave: Bool
        let canFormat: Bool
    }

    private var documentObservers: [EditorDocument.ID: AnyCancellable] = [:]
    private var documentSummaries: [EditorDocument.ID: DocumentSummary] = [:]

    var selectedDocument: EditorDocument? {
        guard let selectedID else { return nil }
        return documents.first { $0.id == selectedID }
    }

    var pendingCloseDocument: EditorDocument? {
        guard let pendingCloseDocumentID else { return nil }
        return documents.first { $0.id == pendingCloseDocumentID }
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "打开文件"
        panel.message = "选择要打开的文件；也可以直接把文件拖入 TextCove 窗口。"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.resolvesAliases = true

        if let selectedDocument {
            panel.directoryURL = selectedDocument.directoryURL
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFiles([url])
    }

    func openFiles(_ urls: [URL]) {
        var resolvedDocuments: [EditorDocument] = []
        var directoryNames: [String] = []
        var seenPaths = Set<String>()

        for rawURL in urls {
            guard rawURL.isFileURL else { continue }
            let url = rawURL.standardizedFileURL
            guard seenPaths.insert(url.path).inserted else { continue }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                directoryNames.append(url.lastPathComponent)
                continue
            }

            if let existing = documents.first(where: { $0.path == url.path }) {
                resolvedDocuments.append(existing)
                continue
            }

            let document = EditorDocument(fileURL: url)
            documents.append(document)
            observe(document)
            document.load()
            resolvedDocuments.append(document)
        }

        if let first = resolvedDocuments.first {
            selectedID = first.id
        }

        if !directoryNames.isEmpty {
            let names = directoryNames.map { "“\($0)”" }.joined(separator: "、")
            activeAlert = .message(
                title: "无法打开文件夹",
                message: "\(names) 是文件夹。TextCove 目前只支持打开文件。"
            )
        }
    }

    func select(_ document: EditorDocument) {
        selectedID = document.id
    }

    func requestSaveSelectedDocument() {
        guard let document = selectedDocument, document.canSave else { return }
        activeAlert = .confirmSave(document)
    }

    func confirmSave(_ document: EditorDocument) {
        activeAlert = nil
        do {
            try document.save()
        } catch {
            showErrorLater(title: "保存失败", message: error.localizedDescription)
        }
    }

    func requestClose(_ document: EditorDocument) {
        if document.isDirty {
            pendingCloseDocumentID = document.id
        } else {
            close(document)
        }
    }

    func cancelPendingClose() {
        pendingCloseDocumentID = nil
    }

    func saveAndClosePendingDocument() {
        guard let document = pendingCloseDocument else {
            pendingCloseDocumentID = nil
            return
        }

        pendingCloseDocumentID = nil
        do {
            try document.save()
            close(document)
        } catch {
            showErrorLater(title: "保存失败", message: error.localizedDescription)
        }
    }

    func discardAndClosePendingDocument() {
        guard let document = pendingCloseDocument else {
            pendingCloseDocumentID = nil
            return
        }

        pendingCloseDocumentID = nil
        close(document)
    }

    func formatSelectedDocument(compactJSON: Bool = false) {
        guard let document = selectedDocument, document.canFormat else { return }

        do {
            let formatted = try CodeFormatter.format(
                document.text,
                kind: document.kind,
                compactJSON: compactJSON
            )
            document.replaceText(with: formatted)
        } catch let error as JSONSyntaxError {
            activeAlert = .message(
                title: "JSON 语法错误",
                message: error.detailedDescription
            )
        } catch {
            activeAlert = .message(
                title: "格式化失败",
                message: error.localizedDescription
            )
        }
    }

    private func close(_ document: EditorDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }

        document.cancelLoading()
        documentObservers.removeValue(forKey: document.id)?.cancel()
        documentSummaries.removeValue(forKey: document.id)

        if pendingCloseDocumentID == document.id {
            pendingCloseDocumentID = nil
        }

        documents.remove(at: index)

        if selectedID == document.id {
            if documents.isEmpty {
                selectedID = nil
            } else if index < documents.count {
                selectedID = documents[index].id
            } else {
                selectedID = documents[documents.count - 1].id
            }
        }
    }

    private func observe(_ document: EditorDocument) {
        documentSummaries[document.id] = summary(for: document)
        documentObservers[document.id] = document.objectWillChange
            .sink { [weak self, weak document] _ in
                DispatchQueue.main.async {
                    guard let self, let document else { return }
                    self.refreshSummary(for: document)
                }
            }
    }

    private func refreshSummary(for document: EditorDocument) {
        guard documents.contains(where: { $0.id == document.id }) else { return }

        let newSummary = summary(for: document)
        guard documentSummaries[document.id] != newSummary else { return }

        documentSummaries[document.id] = newSummary
        objectWillChange.send()
    }

    private func summary(for document: EditorDocument) -> DocumentSummary {
        DocumentSummary(canSave: document.canSave, canFormat: document.canFormat)
    }

    private func showErrorLater(title: String, message: String) {
        let alert = WorkspaceAlert.message(title: title, message: message)
        DispatchQueue.main.async { [weak self] in
            self?.activeAlert = alert
        }
    }
}

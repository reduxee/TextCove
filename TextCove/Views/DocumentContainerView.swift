import SwiftUI

struct DocumentContainerView: View {
    @ObservedObject var document: EditorDocument
    let onOpenFiles: ([URL]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hugeFileIndexProgress: Double = 0

    /// 与 macOS 自身内容面板一致的连续曲率圆角。
    private static let cardCornerRadius: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            if document.isHugeFile {
                hugeFileNotice
            } else if document.encodingLabel != "UTF-8" {
                encodingNotice
            }
            if document.isLongLineHeavy {
                longLineNotice
            }

            contentCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var contentCard: some View {
        ZStack(alignment: .bottomTrailing) {
            documentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                }

            if document.kind.isMarkdown, document.loadState == .loaded {
                markdownModeControl
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var documentBody: some View {
        switch document.loadState {
        case .loading:
            loadingView
        case .loaded:
            if document.isHugeFile {
                HugeFileView(url: document.fileURL, colorScheme: colorScheme) { fraction in
                    hugeFileIndexProgress = fraction
                }
            } else if document.kind.isMarkdown && document.markdownMode == .preview {
                MarkdownPreviewView(
                    markdown: document.text,
                    baseURL: document.directoryURL,
                    colorScheme: colorScheme
                )
            } else {
                editorView
            }
        case .failed(let message):
            DocumentStatusView(
                systemImage: "exclamationmark.triangle",
                title: "无法打开文件",
                message: message,
                path: document.path,
                actionTitle: "重试"
            ) {
                document.load()
            }
        }
    }

    private var editorView: some View {
        CodeEditorPane(
            text: editorText,
            fileURL: document.fileURL,
            colorScheme: colorScheme,
            showsLineNumbers: document.kind.showsLineNumbers && !document.showsWrappedPreview,
            isEditable: !document.showsWrappedPreview,
            wrapsLines: !document.isLongLineHeavy || document.showsWrappedPreview,
            externalEditToken: document.externalEditToken,
            onOpenFiles: onOpenFiles
        )
        .id("\(document.id)-\(document.prefersEditingLongLineFile)")
    }

    private var editorText: Binding<String> {
        document.showsWrappedPreview ? .constant(document.wrappedPreview) : $document.text
    }

    private var hugeFileNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
            Text("\(ByteCountFormatter.string(fromByteCount: document.fileSize, countStyle: .file)) · 只读分页查看")

            if hugeFileIndexProgress < 1 {
                ProgressView(value: hugeFileIndexProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text("正在建立行索引 \(Int(hugeFileIndexProgress * 100))%")
                    .monospacedDigit()
            } else {
                Text("SQL 关键字着色 · 不支持编辑与全文搜索")
            }

            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private var longLineNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")

            if document.showsWrappedPreview {
                Text("该文件含超长行（最长 \(document.longestLineLength.formatted()) 字符），已用只读折行预览打开。")
            } else {
                Text("已关闭自动换行并以可编辑方式打开超长行文件，大范围操作可能变慢。")
            }

            Spacer()

            Button(document.showsWrappedPreview ? "编辑原文件" : "回到只读预览") {
                document.prefersEditingLongLineFile.toggle()
            }
            .buttonStyle(.link)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private var markdownModeControl: some View {
        HStack(spacing: 3) {
            modeButton(.edit, systemImage: "pencil.line")
            modeButton(.preview, systemImage: "eye")
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
        .padding(14)
        .help("切换 Markdown 编辑与预览；两种模式不会同时显示")
    }

    private func modeButton(_ mode: MarkdownMode, systemImage: String) -> some View {
        let isSelected = document.markdownMode == mode

        return Button {
            document.markdownMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background(
            isSelected ? Color.primary.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .help(mode.rawValue)
        .accessibilityLabel(mode.rawValue)
    }

    private var encodingNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
            Text("该文件不是 UTF-8，已按 \(document.encodingLabel) 解码；保存时会沿用这一编码。")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取 \(document.name)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

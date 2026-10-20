import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var workspace: WorkspaceModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if workspace.documents.isEmpty {
                EmptyWorkspaceView(openAction: workspace.openFilePanel)
            } else {
                DocumentTabBar(workspace: workspace)

                if let document = workspace.selectedDocument {
                    DocumentContainerView(
                        document: document,
                        onOpenFiles: workspace.openFiles
                    )
                    .id(document.id)
                } else {
                    EmptyWorkspaceView(openAction: workspace.openFilePanel)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                DropTargetOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: $isDropTargeted
        ) { providers in
            FileDropLoader.loadFileURLs(from: providers) { urls in
                if !urls.isEmpty {
                    workspace.openFiles(urls)
                }
            }
        }
        .navigationTitle("TextCove")
        .navigationSubtitle(workspace.selectedDocument?.path ?? "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    workspace.openFilePanel()
                } label: {
                    Label("打开文件", systemImage: "folder")
                }
                .labelStyle(.titleAndIcon)
                .help("打开文件 (⌘O)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    workspace.requestSaveSelectedDocument()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .labelStyle(.titleAndIcon)
                .disabled(!(workspace.selectedDocument?.canSave ?? false))
                .help("保存当前文件 (⌘S)；保存前会再次确认")

                formatControl
            }
        }
        .alert(
            workspace.activeAlert?.title ?? "",
            isPresented: alertIsPresented,
            presenting: workspace.activeAlert
        ) { alert in
            switch alert {
            case .confirmSave(let document):
                Button("取消", role: .cancel) {
                    workspace.activeAlert = nil
                }
                Button("覆盖保存") {
                    workspace.confirmSave(document)
                }
            case .message:
                Button("好", role: .cancel) {
                    workspace.activeAlert = nil
                }
            }
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            "未保存的修改",
            isPresented: closeDialogIsPresented,
            titleVisibility: .visible,
            presenting: workspace.pendingCloseDocument
        ) { document in
            Button("保存") {
                workspace.saveAndClosePendingDocument()
            }
            Button("丢弃修改", role: .destructive) {
                workspace.discardAndClosePendingDocument()
            }
            Button("取消", role: .cancel) {
                workspace.cancelPendingClose()
            }
        } message: { document in
            Text("“\(document.name)” 包含尚未保存的修改。关闭前要保存吗？")
        }
    }

    private var formatControl: some View {
        Menu {
            if let document = workspace.selectedDocument, document.canFormat {
                if document.kind == .json {
                    Button("格式化 JSON") {
                        workspace.formatSelectedDocument()
                    }
                    Button("压缩 JSON") {
                        workspace.formatSelectedDocument(compactJSON: true)
                    }
                } else {
                    Button("格式化 \(document.kind.displayName)") {
                        workspace.formatSelectedDocument()
                    }
                }
            } else {
                Button("当前文件不可格式化") {}
                    .disabled(true)
            }
        } label: {
            Label("格式化", systemImage: "wand.and.stars")
        } primaryAction: {
            workspace.formatSelectedDocument()
        }
        .labelStyle(.titleAndIcon)
        .disabled(!(workspace.selectedDocument?.canFormat ?? false))
        .help("格式化当前文件 (⇧⌘F)；JSON 的压缩选项在展开菜单中")
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { workspace.activeAlert != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.activeAlert = nil
                }
            }
        )
    }

    private var closeDialogIsPresented: Binding<Bool> {
        Binding(
            get: { workspace.pendingCloseDocument != nil },
            set: { isPresented in
                if !isPresented {
                    workspace.cancelPendingClose()
                }
            }
        )
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.07)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, dash: [9, 6])
                )
                .padding(14)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 38, weight: .medium))
                Text("松开以打开文件")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

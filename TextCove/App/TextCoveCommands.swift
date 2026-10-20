import SwiftUI

struct TextCoveCommands: Commands {
    @ObservedObject var workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开文件…") {
                workspace.openFilePanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                workspace.requestSaveSelectedDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!(workspace.selectedDocument?.canSave ?? false))
        }

        CommandMenu("格式化") {
            Button("格式化当前文件") {
                workspace.formatSelectedDocument()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!(workspace.selectedDocument?.canFormat ?? false))

            Button("压缩 JSON") {
                workspace.formatSelectedDocument(compactJSON: true)
            }
            .disabled(
                !(workspace.selectedDocument?.kind == .json
                  && (workspace.selectedDocument?.canFormat ?? false))
            )
        }
    }
}

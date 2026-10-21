import SwiftUI

struct CodeEditorPane: View {
    @Binding var text: String
    let fileURL: URL
    let colorScheme: ColorScheme
    let showsLineNumbers: Bool
    let isEditable: Bool
    let wrapsLines: Bool
    let externalEditToken: Int
    let onOpenFiles: ([URL]) -> Void

    @StateObject private var viewport = EditorViewport()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if showsLineNumbers {
                LineNumberSidebar(
                    viewport: viewport,
                    colorScheme: colorScheme
                )
                .frame(width: LineNumberSidebar.preferredWidth)
                .frame(maxHeight: .infinity)
                .id(viewport.attachmentGeneration)
            }

            CodeEditorView(
                text: $text,
                fileURL: fileURL,
                colorScheme: colorScheme,
                viewport: viewport,
                isEditable: isEditable,
                wrapsLines: wrapsLines,
                externalEditToken: externalEditToken,
                onOpenFiles: onOpenFiles
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

struct DocumentTabBar: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(workspace.documents) { document in
                        DocumentTabItem(
                            document: document,
                            isSelected: workspace.selectedID == document.id,
                            onSelect: { workspace.select(document) },
                            onClose: { workspace.requestClose(document) }
                        )
                        .id(document.id)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
            }
            .onChange(of: workspace.selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 40)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DocumentTabItem: View {
    @ObservedObject var document: EditorDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Image(systemName: document.kind.systemImageName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 15)

                    Text(document.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 176, alignment: .leading)

                    if document.isDirty {
                        Text("*")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.orange)
                            .accessibilityLabel("有未保存的修改")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(document.path)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isSelected ? 0.88 : 0.55)
            .help("关闭“\(document.name)”")
            .accessibilityLabel("关闭 \(document.name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(tabBackground)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primary.opacity(0.08) : Color.clear,
                        lineWidth: 1
                    )
            }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(nsColor: .textBackgroundColor)
        }
        if isHovering {
            return Color.primary.opacity(0.055)
        }
        return Color.clear
    }
}

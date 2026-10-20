import SwiftUI

struct EmptyWorkspaceView: View {
    let openAction: () -> Void

    private let formats = ["md", "ts", "js", "html", "css", "java", "c", "swift", "yml", "json", "plist", "txt"]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .textBackgroundColor),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "doc.text")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 92, height: 92)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                    )

                VStack(spacing: 7) {
                    Text("TextCove")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))

                    Text("轻量、原生的 macOS 文件查看与编辑器")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 9) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text("将文件拖入窗口，或点击下方按钮打开")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 470)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                        )
                }

                Button(action: openAction) {
                    Label("打开文件", systemImage: "folder")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(formats, id: \.self) { format in
                            Text(format)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                    }

                    Text("以及任意 UTF-8 文本文件")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
            .padding(40)
        }
    }
}

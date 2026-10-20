import AppKit
import Combine

@MainActor
final class EditorViewport: ObservableObject {
    private(set) weak var textView: NSTextView?
    private(set) weak var scrollView: NSScrollView?

    @Published private(set) var attachmentGeneration = 0

    func attach(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        self.scrollView = scrollView

        // 在 Representable 构建期间修改发布状态会触发 SwiftUI 警告，延迟到下一轮主循环。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachmentGeneration &+= 1
        }
    }
}

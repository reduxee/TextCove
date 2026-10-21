import AppKit
import SwiftUI

struct LineNumberSidebar: NSViewRepresentable {
    static let preferredWidth: CGFloat = 54

    let viewport: EditorViewport
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> LineNumberSidebarNSView {
        let view = LineNumberSidebarNSView()
        view.applyTheme(EditorTheme.resolve(colorScheme: colorScheme))
        if let textView = viewport.textView, let scrollView = viewport.scrollView {
            view.attachIfNeeded(textView: textView, scrollView: scrollView)
        }
        return view
    }

    func updateNSView(_ nsView: LineNumberSidebarNSView, context: Context) {
        nsView.applyTheme(EditorTheme.resolve(colorScheme: colorScheme))

        if let textView = viewport.textView, let scrollView = viewport.scrollView {
            nsView.attachIfNeeded(textView: textView, scrollView: scrollView)
        } else {
            nsView.detach()
        }
    }
}

final class LineNumberSidebarNSView: NSView {
    private weak var textView: NSTextView?
    private weak var editorScrollView: NSScrollView?
    private var lineStartOffsets: [Int] = [0]
    private var observers: [NSObjectProtocol] = []
    private var pendingReload: DispatchWorkItem?
    private var scanGeneration = 0

    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let trailingPadding: CGFloat = 10

    private var numberColor = NSColor.secondaryLabelColor {
        didSet { needsDisplay = true }
    }
    private var dividerColor = NSColor.separatorColor {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    func applyTheme(_ theme: EditorTheme) {
        numberColor = theme.comment.withAlphaComponent(0.85)
        dividerColor = theme.foreground.withAlphaComponent(0.10)
        needsDisplay = true
    }

    func attachIfNeeded(textView: NSTextView, scrollView: NSScrollView) {
        guard self.textView !== textView || self.editorScrollView !== scrollView else {
            return
        }

        removeObservers()
        self.textView = textView
        self.editorScrollView = scrollView
        setUpObservers()
        reloadLineNumbers()
    }

    func detach() {
        guard textView != nil || editorScrollView != nil else { return }
        removeObservers()
        textView = nil
        editorScrollView = nil
        lineStartOffsets = [0]
        needsDisplay = true
    }

    deinit {
        removeObservers()
    }

    override func scrollWheel(with event: NSEvent) {
        editorScrollView?.scrollWheel(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        // SwiftUI 交给这个 NSView 的脏区可能大于自身帧，整片填充会把上方的 Tab 栏刷成背景色；
        // 因此背景交给 CodeEditorPane 的 .background，这里只在 bounds 内画内容。
        let clip = dirtyRect.intersection(bounds)
        guard !clip.isEmpty else { return }

        dividerColor.setFill()
        NSRect(
            x: bounds.width - 0.5,
            y: clip.minY,
            width: 0.5,
            height: clip.height
        ).fill(using: .sourceOver)

        guard let textView,
              let editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let scrollOffset = editorScrollView.contentView.bounds.minY
        let viewportHeight = editorScrollView.contentView.bounds.height
        guard viewportHeight > 0 else { return }

        let insetTop = textView.textContainerInset.height
        let visibleContainerRect = NSRect(
            x: 0,
            y: max(0, scrollOffset - insetTop - 24),
            width: max(1, textContainer.size.width),
            height: viewportHeight + 48
        )
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )

        let textLength = (textView.string as NSString).length
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: numberColor,
            .paragraphStyle: paragraphStyle
        ]

        var currentLineIndex = lineIndex(containingOrBefore: visibleCharacterRange.location)

        while currentLineIndex < lineStartOffsets.count {
            let characterIndex = lineStartOffsets[currentLineIndex]
            if characterIndex > NSMaxRange(visibleCharacterRange) {
                break
            }

            let fragmentRect = lineFragmentRect(
                forCharacterAt: characterIndex,
                textLength: textLength,
                layoutManager: layoutManager
            )
            let y = insetTop + fragmentRect.minY - scrollOffset
            if y > bounds.height {
                break
            }

            if y + fragmentRect.height >= 0 {
                let number = NSAttributedString(
                    string: "\(currentLineIndex + 1)",
                    attributes: attributes
                )
                let numberHeight = number.size().height
                let drawRect = NSRect(
                    x: 0,
                    y: y + max(0, (fragmentRect.height - numberHeight) / 2),
                    width: bounds.width - trailingPadding,
                    height: numberHeight
                )
                number.draw(in: drawRect)
            }

            currentLineIndex += 1
        }
    }

    private func setUpObservers() {
        editorScrollView?.contentView.postsBoundsChangedNotifications = true
        textView?.postsFrameChangedNotifications = true

        let center = NotificationCenter.default
        let queue = OperationQueue.main

        if let textView {
            observers.append(
                center.addObserver(
                    forName: NSText.didChangeNotification,
                    object: textView,
                    queue: queue
                ) { [weak self] _ in
                    self?.scheduleReload()
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: textView,
                    queue: queue
                ) { [weak self] _ in
                    self?.needsDisplay = true
                }
            )
        }

        if let contentView = editorScrollView?.contentView {
            observers.append(
                center.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: contentView,
                    queue: queue
                ) { [weak self] _ in
                    self?.needsDisplay = true
                }
            )
        }
    }

    /// 全文行首扫描在 20 万行文件上约 80ms；击键时防抖，避免每个字符都扫一遍。
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadLineNumbers()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func removeObservers() {
        pendingReload?.cancel()
        pendingReload = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func reloadLineNumbers() {
        guard let textView else {
            scanGeneration += 1
            lineStartOffsets = [0]
            needsDisplay = true
            return
        }

        // 20 万行的全文扫描约 80ms，放后台做；先在主线程把 UTF-16 缓冲复制出来，
        // 后台扫描就完全不会再触碰正在编辑的文本存储。
        let nsText = textView.string as NSString
        let length = nsText.length
        var buffer = [unichar](repeating: 0, count: length)
        if length > 0 {
            nsText.getCharacters(&buffer, range: NSRange(location: 0, length: length))
        }

        scanGeneration += 1
        let generation = scanGeneration

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var starts = [0]
            starts.reserveCapacity(max(1, length / 40))
            var index = 0

            while index < length {
                var breakLength = 0
                switch buffer[index] {
                case 0x000D:
                    breakLength = index + 1 < length && buffer[index + 1] == 0x000A ? 2 : 1
                case 0x000A, 0x0085, 0x2028, 0x2029:
                    breakLength = 1
                default:
                    breakLength = 0
                }

                if breakLength > 0 {
                    index += breakLength
                    starts.append(index)
                } else {
                    index += 1
                }
            }

            DispatchQueue.main.async {
                guard let self,
                      self.scanGeneration == generation,
                      self.textView?.textStorage?.length == length else { return }
                self.lineStartOffsets = starts
                self.needsDisplay = true
            }
        }
    }

    private func lineFragmentRect(
        forCharacterAt characterIndex: Int,
        textLength: Int,
        layoutManager: NSLayoutManager
    ) -> NSRect {
        if textLength == 0 || characterIndex >= textLength {
            let extraRect = layoutManager.extraLineFragmentRect
            if extraRect.height > 0 {
                return extraRect
            }

            let fallbackHeight = textView?.font.map {
                layoutManager.defaultLineHeight(for: $0)
            } ?? numberFont.ascender - numberFont.descender
            return NSRect(x: 0, y: 0, width: 0, height: fallbackHeight)
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }

    private func lineIndex(containingOrBefore characterIndex: Int) -> Int {
        guard !lineStartOffsets.isEmpty else { return 0 }

        var lowerBound = 0
        var upperBound = lineStartOffsets.count - 1
        var result = 0

        while lowerBound <= upperBound {
            let middle = (lowerBound + upperBound) / 2
            if lineStartOffsets[middle] <= characterIndex {
                result = middle
                lowerBound = middle + 1
            } else {
                upperBound = middle - 1
            }
        }

        return result
    }
}

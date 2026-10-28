import AppKit
import SwiftUI

/// 超大文件（>64MB）的只读查看器：只绘制可见的几十行，不创建整文件文本存储。
struct HugeFileView: NSViewRepresentable {
    let url: URL
    let colorScheme: ColorScheme
    let onProgress: (Double) -> Void

    func makeNSView(context: Context) -> HugeFileTextView {
        let view = HugeFileTextView(url: url, colorScheme: colorScheme)
        view.onProgress = { fraction in
            DispatchQueue.main.async { onProgress(fraction) }
        }
        return view
    }

    func updateNSView(_ nsView: HugeFileTextView, context: Context) {
        nsView.apply(colorScheme: colorScheme)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HugeFileTextView,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }
}

final class HugeFileTextView: NSView {
    private let file: MappedTextFile?
    private let openError: String?

    private var theme: EditorTheme
    private let lineFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var lineHeight: CGFloat = 19
    private var gutterWidth: CGFloat = 62

    private var topLine = 0
    private var topOffset = 0
    private var scrollRemainder: CGFloat = 0

    private var selectionAnchor: Int?
    private var selectionFocus: Int?

    private var lineCache: [Int: NSAttributedString] = [:]
    private var progress: Double = 0
    var onProgress: ((Double) -> Void)? {
        didSet { onProgress?(progress) }
    }
    private let scroller = NSScroller()
    private var totalLines = 0

    private let maximumLineBytes = 16_000

    init(url: URL, colorScheme: ColorScheme) {
        self.theme = EditorTheme.resolve(colorScheme: colorScheme)

        do {
            let mapped = try MappedTextFile(url: url)
            self.file = mapped
            self.openError = nil
            super.init(frame: .zero)

            lineHeight = ceil(lineFont.ascender - lineFont.descender) + 4
            mapped.onIndexProgress = { [weak self] fraction in
                guard let self else { return }
                self.progress = fraction
                self.onProgress?(fraction)
            }
            mapped.onIndexFinished = { [weak self] count in
                guard let self else { return }
                self.totalLines = count
                self.scroller.isEnabled = true
                self.updateGutterWidth()
                self.syncScroller()
                self.needsDisplay = true
            }
            mapped.buildIndexInBackground()
        } catch {
            self.file = nil
            self.openError = error.localizedDescription
            super.init(frame: .zero)
        }

        scroller.target = self
        scroller.action = #selector(scrollerChanged(_:))
        scroller.isEnabled = false
        scroller.knobStyle = .light
        addSubview(scroller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func apply(colorScheme: ColorScheme) {
        let resolved = EditorTheme.resolve(colorScheme: colorScheme)
        guard resolved.background != theme.background else { return }
        theme = resolved
        lineCache.removeAll()
        scroller.knobStyle = colorScheme == .dark ? .light : .dark
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        scroller.frame = NSRect(
            x: bounds.width - width - 2,
            y: 2,
            width: width,
            height: max(0, bounds.height - 4)
        )
        syncScroller()
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let clip = dirtyRect.intersection(bounds)
        guard !clip.isEmpty else { return }

        theme.background.setFill()
        clip.fill()

        if let openError {
            ("无法打开：\(openError)" as NSString).draw(
                at: NSPoint(x: 20, y: 20),
                withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
            )
            return
        }

        guard let file else { return }

        let textLeft = gutterWidth + 8
        let visibleRows = max(1, Int(ceil(bounds.height / lineHeight)))

        // gutter 分隔线
        theme.foreground.withAlphaComponent(0.10).setFill()
        NSRect(x: gutterWidth - 0.5, y: clip.minY, width: 0.5, height: clip.height).fill()

        var offset = topOffset
        var line = topLine
        var row = 0

        while row < visibleRows, offset <= file.size {
            let y = CGFloat(row) * lineHeight
            let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)

            if rowRect.intersects(clip) {
                drawRow(line: line, offset: offset, y: y, textLeft: textLeft)
            }

            let end = file.lineEnd(from: offset)
            if end >= file.size { break }
            offset = end + 1
            line += 1
            row += 1
        }

    }

    private func drawRow(line: Int, offset: Int, y: CGFloat, textLeft: CGFloat) {
        let isSelected: Bool = {
            guard let anchor = selectionAnchor, let focus = selectionFocus else { return false }
            return line >= min(anchor, focus) && line <= max(anchor, focus)
        }()

        if isSelected {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
        }

        let number = "\(line + 1)" as NSString
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: theme.comment
        ]
        let numberSize = number.size(withAttributes: numberAttributes)
        number.draw(
            at: NSPoint(x: gutterWidth - 12 - numberSize.width, y: y + (lineHeight - numberSize.height) / 2),
            withAttributes: numberAttributes
        )

        let attributed = cachedLine(line: line, offset: offset)
        attributed.draw(at: NSPoint(x: textLeft, y: y + 1))
    }

    private func cachedLine(line: Int, offset: Int) -> NSAttributedString {
        if let cached = lineCache[line] { return cached }
        guard let file else { return NSAttributedString(string: "") }

        let end = file.lineEnd(from: offset)
        let (text, truncated) = file.text(from: offset, to: end, maxBytes: maximumLineBytes)
        let display = truncated ? text + "  …（已截断）" : text

        let attributed = NSMutableAttributedString(
            string: display,
            attributes: [.font: lineFont, .foregroundColor: theme.foreground]
        )
        if truncated {
            attributed.addAttribute(
                .foregroundColor,
                value: theme.comment,
                range: NSRange(location: (text as NSString).length, length: attributed.length - (text as NSString).length)
            )
        }

        for run in SQLLineTokenizer.runs(in: text) {
            guard NSMaxRange(run.range) <= attributed.length else { continue }
            attributed.addAttribute(.foregroundColor, value: color(for: run.kind), range: run.range)
        }

        if lineCache.count > 400 { lineCache.removeAll(keepingCapacity: true) }
        lineCache[line] = attributed
        return attributed
    }

    private func color(for kind: SQLLineTokenizer.Kind) -> NSColor {
        switch kind {
        case .keyword: return theme.keyword
        case .string: return theme.string
        case .number: return theme.number
        case .comment: return theme.comment
        case .identifier: return theme.property
        }
    }

    // MARK: - 滚动

    override func scrollWheel(with event: NSEvent) {
        let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        guard raw != 0 else { return }

        scrollRemainder += raw
        let lines = Int((scrollRemainder / lineHeight).rounded(.towardZero))
        guard lines != 0 else { return }
        scrollRemainder -= CGFloat(lines) * lineHeight
        scrollByLines(lines)
    }

    private func scrollByLines(_ delta: Int) {
        guard let file else { return }
        guard delta != 0 else { return }

        var line = topLine
        var offset = topOffset

        if delta > 0 {
            var remaining = delta
            while remaining > 0 {
                let end = file.lineEnd(from: offset)
                guard end < file.size else { break }
                offset = end + 1
                line += 1
                remaining -= 1
            }
        } else {
            var remaining = -delta
            while remaining > 0 {
                guard let previous = file.previousLineStart(before: offset) else { break }
                offset = previous
                line -= 1
                remaining -= 1
            }
        }

        topLine = max(0, line)
        topOffset = offset
        syncScroller()
        needsDisplay = true
    }

    private func scrollTo(line: Int, offset: Int) {
        topLine = max(0, line)
        topOffset = offset
        syncScroller()
        needsDisplay = true
    }

    private func syncScroller() {
        guard let file else { return }
        scroller.doubleValue = Double(topOffset) / Double(max(1, file.size))

        let approximateVisibleBytes = Double(max(1, Int(bounds.height / lineHeight))) * 240
        scroller.knobProportion = min(1, max(0.02, approximateVisibleBytes / Double(max(1, file.size))))
    }

    @objc private func scrollerChanged(_ sender: NSScroller) {
        guard let file, file.indexComplete else { return }
        let target = Int(Double(file.size) * sender.doubleValue)
        let position = file.lineNumber(at: target)
        scrollTo(line: position.line, offset: position.start)
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        guard let file else {
            super.keyDown(with: event)
            return
        }

        let page = max(1, Int(bounds.height / lineHeight) - 1)
        switch event.keyCode {
        case 116: // Page Up
            scrollByLines(-page)
        case 121: // Page Down
            scrollByLines(page)
        case 115: // Home
            scrollTo(line: 0, offset: 0)
        case 119: // End
            guard file.indexComplete else { return }
            let position = file.lineNumber(at: max(0, file.size - 1))
            scrollTo(line: position.line, offset: position.start)
        case 126: // Up
            scrollByLines(-1)
        case 125: // Down
            scrollByLines(1)
        default:
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                copySelection()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: - 选择与复制

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let line = topLine + max(0, Int(point.y / lineHeight))

        if event.modifierFlags.contains(.shift), selectionAnchor != nil {
            selectionFocus = line
        } else {
            selectionAnchor = line
            selectionFocus = line
        }
        needsDisplay = true
    }

    private func copySelection() {
        guard let file, let anchor = selectionAnchor, let focus = selectionFocus else { return }
        let lower = min(anchor, focus)
        let upper = max(anchor, focus)
        guard upper - lower < 5_000 else { return }

        var text = ""
        // 从当前视口已知位置起算，避免为复制单独做全文件扫描
        var offset = topOffset
        var current = topLine
        if lower < topLine {
            var remaining = topLine - lower
            while remaining > 0, let previous = file.previousLineStart(before: offset) {
                offset = previous
                current -= 1
                remaining -= 1
            }
        } else {
            while current < lower {
                let end = file.lineEnd(from: offset)
                guard end < file.size else { break }
                offset = end + 1
                current += 1
            }
        }

        for line in lower...upper {
            let end = file.lineEnd(from: offset)
            let (content, _) = file.text(from: offset, to: end, maxBytes: 1_000_000)
            text += content
            if line < upper { text += "\n" }
            guard end < file.size else { break }
            offset = end + 1
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func updateGutterWidth() {
        let digits = max(4, String(max(1, totalLines)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: numberFont]).width + 26
        gutterWidth = max(52, ceil(width))
        lineCache.removeAll(keepingCapacity: true)
        needsDisplay = true
    }
}

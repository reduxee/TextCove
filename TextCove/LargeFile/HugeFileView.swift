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
    /// 行内的一段显示宽度（UTF-16 范围，相对行首）
    private struct Segment {
        let offset: Int
        let length: Int
    }

    private let file: MappedTextFile?
    private let openError: String?

    private var theme: EditorTheme
    private let lineFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var lineHeight: CGFloat = 19
    private var characterWidth: CGFloat = 8
    private var columns = 120
    private var gutterWidth: CGFloat = 62

    private var topLine = 0
    private var topOffset = 0
    private var topSegment = 0
    private var scrollRemainder: CGFloat = 0

    private var selectionAnchor: Int?
    private var selectionFocus: Int?

    private var lineCache: [Int: NSAttributedString] = [:]
    private var segmentCache: [Int: [Segment]] = [:]

    private var progress: Double = 0
    private var totalLines = 0
    var onProgress: ((Double) -> Void)? {
        didSet { onProgress?(progress) }
    }

    private let scroller = NSScroller()

    /// 单行最多参与显示/折行的 UTF-16 单元数，防止极端单行文件拖垮绘制
    private let maximumLineUnits = 200_000

    init(url: URL, colorScheme: ColorScheme) {
        self.theme = EditorTheme.resolve(colorScheme: colorScheme)

        do {
            let mapped = try MappedTextFile(url: url)
            self.file = mapped
            self.openError = nil
            super.init(frame: .zero)

            measureFont()
            mapped.onIndexProgress = { [weak self] fraction in
                guard let self else { return }
                self.progress = fraction
                self.onProgress?(fraction)
                self.needsDisplay = true
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
            measureFont()
        }

        scroller.target = self
        scroller.action = #selector(scrollerChanged(_:))
        scroller.isEnabled = false
        scroller.knobStyle = colorScheme == .dark ? .light : .dark
        addSubview(scroller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func measureFont() {
        lineHeight = ceil(lineFont.ascender - lineFont.descender) + 4
        characterWidth = max(1, ("M" as NSString).size(withAttributes: [.font: lineFont]).width)
    }

    func apply(colorScheme: ColorScheme) {
        let resolved = EditorTheme.resolve(colorScheme: colorScheme)
        guard !resolved.background.isEqual(theme.background) else { return }
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

        let textWidth = max(100, bounds.width - gutterWidth - 16)
        let newColumns = max(20, Int(textWidth / characterWidth))
        if newColumns != columns {
            columns = newColumns
            segmentCache.removeAll()
            needsDisplay = true
        }
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

        theme.foreground.withAlphaComponent(0.10).setFill()
        NSRect(x: gutterWidth - 0.5, y: clip.minY, width: 0.5, height: clip.height).fill()

        var line = topLine
        var offset = topOffset
        var segment = topSegment
        var row = 0

        while row < visibleRows, offset <= file.size {
            let segments = segments(forLine: line, offset: offset)
            guard !segments.isEmpty else { break }

            if segment >= segments.count {
                let end = file.lineEnd(from: offset)
                guard end < file.size else { break }
                offset = end + 1
                line += 1
                segment = 0
                continue
            }

            let y = CGFloat(row) * lineHeight
            if NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).intersects(clip) {
                drawRow(segmentIndex: segment, line: line, offset: offset, y: y, textLeft: textLeft)
            }

            row += 1
            segment += 1
        }

        if progress < 1 {
            drawIndexingOverlay()
        }
    }

    private func drawRow(segmentIndex: Int, line: Int, offset: Int, y: CGFloat, textLeft: CGFloat) {
        let isSelected: Bool = {
            guard let anchor = selectionAnchor, let focus = selectionFocus else { return false }
            return line >= min(anchor, focus) && line <= max(anchor, focus)
        }()

        if isSelected {
            // 非激活窗口下 selectedTextBackgroundColor 几乎透明，统一用强调色 + 透明度
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
        }

        if segmentIndex == 0 {
            let number = "\(line + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: theme.comment
            ]
            let size = number.size(withAttributes: attributes)
            number.draw(
                at: NSPoint(x: gutterWidth - 12 - size.width, y: y + (lineHeight - size.height) / 2),
                withAttributes: attributes
            )
        }

        let segments = segments(forLine: line, offset: offset)
        guard segmentIndex < segments.count else { return }
        let segment = segments[segmentIndex]

        let attributed = attributedLine(line: line, offset: offset)
        guard segment.offset < attributed.length else { return }
        let range = NSRange(
            location: segment.offset,
            length: min(segment.length, attributed.length - segment.offset)
        )
        guard range.length > 0 else { return }
        attributed.attributedSubstring(from: range).draw(at: NSPoint(x: textLeft, y: y + 1))
    }

    private func drawIndexingOverlay() {
        let title = "正在建立行索引 \(Int(progress * 100))%" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: theme.foreground
        ]
        let size = title.size(withAttributes: attributes)

        let padding: CGFloat = 12
        let barWidth: CGFloat = 140
        let width = max(size.width, barWidth) + padding * 2
        let height: CGFloat = 46
        let rect = NSRect(x: (bounds.width - width) / 2, y: 16, width: width, height: height)

        theme.background.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        theme.foreground.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        border.lineWidth = 0.5
        border.stroke()

        title.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.minY + 9),
            withAttributes: attributes
        )

        let barRect = NSRect(x: rect.midX - barWidth / 2, y: rect.minY + 27, width: barWidth, height: 4)
        theme.foreground.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()

        let filled = NSRect(
            x: barRect.minX,
            y: barRect.minY,
            width: barRect.width * max(0, min(1, progress)),
            height: barRect.height
        )
        theme.link.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }

    // MARK: - 折行

    private func segments(forLine line: Int, offset: Int) -> [Segment] {
        if let cached = segmentCache[line] { return cached }

        let units = Array(plainLine(line: line, offset: offset).text.utf16)
        var segments: [Segment] = []
        var start = 0
        var column = 0
        var lastBreak = -1
        var index = 0

        while index < units.count {
            let width = displayWidth(units[index])
            if column + width > columns, index > start {
                var cut = index
                if lastBreak > start, index - lastBreak <= 12 {
                    cut = lastBreak + 1
                }
                if cut <= start { cut = index }
                segments.append(Segment(offset: start, length: cut - start))
                start = cut
                column = 0
                lastBreak = -1
                index = cut
                continue
            }

            column += width
            if units[index] == 32 { lastBreak = index }
            index += 1
        }

        if start < units.count {
            segments.append(Segment(offset: start, length: units.count - start))
        }
        if segments.isEmpty {
            segments = [Segment(offset: 0, length: 0)]
        }

        if segmentCache.count > 300 { segmentCache.removeAll(keepingCapacity: true) }
        segmentCache[line] = segments
        return segments
    }

    private func displayWidth(_ unit: UInt16) -> Int {
        if unit < 0x1100 { return 1 }
        switch unit {
        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
             0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6:
            return 2
        default:
            return 1
        }
    }

    // MARK: - 行内容

    private func plainLine(line: Int, offset: Int) -> (text: String, truncated: Bool) {
        guard let file else { return ("", false) }
        let end = file.lineEnd(from: offset)
        return file.text(from: offset, to: end, maxBytes: maximumLineUnits)
    }

    private func attributedLine(line: Int, offset: Int) -> NSAttributedString {
        if let cached = lineCache[line] { return cached }

        let (text, truncated) = plainLine(line: line, offset: offset)
        let display = truncated ? text + "  …（该行过长，已截断显示）" : text

        let attributed = NSMutableAttributedString(
            string: display,
            attributes: [.font: lineFont, .foregroundColor: theme.foreground]
        )
        if truncated {
            let tailStart = (text as NSString).length
            attributed.addAttribute(
                .foregroundColor,
                value: theme.comment,
                range: NSRange(location: tailStart, length: attributed.length - tailStart)
            )
        }

        for run in SQLLineTokenizer.runs(in: text) {
            guard NSMaxRange(run.range) <= attributed.length else { continue }
            attributed.addAttribute(.foregroundColor, value: color(for: run.kind), range: run.range)
        }

        if lineCache.count > 200 { lineCache.removeAll(keepingCapacity: true) }
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
        let rows = Int((scrollRemainder / lineHeight).rounded(.towardZero))
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows) * lineHeight
        scrollByRows(rows)
    }

    private func scrollByRows(_ delta: Int) {
        guard let file, delta != 0 else { return }

        if delta > 0 {
            var remaining = delta
            while remaining > 0 {
                let segments = segments(forLine: topLine, offset: topOffset)
                if topSegment + 1 < segments.count {
                    topSegment += 1
                } else {
                    let end = file.lineEnd(from: topOffset)
                    guard end < file.size else { break }
                    topOffset = end + 1
                    topLine += 1
                    topSegment = 0
                }
                remaining -= 1
            }
        } else {
            var remaining = -delta
            while remaining > 0 {
                if topSegment > 0 {
                    topSegment -= 1
                } else {
                    guard topLine > 0, let previous = file.previousLineStart(before: topOffset) else { break }
                    topLine -= 1
                    topOffset = previous
                    let segments = segments(forLine: topLine, offset: topOffset)
                    topSegment = max(0, segments.count - 1)
                }
                remaining -= 1
            }
        }

        syncScroller()
        needsDisplay = true
    }

    private func scrollTo(line: Int, offset: Int) {
        topLine = max(0, line)
        topOffset = offset
        topSegment = 0
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
        case 116:
            scrollByRows(-page)
        case 121:
            scrollByRows(page)
        case 115:
            scrollTo(line: 0, offset: 0)
        case 119:
            guard file.indexComplete else { return }
            let position = file.lineNumber(at: max(0, file.size - 1))
            scrollTo(line: position.line, offset: position.start)
        case 126:
            scrollByRows(-1)
        case 125:
            scrollByRows(1)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - 选择与复制

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let line = lineAt(point: convert(event.locationInWindow, from: nil)) else { return }
        selectionAnchor = line
        selectionFocus = line
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionAnchor != nil else { return }
        let point = convert(event.locationInWindow, from: nil)

        if point.y < 0 {
            scrollByRows(-1)
        } else if point.y > bounds.height - lineHeight {
            scrollByRows(1)
        }

        if let line = lineAt(point: point) {
            selectionFocus = line
            needsDisplay = true
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard selectionAnchor != nil else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "复制", action: #selector(copy(_:)), keyEquivalent: "c")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func copy(_ sender: Any?) {
        copySelection()
    }

    private func copySelection() {
        guard let file, let anchor = selectionAnchor, let focus = selectionFocus else { return }
        let lower = min(anchor, focus)
        let upper = max(anchor, focus)
        guard upper - lower < 5_000 else { return }

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

        var text = ""
        for line in lower...upper {
            let end = file.lineEnd(from: offset)
            let (content, _) = file.text(from: offset, to: end, maxBytes: 2_000_000)
            text += content
            if line < upper { text += "\n" }
            guard end < file.size else { break }
            offset = end + 1
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 屏幕坐标 → 逻辑行号
    private func lineAt(point: NSPoint) -> Int? {
        guard let file, point.y >= 0, point.y < bounds.height else { return nil }

        let row = Int(point.y / lineHeight)
        var line = topLine
        var offset = topOffset
        var segment = topSegment
        var currentRow = 0

        while currentRow < row {
            let segments = segments(forLine: line, offset: offset)
            if segment + 1 < segments.count {
                segment += 1
            } else {
                let end = file.lineEnd(from: offset)
                guard end < file.size else { return line }
                offset = end + 1
                line += 1
                segment = 0
            }
            currentRow += 1
        }

        return line
    }

    private func updateGutterWidth() {
        let digits = max(4, String(max(1, totalLines)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: numberFont]).width + 26
        gutterWidth = max(52, ceil(width))
        segmentCache.removeAll()
        needsDisplay = true
    }
}

extension HugeFileTextView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return selectionAnchor != nil
        }
        return true
    }
}

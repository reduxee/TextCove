import AppKit
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let fileURL: URL
    let colorScheme: ColorScheme
    let viewport: EditorViewport
    let onOpenFiles: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let theme = EditorTheme.resolve(colorScheme: colorScheme)
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = theme.background
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = theme.background
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: 800,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = CodeTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.registerForDraggedTypes([.fileURL])
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("代码编辑器")

        scrollView.documentView = textView

        context.coordinator.install(
            textView: textView,
            scrollView: scrollView,
            initialText: text,
            theme: theme
        )

        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scrollView: scrollView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: CodeTextView?
        weak var scrollView: NSScrollView?

        private var lastColorScheme: ColorScheme
        private var lastFileURL: URL
        private var pendingHighlightWorkItem: DispatchWorkItem?
        private var highlightGeneration = 0
        private var isApplyingExternalUpdate = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
            self.lastColorScheme = parent.colorScheme
            self.lastFileURL = parent.fileURL
            super.init()
        }

        deinit {
            pendingHighlightWorkItem?.cancel()
        }

        @MainActor
        func install(
            textView: CodeTextView,
            scrollView: NSScrollView,
            initialText: String,
            theme: EditorTheme
        ) {
            self.textView = textView
            self.scrollView = scrollView
            textView.string = initialText
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            applyTheme(theme, to: textView)
            textView.onFileDrop = { [weak self] urls in
                guard let self else { return false }
                self.parent.onOpenFiles(urls)
                return true
            }
            parent.viewport.attach(textView: textView, scrollView: scrollView)
            scheduleHighlight(after: 0.01)
        }

        func update(scrollView: NSScrollView) {
            guard let textView else { return }

            textView.onFileDrop = { [weak self] urls in
                guard let self else { return false }
                self.parent.onOpenFiles(urls)
                return true
            }

            if lastColorScheme != parent.colorScheme {
                lastColorScheme = parent.colorScheme
                applyTheme(EditorTheme.resolve(colorScheme: parent.colorScheme), to: textView)
                scheduleHighlight(after: 0)
            }

            if lastFileURL != parent.fileURL {
                lastFileURL = parent.fileURL
                scheduleHighlight(after: 0)
            }

            if !textView.hasMarkedText(), textView.string != parent.text {
                replaceText(with: parent.text, in: textView)
                scheduleHighlight(after: 0)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate, let textView else { return }
            parent.text = textView.string
            scheduleHighlight(after: 0.12)
        }

        private func replaceText(with newText: String, in textView: CodeTextView) {
            isApplyingExternalUpdate = true
            defer { isApplyingExternalUpdate = false }

            let previousSelection = textView.selectedRange()
            textView.string = newText
            let clampedLocation = min(previousSelection.location, (newText as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            applyBaseAttributes(to: textView)
        }

        private func applyTheme(_ theme: EditorTheme, to textView: CodeTextView) {
            textView.backgroundColor = theme.background
            textView.insertionPointColor = theme.foreground
            textView.font = theme.font
            textView.textColor = theme.foreground
            scrollView?.backgroundColor = theme.background
            scrollView?.contentView.backgroundColor = theme.background
            applyBaseAttributes(to: textView)
        }

        private func applyBaseAttributes(to textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            applyAttributes(to: textView) { _ in }
        }

        private func apply(tokens: [HighlightToken], to textView: NSTextView) {
            guard !textView.hasMarkedText() else {
                scheduleHighlight(after: 0.2)
                return
            }

            let theme = EditorTheme.resolve(colorScheme: parent.colorScheme)
            applyAttributes(to: textView) { textStorage in
                let fullRange = NSRange(location: 0, length: textStorage.length)

                for token in tokens {
                    let range = NSIntersectionRange(token.range, fullRange)
                    guard range.length > 0,
                          let style = theme.style(forCapture: token.captureName) else {
                        continue
                    }

                    textStorage.addAttribute(
                        .foregroundColor,
                        value: style.color,
                        range: range
                    )

                    if style.bold {
                        textStorage.addAttribute(
                            .font,
                            value: theme.emphasizedFont,
                            range: range
                        )
                    }

                    if style.underlined {
                        textStorage.addAttribute(
                            .underlineStyle,
                            value: NSUnderlineStyle.single.rawValue,
                            range: range
                        )
                        textStorage.addAttribute(
                            .underlineColor,
                            value: style.color,
                            range: range
                        )
                    }
                }
            }
        }

        private func applyAttributes(
            to textView: NSTextView,
            extraAttributes: (NSTextStorage) -> Void
        ) {
            guard let textStorage = textView.textStorage else { return }

            let theme = EditorTheme.resolve(colorScheme: parent.colorScheme)
            let selections = textView.selectedRanges
            let undoManager = textView.undoManager

            undoManager?.disableUndoRegistration()
            textStorage.beginEditing()
            textStorage.setAttributes(
                theme.baseAttributes,
                range: NSRange(location: 0, length: textStorage.length)
            )
            extraAttributes(textStorage)
            textStorage.endEditing()
            undoManager?.enableUndoRegistration()

            textView.selectedRanges = selections
            textView.typingAttributes = theme.baseAttributes
            textView.needsDisplay = true
        }

        private func scheduleHighlight(after delay: TimeInterval) {
            pendingHighlightWorkItem?.cancel()
            highlightGeneration += 1
            let generation = highlightGeneration

            guard let textView else { return }
            let snapshot = textView.string
            let fileURL = parent.fileURL

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.highlightGeneration == generation else { return }

                SyntaxHighlighter.shared.highlight(
                    text: snapshot,
                    fileURL: fileURL
                ) { [weak self] tokens in
                    guard let self,
                          self.highlightGeneration == generation,
                          let textView = self.textView,
                          textView.string == snapshot else {
                        return
                    }
                    self.apply(tokens: tokens, to: textView)
                }
            }

            pendingHighlightWorkItem = workItem

            if delay <= 0 {
                DispatchQueue.main.async(execute: workItem)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }
}

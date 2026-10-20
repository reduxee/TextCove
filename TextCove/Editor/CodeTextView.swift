import AppKit

final class CodeTextView: NSTextView {
    var onFileDrop: (([URL]) -> Bool)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onFileDrop != nil, !fileURLs(from: sender).isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if onFileDrop != nil, !fileURLs(from: sender).isEmpty {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if onFileDrop != nil, !fileURLs(from: sender).isEmpty {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        if !urls.isEmpty, let onFileDrop {
            return onFileDrop(urls)
        }
        return super.performDragOperation(sender)
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        )
        return objects?.compactMap { object in
            guard let url = object as? NSURL else { return nil }
            return url as URL
        } ?? []
    }
}

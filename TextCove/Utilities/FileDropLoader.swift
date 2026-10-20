import AppKit
import UniformTypeIdentifiers

enum FileDropLoader {
    static func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) -> Bool {
        let fileProviders = providers.enumerated().filter { _, provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urlsByIndex: [Int: URL] = [:]

        for (index, provider) in fileProviders {
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                defer { group.leave() }

                guard let item, let url = fileURL(from: item), url.isFileURL else {
                    return
                }

                lock.lock()
                urlsByIndex[index] = url
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let urls = fileProviders.compactMap { index, _ in urlsByIndex[index] }
            completion(urls)
        }

        return true
    }

    private static func fileURL(from item: NSSecureCoding) -> URL? {
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }
}

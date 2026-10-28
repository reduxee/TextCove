import Foundation

/// 超大文件的只读映射：不把文件读进内存，按字节范围按需读取。
/// 行号由「每 1024 行一个锚点」的稀疏索引定位，全文件索引在后台建立。
final class MappedTextFile {
    struct Anchor {
        let offset: Int
        let line: Int
    }

    enum OpenError: LocalizedError {
        case empty
        case cannotMap

        var errorDescription: String? {
            switch self {
            case .empty:
                return "文件是空的。"
            case .cannotMap:
                return "无法映射该文件。"
            }
        }
    }

    let url: URL
    let size: Int
    let encoding: String.Encoding

    private let base: UnsafeMutableRawPointer
    private var fileHandle: FileHandle?
    private let lock = NSLock()
    private var anchors: [Anchor] = [Anchor(offset: 0, line: 0)]

    private(set) var totalLines = 0
    private(set) var indexComplete = false
    /// 索引完成（主线程回调），参数为总行数
    var onIndexFinished: ((Int) -> Void)?

    private static let anchorStride = 1024

    init(url: URL) throws {
        self.url = url

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else { throw OpenError.empty }

        let handle = try FileHandle(forReadingFrom: url)
        let pointer = mmap(nil, fileSize, PROT_READ, MAP_PRIVATE, handle.fileDescriptor, 0)

        guard let pointer, pointer != UnsafeMutableRawPointer(bitPattern: -1) else {
            try? handle.close()
            throw OpenError.cannotMap
        }

        fileHandle = handle
        base = pointer
        size = fileSize
        encoding = Self.detectEncoding(base: pointer, size: fileSize)
    }

    deinit {
        munmap(base, size)
        try? fileHandle?.close()
    }

    // MARK: - 字节访问

    @inline(__always)
    func byte(at offset: Int) -> UInt8 {
        base.load(fromByteOffset: offset, as: UInt8.self)
    }

    /// 行尾（不含 \n）；没有换行时返回文件末尾
    func lineEnd(from start: Int) -> Int {
        guard start < size else { return size }
        if let found = memchr(base.advanced(by: start), 10, size - start) {
            return Int(bitPattern: found) - Int(bitPattern: base)
        }
        return size
    }

    func previousLineStart(before start: Int) -> Int? {
        guard start > 0 else { return nil }
        var index = start - 1
        if byte(at: index) == 10 {
            guard index > 0 else { return 0 }
            index -= 1
        }
        while index > 0 {
            if byte(at: index) == 10 { return index + 1 }
            index -= 1
        }
        return 0
    }

    /// 读取一行文本（去掉行尾 \r），超过 maxBytes 时截断并回退到 UTF-8 字符边界
    func text(from start: Int, to end: Int, maxBytes: Int) -> (text: String, truncated: Bool) {
        var upper = min(end, size)
        var truncated = false

        if upper > start, byte(at: upper - 1) == 13 {
            upper -= 1
        }

        if upper - start > maxBytes {
            upper = start + maxBytes
            var back = 0
            while upper > start, back < 3, upper < size, byte(at: upper) & 0xC0 == 0x80 {
                upper -= 1
                back += 1
            }
            truncated = true
        }

        let count = upper - start
        guard count > 0 else { return ("", truncated) }

        if encoding == .utf8 {
            let buffer = UnsafeRawBufferPointer(start: base.advanced(by: start), count: count)
            return (String(decoding: buffer, as: UTF8.self), truncated)
        }

        let data = Data(bytesNoCopy: base.advanced(by: start), count: count, deallocator: .none)
        return (String(data: data, encoding: encoding) ?? "", truncated)
    }

    // MARK: - 行号定位

    /// 给定字节偏移，返回所在行号与该行起始偏移
    func lineNumber(at offset: Int) -> (line: Int, start: Int) {
        lock.lock()
        let snapshot = anchors
        lock.unlock()

        var low = 0
        var high = snapshot.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if snapshot[mid].offset <= offset {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        var line = snapshot[best].line
        var start = snapshot[best].offset
        let target = min(offset, size)

        while start < target {
            let end = lineEnd(from: start)
            if end >= target { break }
            guard end < size else { break }
            start = end + 1
            line += 1
        }

        return (line, start)
    }

    // MARK: - 索引

    func buildIndexInBackground() {
        guard !indexComplete else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let bufferSize = 1024 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            var anchors: [Anchor] = [Anchor(offset: 0, line: 0)]
            var line = 0
            var offset = 0
            var lastYield = 0

            // 用 pread 逐块扫描：不建立额外映射，进程 RSS 不会随文件大小增长
            while offset < self.size {
                let want = min(bufferSize, self.size - offset)
                let read = buffer.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    return pread(self.fileHandle?.fileDescriptor ?? -1, base, want, off_t(offset))
                }
                guard read > 0 else { break }

                var scanned = 0
                while scanned < read {
                    let found = buffer.withUnsafeBytes { raw -> Int in
                        guard let base = raw.baseAddress?.advanced(by: scanned) else { return -1 }
                        guard let hit = memchr(base, 10, read - scanned) else { return -1 }
                        return Int(bitPattern: hit) - Int(bitPattern: base)
                    }
                    guard found >= 0 else { break }

                    let absolute = offset + scanned + found
                    line += 1
                    let next = absolute + 1
                    if line % Self.anchorStride == 0, next <= self.size {
                        anchors.append(Anchor(offset: next, line: line))
                    }
                    scanned += found + 1
                }

                offset += read
                if offset - lastYield >= 128 * 1024 * 1024 {
                    lastYield = offset
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }

            let trailing = self.size > 0 && self.byte(at: self.size - 1) != 10
            let total = line + (trailing ? 1 : 0)

            // 索引期间可能因零星绘制触碰了大量映射页，这里统一交还给系统
            madvise(self.base, self.size, MADV_DONTNEED)

            DispatchQueue.main.async {
                self.lock.lock()
                self.anchors = anchors
                self.lock.unlock()
                self.totalLines = total
                self.indexComplete = true
                self.onIndexFinished?(total)
            }
        }
    }

    // MARK: - 编码

    private static func detectEncoding(base: UnsafeMutableRawPointer, size: Int) -> String.Encoding {
        let sampleLength = min(size, 32 * 1024)
        guard sampleLength > 0 else { return .utf8 }

        // 采样末尾可能截断多字节字符，去掉最后 4 个字节再严格校验
        let trimmed = max(0, sampleLength - 4)
        let data = Data(bytesNoCopy: base, count: trimmed, deallocator: .none)
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }

        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
        )
        if let text = String(data: data, encoding: gbk),
           text.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            return gbk
        }

        if String(data: data, encoding: .windowsCP1252) != nil {
            return .windowsCP1252
        }
        return .isoLatin1
    }
}

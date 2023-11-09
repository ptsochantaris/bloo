import Foundation

protocol RowIdentifiable {
    var rowId: Int64 { get }
    static var byteOffsetOfRowIdentifier: Int { get }
}

struct MemoryMappedCollection<T: RowIdentifiable>: Collection {
    // derived from: https://github.com/akirark/MemoryMappedFileSwift

    enum MemoryMappedCollectionError: LocalizedError {
        case ioError(String)

        var errorDescription: String? {
            switch self {
            case let .ioError(text):
                "IO Error: \(text)"
            }
        }
    }

    struct MemoryMappedIterator: IteratorProtocol {
        private let buffer: UnsafeMutableRawPointer
        private let step: Int
        private let end: Int

        private var position: Int

        fileprivate init(buffer: UnsafeMutableRawPointer, stride: Int, counterSize: Int) {
            self.buffer = buffer
            position = counterSize
            step = stride
            end = counterSize + buffer.loadUnaligned(as: Int.self) * stride
        }

        mutating func next() -> T? {
            if position == end {
                return nil
            }
            defer {
                position += step
            }
            return buffer.loadUnaligned(fromByteOffset: position, as: T.self)
        }
    }

    private let step = MemoryLayout<T>.stride
    private let counterSize = MemoryLayout<Int>.stride

    var count: Int {
        get {
            buffer.loadUnaligned(as: Int.self)
        }
        set {
            buffer.storeBytes(of: newValue, as: Int.self)
        }
    }

    let startIndex = 0
    var endIndex: Int { count }

    private var capacity = 0
    private let fileDescriptor: Int32
    private var buffer: UnsafeMutableRawPointer!
    private var mappedSize = 0

    func index(after i: Int) -> Int { i + 1 }

    private func offset(for index: Int) -> Int {
        counterSize + step * index
    }

    init(at path: String, minimumCapacity: Int) throws {
        fileDescriptor = open(path, O_CREAT | O_RDWR, S_IREAD | S_IWRITE)
        if fileDescriptor == 0 {
            throw MemoryMappedCollectionError.ioError("Could not create or open file at \(path)")
        }
        try start(minimumCapacity: minimumCapacity)
    }

    mutating func insert(_ item: T) throws {
        try insert(contentsOf: [item])
    }

    private func index(for rowId: Int64) -> Int? { // TODO: optimise
        let start = counterSize + T.byteOffsetOfRowIdentifier
        let end = start + count * step
        var index = 0
        for i in stride(from: start, to: end, by: step) {
            if buffer.loadUnaligned(fromByteOffset: i, as: Int64.self) == rowId {
                return index
            }
            index += 1
        }
        return nil
    }

    mutating func insert(contentsOf sequence: any Collection<T>) throws {
        var currentCount = count
        let newMaxCount = currentCount + sequence.count
        if newMaxCount >= capacity {
            stop()
            try start(minimumCapacity: newMaxCount + 100_000)
        }

        let originalCount = currentCount
        for item in sequence {
            if let existingIndex = index(for: item.rowId) {
                buffer.storeBytes(of: item, toByteOffset: offset(for: existingIndex), as: T.self)
            } else {
                buffer.storeBytes(of: item, toByteOffset: offset(for: currentCount), as: T.self)
                currentCount += 1
            }
        }
        if originalCount != currentCount {
            count = currentCount
        }
    }

    mutating func deleteAll(where condition: (T) -> Bool) {
        var pos = count - 1
        while pos >= 0 {
            if condition(self[pos]) {
                delete(at: pos)
            }
            pos -= 1
        }
    }

    func makeIterator() -> MemoryMappedIterator {
        MemoryMappedIterator(buffer: buffer, stride: step, counterSize: counterSize)
    }

    mutating func delete(at index: Int) {
        if index >= count {
            return
        }

        let highestIndex = count - 1
        if index == highestIndex {
            count -= 1
            return
        }

        let itemOffset = offset(for: index)
        let highestItemOffset = offset(for: highestIndex)
        memcpy(buffer.advanced(by: itemOffset), buffer.advanced(by: highestItemOffset), step)
        count -= 1
    }

    subscript(position: Int) -> T {
        buffer.loadUnaligned(fromByteOffset: offset(for: position), as: T.self)
    }

    private mutating func start(minimumCapacity: Int) throws {
        if buffer != nil {
            return
        }

        var statInfo = stat()
        if fstat(fileDescriptor, &statInfo) != 0 {
            throw MemoryMappedCollectionError.ioError("Cannot access backing file on disk")
        }

        let minimumSize = offset(for: minimumCapacity)
        let pageSize = Int(getpagesize())
        let targetSize = ((minimumSize + pageSize - 1) / pageSize) * pageSize
        let existingSize = Int(statInfo.st_size)

        if targetSize > existingSize {
            if ftruncate(fileDescriptor, off_t(targetSize)) != 0 {
                throw MemoryMappedCollectionError.ioError("Cannot resize backing file on disk")
            }
            mappedSize = targetSize
        } else {
            mappedSize = existingSize
        }

        capacity = (mappedSize - counterSize) / step
        buffer = mmap(UnsafeMutableRawPointer(mutating: nil), mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)

        Log.storage(.info).log("Memory mapped index size: \(Double(mappedSize) / 1_000_000_000) Gb")
    }

    private mutating func stop() {
        guard let buf = buffer else {
            return
        }
        msync(buf, mappedSize, 0)
        munmap(buf, mappedSize)
        buffer = nil
        mappedSize = 0
    }

    mutating func shutdown() {
        stop()
        close(fileDescriptor)
    }
}

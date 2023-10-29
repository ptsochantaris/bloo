import Foundation

struct MemoryMappedCollection<T>: Collection {
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

    final class MemoryMappedIterator: IteratorProtocol {
        private var position = 0
        private let buffer: UnsafeMutableRawPointer
        private let step = MemoryLayout<T>.stride
        private let counterSize = MemoryLayout<Int>.stride

        fileprivate init(buffer: UnsafeMutableRawPointer) {
            self.buffer = buffer
        }

        func next() -> T? {
            if position == buffer.load(as: Int.self) {
                return nil
            }
            defer {
                position += 1
            }
            return buffer.load(fromByteOffset: counterSize + step * position, as: T.self)
        }
    }

    private let step = MemoryLayout<T>.stride
    private let counterSize = MemoryLayout<Int>.stride

    var count: Int {
        get {
            buffer.load(as: Int.self)
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

    mutating func append(_ item: T) throws {
        let originalCount = count
        let newCount = originalCount + 1
        if newCount == capacity {
            stop()
            try start(minimumCapacity: newCount + 100_000)
        }
        buffer.storeBytes(of: item, toByteOffset: offset(for: originalCount), as: T.self)
        count = newCount
    }

    mutating func append(contentsOf sequence: any Collection<T>) throws {
        var originalCount = count
        let newCount = originalCount + sequence.count
        if newCount >= capacity {
            stop()
            try start(minimumCapacity: newCount + 100_000)
        }
        for item in sequence {
            buffer.storeBytes(of: item, toByteOffset: offset(for: originalCount), as: T.self)
            originalCount += 1
        }
        count = newCount
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
        MemoryMappedIterator(buffer: buffer)
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
        buffer.load(fromByteOffset: offset(for: position), as: T.self)
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

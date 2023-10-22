import Foundation

final class MemoryMappedCollection<T>: Collection {
    // derived from: https://github.com/akirark/MemoryMappedFileSwift

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

    init(at path: String, minimumCapacity: Int) {
        fileDescriptor = open(path, O_CREAT | O_RDWR, S_IREAD | S_IWRITE)
        start(minimumCapacity: minimumCapacity)
    }

    func append(_ item: T) {
        let originalCount = count
        let newCount = originalCount + 1
        if newCount == capacity {
            stop()
            start(minimumCapacity: newCount + 1000)
        }
        buffer.storeBytes(of: item, toByteOffset: offset(for: originalCount), as: T.self)
        count = newCount
    }

    func append(contentsOf sequence: any Collection<T>) {
        var originalCount = count
        let newCount = originalCount + sequence.count
        if newCount >= capacity {
            stop()
            start(minimumCapacity: newCount + 1000)
        }
        for item in sequence {
            originalCount += 1
            buffer.storeBytes(of: item, toByteOffset: offset(for: originalCount), as: T.self)
        }
        count = newCount
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

    func makeIterator() -> MemoryMappedIterator {
        MemoryMappedIterator(buffer: buffer)
    }

    subscript(position: Int) -> T {
        buffer.load(fromByteOffset: offset(for: position), as: T.self)
    }

    private func start(minimumCapacity: Int) {
        if buffer != nil {
            return
        }

        if fileDescriptor == 0 {
            abort()
        }

        var statInfo = stat()
        if fstat(fileDescriptor, &statInfo) != 0 {
            abort()
        }

        let minimumSize = offset(for: minimumCapacity)
        let pageSize = Int(getpagesize())
        let targetSize = ((minimumSize + pageSize - 1) / pageSize) * pageSize
        let existingSize = Int(statInfo.st_size)

        if targetSize > existingSize {
            if ftruncate(fileDescriptor, off_t(targetSize)) != 0 {
                abort()
            }
            mappedSize = targetSize
        } else {
            mappedSize = existingSize
        }

        capacity = (mappedSize - counterSize) / step
        buffer = mmap(UnsafeMutableRawPointer(mutating: nil), mappedSize, PROT_READ | PROT_WRITE, MAP_SHARED, fileDescriptor, 0)
    }

    func stop() {
        guard let buf = buffer else {
            return
        }
        msync(buf, mappedSize, 0)
        munmap(buf, mappedSize)
        buffer = nil
        mappedSize = 0
    }

    func sync() {
        if let buffer {
            msync(buffer, mappedSize, 0)
        }
    }

    deinit {
        stop()
        if fileDescriptor != 0 {
            close(fileDescriptor)
        }
    }
}

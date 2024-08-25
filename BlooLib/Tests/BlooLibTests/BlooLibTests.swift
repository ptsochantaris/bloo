@testable import BlooLib
import Foundation
import Testing

struct TestType: RowIdentifiable, Equatable {
    let rowId: Int64

    let data = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rowId == rhs.rowId
    }
}

@Test func embedding() async throws {
    let test1 = try #require(await Embedding.vector(for: "This is a test"))
    let t1 = try #require(Vector(coordVector: test1, rowId: 3))

    let embedding1 = try #require(await Embedding.vector(for: "This is a test document"))
    let v1 = Vector(coordVector: embedding1, rowId: 0)
    let d1 = try #require(Embedding.distance(between: v1, and: t1))

    let test2 = try #require(await Embedding.vector(for: "This is a test document"))
    let t2 = try #require(Vector(coordVector: test2, rowId: 4))
    let dI = try #require(Embedding.distance(between: v1, and: t2))
    #expect(d1 > dI)

    let embedding2 = try #require(await Embedding.vector(for: "This is a book"))
    let v2 = Vector(coordVector: embedding2, rowId: 1)
    let d2 = try #require(Embedding.distance(between: v2, and: t1))
    #expect(d2 > d1)

    let embedding3 = try #require(await Embedding.vector(for: "This is a dog"))
    let v3 = Vector(coordVector: embedding3, rowId: 2)
    let d3 = try #require(Embedding.distance(between: v3, and: t1))
    #expect(d3 > d2)

    let embedding4 = try #require(await Embedding.vector(for: "Wuuuuuut"))
    let v4 = Vector(coordVector: embedding4, rowId: 3)
    let d4 = try #require(Embedding.distance(between: v4, and: t1))
    #expect(d4 > d3)
}

@Test func mappedColletion() async throws {
    let embeddingPath = FileManager.default.temporaryDirectory.appending(path: "test.embeddings", directoryHint: .notDirectory).path

    if FileManager.default.fileExists(atPath: embeddingPath) {
        _ = try? FileManager.default.removeItem(atPath: embeddingPath)
    }

    let collection = try MemoryMappedCollection<TestType>(at: embeddingPath, minimumCapacity: 10, validateOrder: false)

    for i in 0 ..< 100 {
        let item = TestType(rowId: Int64(i))
        try! collection.insert(item)
    }

    #expect(collection.count == 100)
    #expect(collection.first?.rowId == 0)
    #expect(collection.last?.rowId == 99)
    #expect(collection.first(where: { $0.rowId == 50 })?.rowId == 50)
    #expect(collection.firstIndex(of: TestType(rowId: 50)) == 50)

    for _ in 0 ..< 25 {
        collection.delete(at: 0)
    }
    #expect(collection.count == 75)
    #expect(collection.first?.rowId == 25)
    #expect(collection.last?.rowId == 99)

    collection.delete(at: 74)
    #expect(collection.count == 74)
    #expect(collection.first?.rowId == 25)
    #expect(collection.last?.rowId == 98)
    collection.delete(at: 0)
    #expect(collection.first?.rowId == 26)
    #expect(collection.last?.rowId == 98)

    try! collection.insert(TestType(rowId: 10))
    try! collection.insert(TestType(rowId: 11))
    try! collection.insert(TestType(rowId: 97))
    #expect(collection.first?.rowId == 10)
    #expect(collection.last?.rowId == 98)
    try! collection.insert(TestType(rowId: 97))
    #expect(collection.last?.rowId == 98)
    try! collection.insert(TestType(rowId: 99))
    #expect(collection.last?.rowId == 99)

    #expect(collection.first(where: { $0.rowId == 3 }) == nil)
    #expect(collection.first(where: { $0.rowId == 11 }) != nil)

    #expect(collection.count == 76)
    collection.deleteEntries(with: [3, 11, 97])
    #expect(collection.count == 74)

    #expect(collection.first(where: { $0.rowId == 97 }) == nil)

    let ids = collection.map(\.rowId)
    #expect(ids[0 ..< 10] == [10, 26, 27, 28, 29, 30, 31, 32, 33, 34])
}

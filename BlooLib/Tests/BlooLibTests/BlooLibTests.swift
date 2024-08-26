@testable import BlooLib
import Foundation
import Testing
import SwiftSoup
import Accelerate

struct TestType: RowIdentifiable, Equatable {
    let rowId: Int64

    let data = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rowId == rhs.rowId
    }
}

private func calculateDistance(of phrase: String, to vector: Vector) async throws -> Float {
    let e = try #require(await Embedding.vector(for: phrase))
    let v = Vector(coordVector: e.map { Float($0) }, rowId: 0)
    return try #require(Embedding.distance(between: v, and: vector))
}

private func textBlocks(from file: String) -> [String] {
    let htmlPath = Bundle.module.url(forResource: file, withExtension: "html", subdirectory: "Resources")!
    let data = try! Data(contentsOf: htmlPath)
    let htmlString = String(decoding: data, as: UTF8.self)
    let souped = try! SwiftSoup.Parser.parse(htmlString, "")
    #expect(souped.body() != nil)

    var textBlocks = [String]()
    for child in try! souped.body()!.getAllElements() {
        if let text = try? child.text(),
           text.count > 10,
           child.tag().getName() == "div" {
            textBlocks.append(text)
        }
    }

    return textBlocks
}

@Test func htmlFromStackOverFlow() async throws {
    let textBlocks = textBlocks(from: "stack-overflow-sample")
    let documentVector = await Embedding.vector(for: textBlocks)!
    let dv = Vector(coordVector: documentVector.map { Float($0) }, rowId: 0)

    let d0 = try await calculateDistance(of: "How to embed resources in swift package manager", to: dv)
    let d1 = try await calculateDistance(of: "How to make apps", to: dv)
    #expect(d0 < d1)

    let d2 = try await calculateDistance(of: "How to code in Swift", to: dv)
    #expect(d1 < d2)

    let d3 = try await calculateDistance(of: "Swift is fun", to: dv)
    #expect(d2 < d3)

    let d4 = try await calculateDistance(of: "I'm a little teapot", to: dv)
    #expect(d3 < d4)

    let d5 = try await calculateDistance(of: "Swimming is fun", to: dv)
    #expect(d4 < d5)

    let d6 = try await calculateDistance(of: "The quick brown fox jumps over the lazy dog", to: dv)
    #expect(d5 < d6)
}

@Test func htmlFromBruland() async throws {
    let textBlocks = textBlocks(from: "bruland-sample")
    let documentVector = await Embedding.vector(for: textBlocks)!
    let dv = Vector(coordVector: documentVector.map { Float($0) }, rowId: 0)

    let d0 = try await calculateDistance(of: "Rainy evening", to: dv)
    let d1 = try await calculateDistance(of: "Refrigeration", to: dv)
    #expect(d0 < d1)

    let d2 = try await calculateDistance(of: "Timelines", to: dv)
    #expect(d1 < d2)

    let d3 = try await calculateDistance(of: "Beer", to: dv)
    #expect(d2 < d3)

    let d4 = try await calculateDistance(of: "Government", to: dv)
    #expect(d3 < d4)

    let d5 = try await calculateDistance(of: "Racist drunk guy", to: dv)
    #expect(d4 < d5)

    let d6 = try await calculateDistance(of: "Swimming is fun", to: dv)
    #expect(d5 < d6)
}

@Test func embedding() async throws {
    let test1 = try #require(await Embedding.vector(for: "This is a test"))
    let t1 = try #require(Vector(coordVector: test1.map { Float($0) }, rowId: 0))

    let d0 = try await calculateDistance(of: "This is a test", to: t1)

    let d1 = try await calculateDistance(of: "This is a test document", to: t1)
    #expect(d1 > d0)

    let d2 = try await calculateDistance(of: "This is a book", to: t1)
    #expect(d2 > d1)

    let d3 = try await calculateDistance(of: "This is a dog", to: t1)
    #expect(d3 > d2)

    let d4 = try await calculateDistance(of: "Wuuuuuut", to: t1)
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

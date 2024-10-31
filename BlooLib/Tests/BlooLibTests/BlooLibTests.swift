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
    let e = await Embedding.vector(for: .query, text: phrase)
    guard let e else {
        return Float.greatestFiniteMagnitude
    }
    let v = Vector(coordVector: e.map { Float($0) }, rowId: 0)
    return try #require(Embedding.distance(between: v, and: vector))
}

private func textBlock(from file: String) -> String {
    let htmlPath = Bundle.module.url(forResource: file, withExtension: "html", subdirectory: "Resources")!
    let data = try! Data(contentsOf: htmlPath)
    let htmlString = String(decoding: data, as: UTF8.self)
    let souped = try! SwiftSoup.Parser.parse(htmlString, "")
    #expect(souped.body() != nil)

    return try! souped.body()!.text(trimAndNormaliseWhitespace: true)
}

func sequenceVerify(_ phrases: [String], to vector: Vector) async throws {
    struct Distance: Equatable, Comparable, CustomStringConvertible {
        let text: String
        let distance: Float

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.distance < rhs.distance
        }

        var description: String {
            text
        }
    }
    var distances: [Distance] = []
    for phrase in phrases {
        let distance = try await calculateDistance(of: phrase, to: vector)
        distances.append(Distance(text: phrase, distance: distance))
    }
    #expect(distances.sorted() == distances)
}

@Test func htmlFromStackOverFlow() async throws {
    let textBlocks = textBlock(from: "stack-overflow-sample")
    let documentVector = await Embedding.vector(for: .passage, text: textBlocks)!
    let dv = Vector(coordVector: documentVector.map { Float($0) }, rowId: 0)

    try await sequenceVerify([
        "How to code in Swift",
        "How to make apps",
        "Xcode",
        "How to embed resources in swift package manager",
        "Wuuuuuut",
        "Package manager",
        "Swift",
        "I'm a little teapot",
        "Sandwitch",
        "iPad",
        "Swimming is great exercise",
        "Quick brown fox jumps over the lazy dog",
    ], to: dv)
}

@Test func htmlFromBruland() async throws {
    let textBlocks = textBlock(from: "bruland-sample")
    let documentVector = await Embedding.vector(for: .passage, text: textBlocks)!
    let dv = Vector(coordVector: documentVector.map { Float($0) }, rowId: 0)

    try await sequenceVerify([
        "Cold",
        "Racist drunk guy",
        "Government",
        "Beer",
        "Timelines",
        "Space shuttle",
        "Και ενα στα Ελληνικά",
    ], to: dv)
}

@Test func embedding() async throws {
    let test1 = try #require(await Embedding.vector(for: .passage, text: "This is a test"))
    let t1 = try #require(Vector(coordVector: test1.map { Float($0) }, rowId: 0))

    let d0 = try await calculateDistance(of: "This is a test", to: t1)

    let d1 = try await calculateDistance(of: "This is a test document", to: t1)
    #expect(d1 > d0)

    let d2 = try await calculateDistance(of: "This is a book", to: t1)
    #expect(d2 > d1)

    let d3 = try await calculateDistance(of: "This is a dog", to: t1)
    #expect(d3 > d2)

    let d4 = try await calculateDistance(of: "ZX Spectrum emulator", to: t1)
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

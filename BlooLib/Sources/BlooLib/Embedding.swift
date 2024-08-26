import Accelerate
import Foundation
import Lista
@preconcurrency import NaturalLanguage

private final actor Rental<T: Sendable> {
    private let items = Lista<T>()

    private var createBlock: () async throws -> T

    init(createBlock: @escaping () async throws -> T) {
        self.createBlock = createBlock
    }

    func reserve() async throws -> T {
        if let existing = items.pop() {
            return existing
        }
        return try await createBlock()
    }

    private func _release(item: T) {
        items.append(item)
    }

    nonisolated func release(item: T) {
        Task {
            await _release(item: item)
        }
    }
}

public enum Embedding {
    private static let vectorEngines = Rental<NLContextualEmbedding> { @Sendable in
        let newEngine = NLContextualEmbedding(language: .english)!
        if !newEngine.hasAvailableAssets {
            try await newEngine.requestAssets()
        }
        try newEngine.load()
        return newEngine
    }

    private static let detectors = Rental<NSDataDetector> { @Sendable in
        let types: NSTextCheckingResult.CheckingType = [.date]
        return try NSDataDetector(types: types.rawValue)
    }

    private static let charsetForTrimming = CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines)

    public static func generateDate(from text: String) async -> Date? {
        guard let engine = try? await detectors.reserve() else {
            return nil
        }
        defer {
            detectors.release(item: engine)
        }
        return engine.firstMatch(in: text, range: text.wholeNSRange)?.date
    }

    public static func vector(for text: String) async -> [Double]? {
        guard let engine = try? await vectorEngines.reserve() else {
            return nil
        }

        let coordResult = try? engine.embeddingResult(for: text, language: .english)
        vectorEngines.release(item: engine)

        guard let coordResult else {
            return nil
        }

        var vector = [Double](repeating: 0, count: 512)
        var addedCount = 0
        coordResult.enumerateTokenVectors(in: text.wholeRange) { vec, range in
            if !range.isEmpty {
                vector = vDSP.add(vector, vec)
                addedCount += 1
            }
            return true
        }
        if addedCount > 1 {
            vector = vDSP.divide(vector, Double(addedCount))
        }
        if addedCount > 0 {
            return vector
        }

        return nil
    }

    public static func vector(for textBlocks: [String]) async -> [Double]? {
        var count = 0
        var documentVector = [Double](repeating: 0, count: 512)
        var sentences = Set<String>()

        for text in textBlocks {
            text.enumerateSubstrings(in: text.wholeRange, options: .bySentences) { substring, _, _, _ in
                if let substring {
                    sentences.insert(substring)
                }
            }
        }

        for sentence in sentences {
            if let vector = await Embedding.vector(for: sentence) {
                documentVector = vDSP.add(documentVector, vector)
                count += 1
            }
        }

        return if count > 1 {
            vDSP.divide(documentVector, Double(count))
        } else if count > 0 {
            documentVector
        } else {
            nil
        }
    }

    public static func distance(between firstVector: Vector, and secondVector: Vector) -> Float {
        distance(between: firstVector.accelerateBuffer, firstMagnitude: firstVector.magnitude, and: secondVector.accelerateBuffer, secondMagnitude: secondVector.magnitude)
    }

    public static func distance(between firstEmbedding: [Float], firstMagnitude: Float, and secondEmbedding: [Float], secondMagnitude: Float) -> Float {
        //let cosineSimilarity = vDSP.dot(firstEmbedding, secondEmbedding) / (firstMagnitude * secondMagnitude)
        //return 1 - pow(cosineSimilarity, 2)
        vDSP.distanceSquared(firstEmbedding, secondEmbedding)
    }
}

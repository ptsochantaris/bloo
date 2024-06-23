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

enum Embedding {
    private static let vectorEngines = Rental<NLContextualEmbedding> { @Sendable in
        let newEngine = NLContextualEmbedding(language: .english)!
        if !newEngine.hasAvailableAssets {
            try await newEngine.requestAssets()
            try newEngine.load()
        }
        return newEngine
    }

    private static let detectors = Rental<NSDataDetector> { @Sendable in
        let types: NSTextCheckingResult.CheckingType = [.date]
        return try NSDataDetector(types: types.rawValue)
    }

    private static let charsetForTrimming = CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines)

    static func generateDate(from text: String) async -> Date? {
        guard let engine = try? await detectors.reserve() else {
            return nil
        }
        defer {
            detectors.release(item: engine)
        }
        return engine.firstMatch(in: text, range: text.wholeNSRange)?.date
    }

    static func vector(for text: String, rowId: Int64 = 0) async -> Vector? {
        guard let engine = try? await vectorEngines.reserve() else {
            return nil
        }
        defer {
            vectorEngines.release(item: engine)
        }

        if let coordResult = try? engine.embeddingResult(for: text, language: .english) {
            var vector = [Double](repeating: 0, count: 512)
            var added = false
            coordResult.enumerateTokenVectors(in: text.wholeRange) { vec, range in
                if !range.isEmpty {
                    vDSP.maximum(vector, vec, result: &vector)
                    added = true
                }
                return true
            }

            if added {
                return Vector(coordVector: vector.map { Float($0) }, rowId: rowId)
            }
        }

        return nil
    }
}

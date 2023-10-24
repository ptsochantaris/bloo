import Foundation
@preconcurrency import NaturalLanguage
import Accelerate

final actor SentenceEmbedding {
    static let shared = SentenceEmbedding()

    private var engines = [NLContextualEmbedding]()

    private func reserve() async throws -> NLContextualEmbedding {
        if let existing = engines.popLast() {
            return existing
        }
        let newEngine = NLContextualEmbedding(language: .english)!
        if !newEngine.hasAvailableAssets {
            try await newEngine.requestAssets()
            try newEngine.load()
        }
        return newEngine
    }

    private func _release(engine: NLContextualEmbedding) {
        engines.append(engine)
    }

    private nonisolated func release(engine: NLContextualEmbedding) {
        Task {
            await _release(engine: engine)
        }
    }

    nonisolated func vector(for searchTerm: String, rowId: Int64 = 0) async -> Vector? {
        guard let engine = try? await reserve() else {
            return nil
        }
        defer {
            release(engine: engine)
        }

        guard let coordResult = try? engine.embeddingResult(for: searchTerm, language: .english) else {
            return nil
        }

        var vector = [Double](repeating: 0, count: 512) // TODO cache these buffers?
        coordResult.enumerateTokenVectors(in: searchTerm.startIndex ..< searchTerm.endIndex) { vec, range in
            if !range.isEmpty {
                vDSP.add(vector, vec, result: &vector)
            }
            return true
        }
        return Vector(coordVector: vector, rowId: rowId, sentence: searchTerm)
    }

    nonisolated func vectors(for sentences: [String], at rowId: Int64) async -> [Vector] {
        guard let engine = try? await reserve() else {
            return []
        }
        defer {
            release(engine: engine)
        }

        var res = [Vector]()
        for rawSentence in sentences {
            let trimmed = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 2, trimmed.contains(" "), let vec = await vector(for: trimmed, rowId: rowId) {
                res.append(vec)
            }
        }
        return res
    }
}

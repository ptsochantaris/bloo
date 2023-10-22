import Foundation
@preconcurrency import NaturalLanguage

final actor SentenceEmbedding {
    static let shared = SentenceEmbedding()

    private var embeddings = [NLEmbedding]()

    private func reserve() -> NLEmbedding {
        if let existing = embeddings.popLast() {
            return existing
        }
        return NLEmbedding.sentenceEmbedding(for: .english)!
    }

    private func _release(embedding: NLEmbedding) {
        embeddings.append(embedding)
    }

    private nonisolated func release(embedding: NLEmbedding) {
        Task {
            await _release(embedding: embedding)
        }
    }

    nonisolated func vector(for sentence: String) async -> Vector? {
        let sentenceEmbedding = await reserve()
        defer {
            release(embedding: sentenceEmbedding)
        }

        guard let coords = sentenceEmbedding.vector(for: sentence) else {
            return nil
        }

        return Vector(coordVector: coords, rowId: 0, sentence: sentence)
    }

    nonisolated func vectors(for sentences: [String], at rowId: Int64) async -> [Vector] {
        let sentenceEmbedding = await reserve()
        defer {
            release(embedding: sentenceEmbedding)
        }

        return sentences.compactMap { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 2, trimmed.contains(" "), let coords = sentenceEmbedding.vector(for: sentence) {
                return Vector(coordVector: coords, rowId: rowId, sentence: sentence)
            }
            return nil
        }
    }
}

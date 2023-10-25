import Accelerate
import Foundation
@preconcurrency import NaturalLanguage

private final actor Rental<T: Sendable> {
    private var items: [T]

    private var createBlock: () async throws -> T

    init(createBlock: @escaping () async throws -> T) {
        items = [T]()
        self.createBlock = createBlock
    }

    func reserve() async throws -> T {
        if let existing = items.popLast() {
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

enum SentenceEmbedding {
    private static let vectorEngines = Rental<NLContextualEmbedding> {
        let newEngine = NLContextualEmbedding(language: .english)!
        if !newEngine.hasAvailableAssets {
            try await newEngine.requestAssets()
            try newEngine.load()
        }
        return newEngine
    }

    private static let tokenizers = Rental<NLTokenizer> {
        NLTokenizer(unit: .sentence)
    }

    private static let detectors = Rental<NSDataDetector> {
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

    static func vector(for searchTerm: String, rowId: Int64 = 0) async -> Vector? {
        guard let engine = try? await vectorEngines.reserve() else {
            return nil
        }
        defer {
            vectorEngines.release(item: engine)
        }

        guard let coordResult = try? engine.embeddingResult(for: searchTerm, language: .english) else {
            return nil
        }

        var vector = [Double](repeating: 0, count: 512) // TODO: cache these buffers?
        coordResult.enumerateTokenVectors(in: searchTerm.wholeRange) { vec, range in
            if !range.isEmpty {
                vDSP.add(vector, vec, result: &vector)
            }
            return true
        }
        return Vector(coordVector: vector, rowId: rowId, sentence: searchTerm)
    }

    static func vectors(for sentences: [String], at rowId: Int64) async -> [Vector] {
        guard let engine = try? await vectorEngines.reserve() else {
            return []
        }
        defer {
            vectorEngines.release(item: engine)
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

    static func sentences(for text: String) async -> [String] {
        guard let engine = try? await tokenizers.reserve(), let dateDetector = try? await detectors.reserve() else {
            return []
        }
        defer {
            tokenizers.release(item: engine)
            detectors.release(item: dateDetector)
        }
        engine.string = text
        var sentences = [String]()
        engine.enumerateTokens(in: text.wholeRange) { range, _ in
            let text = text[range].trimmingCharacters(in: Self.charsetForTrimming)
            if text.contains("   ") || text.contains("   ") { // not spaces
                return true
            }
            if let match = dateDetector.firstMatch(in: text, range: text.wholeNSRange), match.range.lowerBound == 0 {
                return true
            }
            sentences.append(text)
            return true
        }
        return sentences
    }
}

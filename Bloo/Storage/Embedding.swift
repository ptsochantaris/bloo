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

    private static let tokenizers = Rental<NLTokenizer> { @Sendable in
        NLTokenizer(unit: .sentence)
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

        guard let coordResult = try? engine.embeddingResult(for: text, language: .english) else {
            return nil
        }

        var vector = [Float](repeating: 0, count: 512) // TODO: cache these buffers?
        coordResult.enumerateTokenVectors(in: text.wholeRange) { vec, range in
            if !range.isEmpty {
                let fvec = vec.map { Float($0) }
                vDSP.add(vector, fvec, result: &vector)
            }
            return true
        }
        return Vector(coordVector: vector, rowId: rowId, text: text)
    }

    static func vectors(for sentences: [String], at rowId: Int64) async -> Lista<Vector> {
        guard let engine = try? await vectorEngines.reserve() else {
            return Lista()
        }
        defer {
            vectorEngines.release(item: engine)
        }

        let res = Lista<Vector>()
        for rawSentence in sentences {
            let trimmed = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 2, trimmed.contains(" "), let vec = await vector(for: trimmed, rowId: rowId) {
                res.append(vec)
            }
        }
        return res
    }

    static func sentences(for text: String, titled: String?) async -> [String] {
        guard let engine = try? await tokenizers.reserve(), let dateDetector = try? await detectors.reserve() else {
            return []
        }
        defer {
            tokenizers.release(item: engine)
            detectors.release(item: dateDetector)
        }
        let allText: String = if let titled, !text.contains(titled) {
            titled + ". " + text
        } else {
            text
        }
        let sentences = Lista<String>()
        engine.string = allText
        engine.enumerateTokens(in: allText.wholeRange) { range, _ in
            let text = allText[range].trimmingCharacters(in: Self.charsetForTrimming)
            if text.isEmpty || text.contains("   ") || text.contains("   ") { // not spaces
                return true
            }
            if text.split(separator: " ").count < 4 {
                return true
            }
            if let match = dateDetector.firstMatch(in: text, range: text.wholeNSRange), match.range.lowerBound == 0 {
                return true
            }
            sentences.append(text)
            return true
        }
        return Array(sentences.uniqued())
    }
}

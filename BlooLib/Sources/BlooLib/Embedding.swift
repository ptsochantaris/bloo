import Accelerate
import Foundation
import Lista
import Algorithms
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

    public enum VectorType: String {
        case passage, query
    }

    private struct EmbeddingRequest: Encodable {
        let input: [String]

        init(type: VectorType, text: [String]) {
            input = text.map {
                "\(type.rawValue): \($0)"
            }
        }
    }

    private struct EmbeddingResponseData: Decodable {
        let data: [EmbeddingResponse]
    }

    private struct EmbeddingResponse: Decodable {
        let embedding: [Double]
    }

    public static func vector(for type: VectorType, text: String) async -> [Double]? {
        var addedCount = 0
        var sentences = [String]()
        var vector = [Double](repeating: 0, count: 1024)
        text.enumerateSubstrings(in: text.wholeRange, options: .bySentences) { substring, _, _, _ in
            if let substring, substring.count > 4 {
                sentences.append(substring)
            }
        }

        if sentences.isEmpty {
            sentences = [text]
        }

        // ./bin/llama-server --hf-repo chris-code/multilingual-e5-large-Q8_0-GGUF --hf-file multilingual-e5-large-q8_0.gguf --embedding -c 512

        var request = URLRequest(url: URL(string: "http://127.0.0.1:8080/embedding")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var formattedResponse: String?
        var formattedBody: String?
        do {
            let body = try JSONEncoder().encode(EmbeddingRequest(type: type, text: sentences))
            formattedBody = String(data: body, encoding: .utf8)
            request.httpBody = body
            let (data, _) = try await URLSession.shared.data(for: request)
            formattedResponse = String(data: data, encoding: .utf8)
            let response = try JSONDecoder().decode(EmbeddingResponseData.self, from: data)
            for r in response.data {
                vector = vDSP.add(vector, r.embedding)
                addedCount += 1
            }
        } catch {
            print("Request error: \(error)\n\nRequest: \(formattedBody ?? "<none>")\n\nResponse: \(formattedResponse ?? "<none>")")
        }

        if addedCount > 1 {
            vector = vDSP.divide(vector, Double(addedCount))
        }
        if addedCount > 0 {
            return vector
        }

        return nil
    }

    public static func distance(between firstVector: Vector, and secondVector: Vector) -> Float {
        distance(between: firstVector.accelerateBuffer, firstMagnitude: firstVector.magnitude, and: secondVector.accelerateBuffer, secondMagnitude: secondVector.magnitude)
    }

    public static func distance(between firstEmbedding: [Float], firstMagnitude: Float, and secondEmbedding: [Float], secondMagnitude: Float) -> Float {

        /*
        let cosineSimilarity = vDSP.dot(firstEmbedding, secondEmbedding) / (firstMagnitude * secondMagnitude)
        let distance1 = 1 - cosineSimilarity
        return distance1
        */

        return vDSP.distanceSquared(firstEmbedding, secondEmbedding)
    }
}

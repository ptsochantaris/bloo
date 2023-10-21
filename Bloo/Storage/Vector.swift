import Accelerate
import Foundation

typealias VectorTuple = (
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,

    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double, Double, Double
)

struct Vector {
    private let coords: VectorTuple
    private let sumOfSquares: Double
    let rowId: Int64

    init(coords: [Double], rowId: Int64) {
        self.rowId = rowId
        sumOfSquares = sqrt(vDSP.sumOfSquares(coords))
        self.coords = coords.withUnsafeBytes { pointer in
            let t = UnsafeMutablePointer<VectorTuple>.allocate(capacity: 1)
            defer { t.deallocate() }
            memcpy(t, pointer.baseAddress!, 4096)
            return t.pointee
        }
    }

    func similarity(to other: Vector) -> Double {
        var dot: Double = 0
        withUnsafePointer(to: coords) { tuplePointer1 in
            tuplePointer1.withMemoryRebound(to: Double.self, capacity: 512) { doublePointer1 in
                withUnsafePointer(to: other.coords) { tuplePointer2 in
                    tuplePointer2.withMemoryRebound(to: Double.self, capacity: 512) { doublePointer2 in
                        vDSP_dotprD(doublePointer1, 1, doublePointer2, 1, &dot, 512)
                    }
                }
            }
        }
        return dot / (sumOfSquares * other.sumOfSquares) * 1000
    }
}

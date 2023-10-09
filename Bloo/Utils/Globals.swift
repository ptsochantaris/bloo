import Foundation

enum Blooper: Error {
    case malformedUrl
    case coreSpotlightNotEnabled
    case blockedUrl
}

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("storage.noindex", isDirectory: true)

func domainPath(for id: String) -> URL {
    documentsPath.appendingPathComponent(id, isDirectory: true)
}

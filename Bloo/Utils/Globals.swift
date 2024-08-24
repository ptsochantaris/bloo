import Foundation
import SwiftUI

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("storage.noindex", isDirectory: true)

func domainPath(for id: String) -> URL {
    documentsPath.appendingPathComponent(id, isDirectory: true)
}

struct WindowIdKey: EnvironmentKey {
    static let defaultValue = UUID()
}

extension EnvironmentValues {
    var windowId: UUID {
        get { self[WindowIdKey.self] }
        set { self[WindowIdKey.self] = newValue }
    }
}

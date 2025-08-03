import Foundation
import SwiftUI

enum Constants {
    static let wideCorner: CGFloat = 15
    static let narrowCorner: CGFloat = 10
    static let gridColumns = [GridItem(.adaptive(minimum: 320, maximum: 640))]
}

#if canImport(AppKit)

    extension Font {
        static let blooTitle = Font.title2
        static let blooFootnote = Font.footnote
        static let blooCaption = Font.caption
        static let blooCaption2 = Font.caption2
        static let blooBody = Font.body
    }

    extension Constants {
        static let hspacing: CGFloat = 17
        static let titleInset: CGFloat = 4
    }

#elseif canImport(UIKit)

    extension Font {
        static let blooTitle = Font.title3
        static let blooFootnote = Font.footnote
        static let blooCaption = Font.footnote
        static let blooCaption2 = Font.footnote
        static let blooBody = Font.body
    }

    extension Constants {
        static let hspacing: CGFloat = 12
        static let titleInset: CGFloat = 0
    }
#endif

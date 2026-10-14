import SwiftUI

/// Two hands: Ari writes in New York, Apple's serif; you write in SF Pro, as does everything else.
extension Font {
    static let ariBody = Font.system(.body, design: .serif)
    static let ariStrong = Font.system(.body, design: .serif).weight(.semibold).monospacedDigit()
    static let ariName = Font.system(.headline, design: .serif)
    static let ariNote = Font.system(.subheadline, design: .serif).italic()
    static let ariHeading = Font.system(.title3, design: .serif).weight(.semibold)
    static let code = Font.callout.monospaced()
}

/// The serif wants more air than SF Pro to stay comfortable over a long read.
enum Rhythm {
    static let ariLineSpacing: CGFloat = 5
    static let ariParagraphGap: CGFloat = 18
    static let listItemGap: CGFloat = 6
    static let messageGap: CGFloat = 16
}

import SwiftUI
import UIKit
import KiokitCore

enum AnkiTheme {
    // Based on the v2 light/dark tokens in the user's saved Claude page.
    static let brand = Color(hex: 0xD97757)
    static let tint = adaptive(light: 0xA64F33, dark: 0xE69B7E)
    static let background = adaptive(light: 0xF9F9F7, dark: 0x151515)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x20201F)
    static let sidebar = adaptive(light: 0xF3F3F0, dark: 0x111111)
    static let subtle = adaptive(light: 0xF0EFEC, dark: 0x292928)
    static let selection = adaptive(light: 0xE7E6E1, dark: 0x333331)
    static let ink = adaptive(light: 0x131313, dark: 0xF9F9F7)
    static let muted = adaptive(light: 0x7B7974, dark: 0xA8A69E)
    static let border = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.10)
    })
    static let blue = adaptive(light: 0x586D85, dark: 0x9CB4CF)
    static let olive = adaptive(light: 0x647059, dark: 0xA8B59A)
    static let ochre = adaptive(light: 0x937343, dark: 0xCCAC78)
    static let palette: [Color] = [tint, blue, ochre, adaptive(light: 0x83677F, dark: 0xC0A4B9), olive]

    static func editorial(_ size: CGFloat) -> Font { .custom("Georgia", size: size, relativeTo: .title) }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
    }

    static func deckColor(_ deck: Deck) -> Color { palette[((deck.colorIndex % palette.count) + palette.count) % palette.count] }
    static func ratingColor(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: adaptive(light: 0xA04E45, dark: 0xDF9388)
        case .hard: ochre
        case .good: olive
        case .easy: blue
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

private extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

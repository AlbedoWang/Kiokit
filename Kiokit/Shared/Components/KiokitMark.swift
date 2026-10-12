import SwiftUI

/// The app icon's original artwork, with a transparent background so the mark
/// blends into the surrounding interface in both light and dark appearances.
struct KiokitMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("AppMark")
            .resizable()
            .scaledToFit()
            .frame(width: size * 1.5, height: size * 1.5)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

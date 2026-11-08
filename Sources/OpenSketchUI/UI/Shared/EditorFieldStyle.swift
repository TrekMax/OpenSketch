import SwiftUI

/// Keep native text editing while giving light-mode fields Sketch-like soft surfaces.
struct EditorFieldStyle: ViewModifier {
    var roundedInDark = false
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        if colorScheme == .light {
            content
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(EditorPalette.lightControl, in: RoundedRectangle(cornerRadius: 6))
        } else if roundedInDark {
            content.textFieldStyle(.roundedBorder)
        } else {
            content
        }
    }
}

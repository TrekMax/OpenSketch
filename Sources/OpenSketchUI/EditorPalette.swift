import AppKit
import SwiftUI

/// Neutral surfaces based on Compositor's 0.14 chrome and 0.105 canvas surround.
/// These colors belong to the editor, never to the document or exported artwork.
enum EditorPalette {
    static let panel = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.14, green: 0.14, blue: 0.14, alpha: 1)
            : .windowBackgroundColor
    }
    static let canvas = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.105, green: 0.105, blue: 0.105, alpha: 1)
            : .windowBackgroundColor
    }

    static func selection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }
}

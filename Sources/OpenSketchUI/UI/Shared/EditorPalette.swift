import AppKit
import SwiftUI

/// Editor-owned dynamic surfaces used only by the workspace chrome.
/// These colors belong to the editor, never to the document or exported artwork.
enum EditorPalette {
    static let panel = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.14, green: 0.14, blue: 0.14, alpha: 1)
            : .white
    }
    static let canvas = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.105, green: 0.105, blue: 0.105, alpha: 1)
            : NSColor(srgbRed: 245/255, green: 245/255, blue: 245/255, alpha: 1)
    }
    static let accent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemPurple
            : NSColor(srgbRed: 94/255, green: 91/255, blue: 255/255, alpha: 1)
    }
    static let separator = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .separatorColor
            : NSColor(srgbRed: 232/255, green: 232/255, blue: 235/255, alpha: 1)
    }
    static let grid = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .separatorColor
            : NSColor(srgbRed: 220/255, green: 220/255, blue: 225/255, alpha: 1)
    }

    static let inspectorControl = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.20, green: 0.20, blue: 0.20, alpha: 1)
            : NSColor(srgbRed: 244/255, green: 244/255, blue: 246/255, alpha: 1)
    }

    static let lightControl = Color(.sRGB, red: 244/255, green: 244/255, blue: 246/255, opacity: 1)

    static func selection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.12) : Color(.sRGB, red: 239/255, green: 238/255, blue: 255/255, opacity: 1)
    }

    static func selectionForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .primary : Color(nsColor: accent)
    }

    static func layerSelection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? selection(scheme) : Color(nsColor: accent)
    }
}

struct EditorDivider: View {
    var body: some View { Divider().overlay(Color(nsColor: EditorPalette.separator)) }
}

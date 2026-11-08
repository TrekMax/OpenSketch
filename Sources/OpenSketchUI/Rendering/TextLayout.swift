import AppKit
import OpenSketchCore

@MainActor enum TextLayout {
    static func attributes(_ node: DesignNode) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch node.textAlignment { case .left: .left; case .center: .center; case .right: .right; case .justified: .justified }
        return [.font: NSFont(name: node.fontName, size: node.fontSize) ?? NSFont.systemFont(ofSize: node.fontSize), .foregroundColor: (node.style.fill ?? .black).nsColor, .paragraphStyle: paragraph]
    }
    static func layout(_ node: DesignNode) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(string: node.text, attributes: attributes(node))
        let manager = NSLayoutManager(); let container = NSTextContainer(size: node.frame.size)
        container.lineFragmentPadding = 0; storage.addLayoutManager(manager); manager.addTextContainer(container); manager.ensureLayout(for: container)
        return (storage, manager, container)
    }
    static func measure(_ node: DesignNode) -> CGSize { let (storage, manager, container) = layout(node); return withExtendedLifetime(storage) { manager.usedRect(for: container).size } }
    static func draw(_ node: DesignNode) { guard node.style.fill != nil else { return }; let (storage, manager, container) = layout(node); withExtendedLifetime(storage) { let range = manager.glyphRange(for: container); manager.drawBackground(forGlyphRange: range, at: .zero); manager.drawGlyphs(forGlyphRange: range, at: .zero) } }
}
extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    init(_ color: NSColor) { let c = color.usingColorSpace(.sRGB) ?? .black; self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent) }
}

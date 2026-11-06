import AppKit
import OpenSketchCore

enum EditorError: LocalizedError { case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): text } }
}
@MainActor enum Exporter {
    static func validate(_ bounds: CGRect) throws {
        _ = try pixelSize(bounds: bounds)
    }
    /// Shared by preview and PNG output. Performs no bitmap allocation or Int conversion.
    static func pixelSize(bounds: CGRect, scale: Double = 1) throws -> CGSize {
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              (-1e9...1e9).contains(bounds.origin.x), (-1e9...1e9).contains(bounds.origin.y),
              bounds.size.width.isFinite, bounds.size.height.isFinite,
              bounds.size.width > 0, bounds.size.height > 0,
              bounds.maxX.isFinite, bounds.maxY.isFinite,
              scale.isFinite, scale > 0 else { throw EditorError.invalid("导出区域或倍率无效。") }
        let width = ceil(bounds.width * scale), height = ceil(bounds.height * scale)
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 16384, height <= 16384, width * height <= 64_000_000 else {
            throw EditorError.invalid("导出尺寸过大：最大边长 16384，最多 6400 万像素。")
        }
        return CGSize(width: width, height: height)
    }
    static func filename(name: String, format: ExportFormat, scale: Double = 1) -> String {
        let separators = CharacterSet(charactersIn: "/\\:")
        let sanitized = String(String.UnicodeScalarView(name.unicodeScalars.map {
            $0.properties.generalCategory == .control || separators.contains($0) ? "-" : $0
        }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sanitized.isEmpty || sanitized == "." || sanitized == ".." ? "设计" : sanitized
        let scaleText = String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), scale)
        let suffix = format == .png && scale != 1 ? "@\(scaleText)x" : ""
        var base = ""
        for character in source {
            guard base.utf8.count + character.utf8.count + suffix.utf8.count <= 200 else { break }
            base.append(character)
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "设计" }
        return base + suffix + "." + format.rawValue
    }
    static func png(page: DesignPage, bounds: CGRect, scale: Double = 1) throws -> Data {
        let size = try pixelSize(bounds: bounds, scale: scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw EditorError.invalid("无法分配导出图像") }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; NSGraphicsContext.current = graphics
        let c = graphics.cgContext
        c.clear(CGRect(origin: .zero, size: size))
        c.translateBy(x: 0, y: size.height); c.scaleBy(x: scale, y: -scale); c.translateBy(x: -bounds.minX, y: -bounds.minY)
        c.clip(to: bounds)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        CanvasRenderer.draw(page: page, in: c)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw EditorError.invalid("PNG 编码失败") }; return data
    }
    static func pdf(page: DesignPage, bounds: CGRect) throws -> Data {
        try validate(bounds); let data = NSMutableData(); var box = CGRect(origin: .zero, size: bounds.size)
        guard let consumer = CGDataConsumer(data: data), let c = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw EditorError.invalid("PDF 创建失败") }
        c.beginPDFPage(nil); c.translateBy(x: 0, y: bounds.height); c.scaleBy(x: 1, y: -1); c.translateBy(x: -bounds.minX, y: -bounds.minY)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
        CanvasRenderer.draw(page: page, in: c); NSGraphicsContext.restoreGraphicsState(); c.endPDFPage(); c.closePDF(); return data as Data
    }
}

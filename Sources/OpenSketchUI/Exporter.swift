import AppKit
import OpenSketchCore

enum EditorError: LocalizedError { case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): text } }
}
@MainActor enum Exporter {
    static func validate(_ bounds: CGRect) throws {
        guard !bounds.isEmpty, !bounds.isInfinite, bounds.width.isFinite, bounds.height.isFinite, bounds.width <= 16384, bounds.height <= 16384, bounds.width * bounds.height <= 64_000_000 else { throw EditorError.invalid("导出尺寸过大：最大边长 16384，最多 6400 万像素。") }
    }
    static func png(page: DesignPage, bounds: CGRect) throws -> Data {
        try validate(bounds)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(bounds.width)), pixelsHigh: Int(ceil(bounds.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw EditorError.invalid("无法分配导出图像") }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }; NSGraphicsContext.current = graphics
        let c = graphics.cgContext; c.translateBy(x: 0, y: bounds.height); c.scaleBy(x: 1, y: -1); c.translateBy(x: -bounds.minX, y: -bounds.minY)
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

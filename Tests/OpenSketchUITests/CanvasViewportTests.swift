import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct CanvasViewportTests {
    @Test(arguments: [false, true], [CGFloat(1), 2])
    func pannedContentStaysInsideViewport(inlineText: Bool, zoom: CGFloat) throws {
        let node = DesignNode(kind: inlineText ? .text : .frame,
                              frame: CGRect(x: 0, y: 0, width: 800, height: 600), text: "Viewport")
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.grid = false
        session.zoom = zoom
        session.pan = CGPoint(x: -100, y: -100)
        session.selection = [node.id]
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let surround = ViewportSurround(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = surround
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 80, y: 60, width: 240, height: 180)
        surround.addSubview(canvas)
        if inlineText {
            canvas.beginText(node.id)
            try #require(canvas.editor).backgroundColor = .white
        }

        // Capture the parent, so drawing outside the canvas cannot be hidden by
        // the capture bounds. The black surround represents all four editor panels.
        for size in [CGSize(width: 240, height: 180), CGSize(width: 180, height: 120)] {
            canvas.setFrameSize(size)
            let bitmap = try #require(surround.bitmapImageRepForCachingDisplay(in: surround.bounds))
            surround.cacheDisplay(in: surround.bounds, to: bitmap)
            func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try #require(bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / 400),
                                            y: Int(y * CGFloat(bitmap.pixelsHigh) / 300))?.usingColorSpace(.sRGB))
            }
            #expect(try color(160, 120).greenComponent > 0.9) // Content still renders inside.
            for point in [CGPoint(x: 40, y: 120), CGPoint(x: 360, y: 120),
                          CGPoint(x: 160, y: 30), CGPoint(x: 160, y: 270)] {
                let outside = try color(point.x, point.y)
                #expect(outside.redComponent < 0.1 && outside.greenComponent < 0.1 && outside.blueComponent < 0.1,
                        "Outside pixel at \(point): \(outside); canvas frame \(canvas.frame)")
            }
        }
        canvas.finishText(commit: false)
        #expect(session.document.pages[0].nodes == [node])
        #expect(!session.isDirty)
    }
}

@MainActor private final class ViewportSurround: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
    }
}

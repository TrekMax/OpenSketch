import Testing
import AppKit
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct ExportTests {
    private let red = RGBAColor(red: 1, green: 0, blue: 0)
    private let blue = RGBAColor(red: 0, green: 0, blue: 1)

    @Test func scaledPNGHasRealPixelsAndPDFKeepsPointSize() throws {
        let bounds = CGRect(x: 10, y: 20, width: 20, height: 10)
        let page = DesignPage(nodes: [DesignNode(kind: .rectangle, frame: bounds, style: NodeStyle(fill: red))])
        let image = try #require(NSBitmapImageRep(data: Exporter.png(page: page, bounds: bounds, scale: 2)))
        #expect(image.pixelsWide == 40 && image.pixelsHigh == 20)
        try expectColor(image, x: 39, y: 19, red: 1, blue: 0)
        let data = try Exporter.pdf(page: page, bounds: bounds)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let pdf = try #require(CGPDFDocument(provider))
        #expect(try #require(pdf.page(at: 1)).getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 20, height: 10))
    }

    @Test(arguments: [(1.0, 21, 11), (2.0, 41, 21), (3.0, 61, 31)])
    func fractionalCropKeepsTopBottomAndEdgeCoverage(scale: Double, width: Int, height: Int) throws {
        let bounds = CGRect(x: 10.5, y: 20.25, width: 20.25, height: 10.25)
        let background = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 100), style: NodeStyle(fill: red))
        let top = DesignNode(kind: .rectangle, frame: CGRect(x: 10.5, y: 20.25, width: 20.25, height: 4), style: NodeStyle(fill: blue))
        let image = try #require(NSBitmapImageRep(data: Exporter.png(page: DesignPage(nodes: [background, top]), bounds: bounds, scale: scale)))
        #expect(image.pixelsWide == width && image.pixelsHigh == height)
        try expectColor(image, x: 1, y: 1, red: 0, blue: 1)
        try expectColor(image, x: 1, y: height - 2, red: 1, blue: 0)
        let right = try #require(image.colorAt(x: width - 1, y: height - 2))
        let bottom = try #require(image.colorAt(x: 1, y: height - 1))
        #expect(abs(right.alphaComponent - scale * 0.25) < 0.03)
        #expect(abs(bottom.alphaComponent - scale * 0.25) < 0.03)
    }

    @Test func selectedChildKeepsAncestorOpacityButDropsBackgroundSiblingsAndSize() throws {
        let child = DesignNode(name: "按钮", kind: .rectangle, frame: CGRect(x: 5, y: 7, width: 20, height: 10), style: NodeStyle(fill: RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5)))
        let sibling = DesignNode(kind: .rectangle, frame: child.frame, style: NodeStyle(fill: blue))
        let parent = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 200, width: 1000, height: 1000), style: NodeStyle(fill: blue, opacity: 0.5), children: [child, sibling])
        let page = DesignPage(nodes: [parent])
        let before = page
        let snapshot = try ExportSnapshot.make(page: page, selection: [child.id], scope: .selection)
        #expect(snapshot.bounds == CGRect(x: 105, y: 207, width: 20, height: 10))
        #expect(snapshot.name == "按钮")
        let image = try png(snapshot)
        try expectColor(image, x: 10, y: 5, red: 1, blue: 0, alpha: 0.25)
        #expect(page == before)
    }

    @Test func nestedRotationsAndClipProduceTightSelectedBoundsAndPixels() throws {
        // Outer 90° and inner -90° cancel, mapping child (x,y) to (80+x,20+y).
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 30, y: 10, width: 30, height: 20), style: NodeStyle(fill: red))
        let inner = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 40, height: 40), rotation: -90, clipsContent: true, style: NodeStyle(fill: blue, opacity: 0.5), children: [child])
        let outer = DesignNode(kind: .group, frame: CGRect(x: 20, y: 20, width: 100, height: 100), rotation: 90, children: [inner])
        let snapshot = try ExportSnapshot.make(page: DesignPage(nodes: [outer]), selection: [child.id], scope: .selection)
        #expect(abs(snapshot.bounds.minX - 110) < 0.001)
        #expect(abs(snapshot.bounds.minY - 30) < 0.001)
        #expect(abs(snapshot.bounds.width - 10) < 0.001)
        #expect(abs(snapshot.bounds.height - 20) < 0.001)
        try expectColor(png(snapshot), x: 5, y: 10, red: 1, blue: 0, alpha: 0.5)
    }

    @Test func rotatedClipRejectsAABBOnlyOverlap() {
        // A 45° square is a diamond; this child lies only in its bounding-box corner.
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: -20, y: 45, width: 10, height: 10), rotation: -45)
        let frame = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 45, clipsContent: true, children: [child])
        #expect(throws: (any Error).self) { try ExportSnapshot.make(page: DesignPage(nodes: [frame]), selection: [child.id], scope: .selection) }
    }

    @Test func groupExportUsesChildrenAndDeduplicatesParentChildSelection() throws {
        let a = DesignNode(kind: .rectangle, frame: CGRect(x: 20, y: 30, width: 20, height: 10), style: NodeStyle(fill: red))
        let b = DesignNode(kind: .rectangle, frame: CGRect(x: 60, y: 30, width: 10, height: 10), style: NodeStyle(fill: blue))
        let hidden = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), isVisible: false)
        let group = DesignNode(name: "组合", kind: .group, frame: CGRect(x: 100, y: 200, width: 1000, height: 1000), style: NodeStyle(opacity: 0.5), children: [a, b, hidden])
        let page = DesignPage(nodes: [group])
        let snapshot = try ExportSnapshot.make(page: page, selection: [group.id, a.id], scope: .selection)
        #expect(snapshot.bounds == CGRect(x: 120, y: 230, width: 50, height: 10))
        #expect(snapshot.page.nodes.first?.children == group.children)
        try expectColor(png(snapshot), x: 5, y: 5, red: 1, blue: 0, alpha: 0.5)
        let merged = try ExportSnapshot.make(page: page, selection: [a.id, b.id], scope: .selection)
        #expect(merged.bounds == snapshot.bounds)
        #expect(merged.name == "选中图层")
        let image = try png(merged)
        try expectColor(image, x: 45, y: 5, red: 0, blue: 1, alpha: 0.5)
        #expect(try #require(image.colorAt(x: 30, y: 5)).alphaComponent < 0.01)
    }

    @Test func singleArtboardNormalizesAndClipsExactOwnBounds() throws {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 15, y: 0, width: 20, height: 10), style: NodeStyle(fill: red))
        let artboard = DesignNode(name: "画板", kind: .frame, frame: CGRect(x: 200, y: 300, width: 20, height: 10), rotation: 45, children: [child])
        let parent = DesignNode(kind: .group, frame: CGRect(x: 100, y: 100, width: 100, height: 100), rotation: 90, children: [artboard])
        let page = DesignPage(nodes: [parent])
        let before = page
        let snapshot = try ExportSnapshot.make(page: page, selection: [artboard.id], scope: .selection)
        #expect(snapshot.bounds == CGRect(x: 0, y: 0, width: 20, height: 10))
        let image = try png(snapshot)
        #expect(image.pixelsWide == 20 && image.pixelsHigh == 10)
        try expectColor(image, x: 1, y: 5, red: 1, blue: 1)
        try expectColor(image, x: 19, y: 5, red: 1, blue: 0)
        #expect(snapshot.page.nodes.first?.children == [child])
        #expect(snapshot.page.nodes.first?.frame.origin == .zero)
        #expect(snapshot.page.nodes.first?.rotation == 0)
        #expect(snapshot.page.nodes.first?.clipsContent == true)
        #expect(page == before)
    }

    @Test func invalidAndInvisibleSelectionsThrowWhileLockedNodesExport() throws {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 20, y: 20, width: 10, height: 10), isLocked: true)
        let hidden = DesignNode(kind: .group, isVisible: false, children: [child])
        let clipped = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 10, height: 10), clipsContent: true, children: [child])
        let invalid: [(DesignPage, Set<UUID>)] = [(DesignPage(nodes: [child]), []), (DesignPage(nodes: [child]), [UUID()]), (DesignPage(nodes: [hidden]), [child.id]), (DesignPage(nodes: [clipped]), [child.id])]
        for (page, selection) in invalid {
            #expect(throws: (any Error).self) { try ExportSnapshot.make(page: page, selection: selection, scope: .selection) }
        }
        let artboard = DesignNode(kind: .frame)
        #expect(throws: (any Error).self) { try ExportSnapshot.make(page: DesignPage(nodes: [DesignNode(kind: .group, isVisible: false, children: [artboard])]), selection: [artboard.id], scope: .selection) }
        let snapshot = try ExportSnapshot.make(page: DesignPage(nodes: [child]), selection: [child.id], scope: .selection)
        #expect(try png(snapshot).pixelsWide == 10)
        let transparent = DesignNode(kind: .group, style: NodeStyle(opacity: 0), children: [child])
        #expect(throws: (any Error).self) { try ExportSnapshot.make(page: DesignPage(nodes: [transparent]), selection: [child.id], scope: .selection) }
    }

    @Test func pageScopeUsesExistingBoundsAndEmptyPageSize() throws {
        let page = DesignPage(name: "页面", size: CGSize(width: 321, height: 123))
        #expect(try ExportSnapshot.make(page: page, selection: [], scope: .page).bounds == CGRect(x: 0, y: 0, width: 321, height: 123))
        #expect(try ExportSnapshot.make(page: page, selection: [], scope: .page).name == "页面")
        let filled = DesignPage(nodes: [DesignNode(kind: .rectangle, frame: CGRect(x: 10.5, y: 20.5, width: 20, height: 10))])
        #expect(try ExportSnapshot.make(page: filled, selection: [], scope: .page).bounds == CGRect(x: 10, y: 20, width: 21, height: 11))
        #expect(ExportOptions().resolvedScope(selection: []) == .page)
        #expect(ExportOptions().resolvedScope(selection: [UUID()]) == .selection)
    }

    @Test func dimensionsValidateBeforeConversionOrAllocation() throws {
        #expect(try Exporter.pixelSize(bounds: CGRect(x: 0, y: 0, width: 32768, height: 2), scale: 0.5) == CGSize(width: 16384, height: 1))
        #expect(try Exporter.pixelSize(bounds: CGRect(x: -1e9, y: 1e9, width: 8000, height: 8000)) == CGSize(width: 8000, height: 8000))
        for bounds in [CGRect(x: 0, y: 0, width: 8000.01, height: 7999.99), CGRect(x: 0, y: 0, width: 16384.01, height: 1), CGRect(x: 0, y: 0, width: 0, height: 1), CGRect(x: 0, y: 0, width: -1, height: 1), CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1), CGRect(x: 1e10, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1)] {
            #expect(throws: (any Error).self) { try Exporter.pixelSize(bounds: bounds) }
        }
        for scale in [0, -1, Double.nan, .infinity, Double.greatestFiniteMagnitude] {
            #expect(throws: (any Error).self) { try Exporter.pixelSize(bounds: CGRect(x: 0, y: 0, width: 20, height: 10), scale: scale) }
        }
        #expect(throws: (any Error).self) { try Exporter.pdf(page: DesignPage(), bounds: CGRect(x: 0, y: 0, width: 32768, height: 2)) }
    }

    @Test func filenamesAreSingleSafeUnicodeComponentsWithinByteBudget() {
        #expect(Exporter.filename(name: "  a/b\\c:d\u{1}e  ", format: .png, scale: 2) == "a-b-c-d-e@2x.png")
        #expect(Exporter.filename(name: "   ", format: .png) == "设计.png")
        #expect(Exporter.filename(name: "图标 👩🏽‍💻", format: .pdf, scale: 3) == "图标 👩🏽‍💻.pdf")
        #expect(Exporter.filename(name: "图标", format: .png, scale: 3) == "图标@3x.png")
        let filename = Exporter.filename(name: String(repeating: "中文👩🏽‍💻", count: 100), format: .png, scale: 2)
        #expect(filename.hasSuffix("@2x.png"))
        #expect(filename.dropLast(4).utf8.count <= 200)
        #expect(!filename.contains("�"))
        let truncated = Exporter.filename(name: String(repeating: "a", count: 198) + "   ending", format: .pdf)
        #expect(!truncated.dropLast(4).hasSuffix(" "))
        #expect(Exporter.filename(name: "设计", format: .png, scale: .greatestFiniteMagnitude).dropLast(4).utf8.count <= 200)
    }

    private func png(_ snapshot: ExportSnapshot) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(data: Exporter.png(page: snapshot.page, bounds: snapshot.bounds)))
    }
    private func expectColor(_ image: NSBitmapImageRep, x: Int, y: Int, red: CGFloat, blue: CGFloat, alpha: CGFloat = 1) throws {
        let color = try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        #expect(abs(color.redComponent - red) < 0.03)
        #expect(abs(color.blueComponent - blue) < 0.03)
        #expect(abs(color.alphaComponent - alpha) < 0.03)
    }
}

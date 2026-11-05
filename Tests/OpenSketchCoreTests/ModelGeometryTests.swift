import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

@Test func blankDocumentHasOnePageAndKindSpecificStyles() {
    #expect(DesignDocument.blank().pages.count == 1)
    #expect(DesignNode(kind: .frame).style.fill == .white)
    #expect(DesignNode(kind: .text).style.fill == .black)
    #expect(DesignNode(kind: .group).style.fill == nil)
    #expect(DesignNode(kind: .rectangle).style.fill != nil)
}

@Test func recursiveMutationPreservesOrderAndIdentity() throws {
    let first = DesignNode(name: "第一", kind: .rectangle)
    let second = DesignNode(name: "第二", kind: .ellipse)
    let group = DesignNode(kind: .group, children: [first])
    let page = DesignPage(nodes: [group])
    var document = DesignDocument(pages: [page])
    try document.insertNode(second, into: page.id, parentID: group.id, at: 0)
    #expect(document.node(id: group.id)?.children.map(\.id) == [second.id, first.id])
    #expect(document.pageContaining(nodeID: first.id) == page.id)
    #expect(document.parentID(of: first.id) == group.id)
    #expect({ document.updateNode(id: first.id) { $0.name = "中文 🖊️" } }())
    #expect(document.node(id: first.id)?.name == "中文 🖊️")
    #expect({ document.removeNode(id: second.id) }() == second)
    #expect(document.node(id: group.id)?.children.map(\.id) == [first.id])
    try document.insertNode(second, into: page.id, at: 0)
    #expect(document.pages[0].nodes.map(\.id) == [second.id, group.id])
    #expect(document.parentID(of: second.id) == nil)
    #expect({ document.removeNode(id: UUID()) }() == nil)
    #expect({ !document.updateNode(id: UUID()) { $0.name = "无" } }())
}

@Test func insertionFailuresDoNotPartiallyMutateDocument() throws {
    let leaf = DesignNode(kind: .rectangle)
    let page = DesignPage(nodes: [leaf])
    var document = DesignDocument(pages: [page])
    let original = document
    #expect(throws: DocumentOperationError.invalidParent) {
        try document.insertNode(DesignNode(kind: .ellipse), into: page.id, parentID: leaf.id)
    }
    #expect(throws: DocumentOperationError.duplicateID) { try document.insertNode(leaf, into: page.id) }
    #expect(throws: DocumentOperationError.invalidIndex) {
        try document.insertNode(DesignNode(kind: .ellipse), into: page.id, at: 50)
    }
    #expect(throws: DocumentOperationError.pageNotFound) {
        try document.insertNode(DesignNode(kind: .ellipse), into: UUID())
    }
    #expect(throws: DocumentOperationError.parentNotFound) {
        try document.insertNode(DesignNode(kind: .ellipse), into: page.id, parentID: UUID())
    }
    #expect(document == original)
    let container = DesignNode(kind: .group, children: [DesignNode(kind: .group, children: [leaf])])
    let copy = container.cloned()
    #expect(copy.id != container.id)
    #expect(copy.children[0].id != container.children[0].id)
    #expect(copy.children[0].children[0].id != leaf.id)
    #expect(copy.children[0].children[0].frame == leaf.frame)
}

@Test func nestedRotationUsesHandDerivedWorldCoordinates() throws {
    // Parent: (100,50), 100×100, +90°. Child: (10,20), 20×10, +90°.
    // Child local (0,0) -> parent (25,15) -> world (185,75).
    // Child local (20,10) -> parent (15,35) -> world (165,65).
    let child = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 20, height: 10), rotation: 90)
    let parent = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 50, width: 100, height: 100),
                            rotation: 90, children: [child])
    let page = DesignPage(nodes: [parent])
    let transform = try #require(SceneGeometry.worldTransform(id: child.id, in: page))
    let origin = CGPoint.zero.applying(transform)
    let far = CGPoint(x: 20, y: 10).applying(transform)
    #expect(abs(origin.x - 185) < 0.000001)
    #expect(abs(origin.y - 75) < 0.000001)
    #expect(abs(far.x - 165) < 0.000001)
    #expect(abs(far.y - 65) < 0.000001)
    #expect(SceneGeometry.hitTest(CGPoint(x: 175, y: 70), in: page) == child.id)
    #expect(SceneGeometry.hitTest(CGPoint(x: 190, y: 70), in: page) == parent.id)
    #expect(SceneGeometry.worldTransform(id: UUID(), in: page) == nil)
}

@Test func clipRespectsRotatedFrameAndUnclippedChildOutsideBounds() {
    let child = DesignNode(kind: .rectangle, frame: CGRect(x: 80, y: 40, width: 50, height: 20))
    var frame = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 50, width: 100, height: 100),
                           rotation: 90, clipsContent: true, children: [child])
    // Parent local (110,50) -> world (150,160), outside frame; local (90,50) -> (150,140).
    #expect(SceneGeometry.hitTest(CGPoint(x: 150, y: 160), in: DesignPage(nodes: [frame])) == nil)
    #expect(SceneGeometry.hitTest(CGPoint(x: 150, y: 140), in: DesignPage(nodes: [frame])) == child.id)
    frame.clipsContent = false
    #expect(SceneGeometry.hitTest(CGPoint(x: 150, y: 160), in: DesignPage(nodes: [frame])) == child.id)
}

@Test(arguments: [true, false]) func hiddenOrLockedAncestorBlocksDescendant(hidden: Bool) {
    let underneath = DesignNode(kind: .rectangle)
    let child = DesignNode(kind: .rectangle)
    let parent = DesignNode(kind: .group, isVisible: !hidden, isLocked: !hidden, children: [child])
    #expect(SceneGeometry.hitTest(CGPoint(x: 20, y: 20), in: DesignPage(nodes: [underneath, parent])) == underneath.id)
}

@Test func zOrderVisitsDeepestTopmostEligibleNode() {
    let bottom = DesignNode(kind: .rectangle)
    let first = DesignNode(kind: .rectangle)
    let last = DesignNode(kind: .ellipse)
    let parent = DesignNode(kind: .group, children: [first, last])
    let page = DesignPage(nodes: [bottom, parent])
    #expect(SceneGeometry.traversal(in: page).map(\.id) == [bottom.id, parent.id, first.id, last.id])
    #expect(SceneGeometry.hitTest(CGPoint(x: 50, y: 50), in: page) == last.id)
    // Ellipse corner is outside its filled shape, revealing the sibling underneath.
    #expect(SceneGeometry.hitTest(CGPoint(x: 1, y: 1), in: page) == first.id)
}

@Test func vectorPathHitTestingUsesCommands() {
    let triangle = VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 100, y: 0)),
                                          .line(to: CGPoint(x: 0, y: 100)), .close])
    let node = DesignNode(kind: .path, path: triangle)
    let page = DesignPage(nodes: [node])
    #expect(SceneGeometry.hitTest(CGPoint(x: 20, y: 20), in: page) == node.id)
    #expect(SceneGeometry.hitTest(CGPoint(x: 90, y: 90), in: page) == nil)
    #expect(SceneGeometry.cgPath(for: triangle).boundingBox == CGRect(x: 0, y: 0, width: 100, height: 100))
}

@Test func roundedRectangleCornerAndPathStrokeMatchVisibleGeometry() {
    let rounded = DesignNode(kind: .rectangle, style: NodeStyle(fill: .black, cornerRadius: 30))
    #expect(SceneGeometry.hitTest(CGPoint(x: 1, y: 1), in: DesignPage(nodes: [rounded])) == nil)
    #expect(SceneGeometry.hitTest(CGPoint(x: 30, y: 1), in: DesignPage(nodes: [rounded])) == rounded.id)
    let line = DesignNode(kind: .path, style: NodeStyle(stroke: .black, strokeWidth: 10),
                          path: VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 100, y: 0))]))
    #expect(SceneGeometry.hitTest(CGPoint(x: 50, y: -2), in: DesignPage(nodes: [line])) == line.id)
    #expect(SceneGeometry.hitTest(CGPoint(x: 50, y: -6), in: DesignPage(nodes: [line])) == nil)
}

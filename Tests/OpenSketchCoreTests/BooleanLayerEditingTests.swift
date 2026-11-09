import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct BooleanLayerEditingTests {
    private func node(_ x: CGFloat, _ y: CGFloat) -> DesignNode {
        DesignNode(kind: .rectangle, frame: CGRect(x: x, y: y, width: 80, height: 80))
    }

    @Test func combinesSameParentRectanglesAndSelectsResult() throws {
        let first = node(0, 0), second = node(40, 40)
        let page = DesignPage(nodes: [first, second])
        let document = DesignDocument(pages: [page])
        let result = try BooleanLayerEditing.apply(.union, to: document, pageID: page.id,
                                                   selection: [first.id, second.id])
        #expect(result.document.pages[0].nodes.count == 1)
        let combined = try #require(result.document.node(id: result.selection.first!))
        #expect(combined.kind == .path)
    }

    @Test func rejectsOpenPathAndDifferentParents() {
        let open = DesignNode(kind: .path, path: VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 10, y: 0))]))
        let rect = node(20, 0)
        let page = DesignPage(nodes: [open, rect])
        #expect(throws: BooleanEditingError.openPath) {
            try BooleanLayerEditing.apply(.union, to: DesignDocument(pages: [page]), pageID: page.id,
                                          selection: [open.id, rect.id])
        }
        let parent = DesignNode(kind: .group, children: [node(0, 0)])
        let other = node(100, 0)
        let different = DesignPage(nodes: [parent, other])
        let child = parent.children[0]
        #expect(throws: LayerEditError.differentParents) {
            try BooleanLayerEditing.apply(.union, to: DesignDocument(pages: [different]), pageID: different.id,
                                          selection: [child.id, other.id])
        }
    }
}

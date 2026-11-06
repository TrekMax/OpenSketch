import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct LayerTreeEditingTests {
    @Test func aboveAndBelowUseDisplayOrderAfterRemovingSources() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse), c = DesignNode(kind: .text)
        let page = DesignPage(nodes: [a, b, c]), doc = DesignDocument(pages: [page])
        let above = try LayerTreeEditing.move(doc, pageID: page.id, selection: [a.id], to: .above(b.id))
        #expect(above.document.pages[0].nodes == [b, a, c])
        let below = try LayerTreeEditing.move(doc, pageID: page.id, selection: [c.id], to: .below(b.id))
        #expect(below.document.pages[0].nodes == [a, c, b])
        let unchanged = try LayerTreeEditing.move(doc, pageID: page.id, selection: [c.id], to: .above(b.id))
        #expect(unchanged.document == doc)
    }

    @Test func multipleRootsKeepPaintOrderAndNormalizeSelectedChildren() throws {
        let child = DesignNode(kind: .rectangle, isLocked: true)
        let group = DesignNode(kind: .group, children: [child])
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse), target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [group, a, b, target]), doc = DesignDocument(pages: [page])
        let moved = try LayerTreeEditing.move(doc, pageID: page.id, selection: [b.id, group.id, child.id], to: .inside(target.id))
        #expect(moved.document.node(id: target.id)?.children == [group, b])
        #expect(moved.selection == [group.id, b.id])
        #expect(moved.document.pages[0].nodes.map(\.id) == [a.id, target.id])
    }

    @Test func rotatedReparentingPreservesRootAndDescendantWorldPoints() throws {
        let leaf = DesignNode(kind: .ellipse, frame: CGRect(x: 3, y: 4, width: 10, height: 20), rotation: 12)
        let moving = DesignNode(kind: .group, frame: CGRect(x: 30, y: 10, width: 80, height: 60), rotation: 20, children: [leaf])
        let source = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 200, width: 300, height: 200), rotation: 45, children: [moving])
        let target = DesignNode(kind: .group, frame: CGRect(x: -200, y: 60, width: 180, height: 120), rotation: -30)
        let page = DesignPage(nodes: [source, target]), doc = DesignDocument(pages: [page])
        let result = try LayerTreeEditing.move(doc, pageID: page.id, selection: [moving.id], to: .inside(target.id)).document
        #expect(result.parentID(of: moving.id) == target.id)
        #expect(result.node(id: moving.id)?.children == moving.children)
        #expect(result.node(id: moving.id)?.frame.size == moving.frame.size)
        try sameWorldPoints([moving.id, leaf.id], before: page, after: result.pages[0])
        let outside = try LayerTreeEditing.move(result, pageID: page.id, selection: [moving.id], to: .pageEnd).document
        #expect(outside.pages[0].nodes.first?.id == moving.id && outside.parentID(of: moving.id) == nil)
        try sameWorldPoints([moving.id, leaf.id], before: page, after: outside.pages[0])
        #expect(try DocumentCodec.decode(DocumentCodec.encode(outside)) == outside)
    }

    @Test func sameParentReorderingNeverChangesGeometryAndFramesCanNest() throws {
        let a = DesignNode(kind: .frame, rotation: 390), b = DesignNode(kind: .rectangle)
        let parent = DesignNode(kind: .frame, rotation: 17, children: [a, b])
        let target = DesignNode(kind: .group)
        let page = DesignPage(nodes: [parent, target]), doc = DesignDocument(pages: [page])
        let reordered = try LayerTreeEditing.move(doc, pageID: page.id, selection: [a.id], to: .above(b.id)).document
        #expect(reordered.node(id: parent.id)?.children == [b, a])
        let nested = try LayerTreeEditing.move(doc, pageID: page.id, selection: [a.id], to: .inside(target.id)).document
        #expect(nested.parentID(of: a.id) == target.id)
        try sameWorldPoints([a.id], before: page, after: nested.pages[0])
    }

    @Test func crossParentMultipleSourcesInsertRelativeToSurvivingAnchor() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse), anchor = DesignNode(kind: .text)
        let source = DesignNode(kind: .group, children: [a])
        let target = DesignNode(kind: .frame, children: [b, anchor])
        let page = DesignPage(nodes: [source, target]), doc = DesignDocument(pages: [page])
        let moved = try LayerTreeEditing.move(doc, pageID: page.id, selection: [b.id, a.id], to: .above(anchor.id)).document
        #expect(moved.node(id: target.id)?.children.map(\.id) == [anchor.id, a.id, b.id])
        #expect(moved.node(id: source.id)?.children.isEmpty == true)
    }

    @Test func cyclesMissingCrossPageAndLeafParentsRejectAtomically() throws {
        let child = DesignNode(kind: .group), leaf = DesignNode(kind: .rectangle), foreign = DesignNode(kind: .group)
        let parent = DesignNode(kind: .group, children: [child])
        let page = DesignPage(nodes: [parent, leaf]), doc = DesignDocument(pages: [page, DesignPage(nodes: [foreign])])
        for destination: LayerDropDestination in [.inside(parent.id), .inside(child.id), .above(child.id), .below(parent.id), .inside(leaf.id), .inside(foreign.id), .above(UUID())] {
            #expect(!LayerTreeEditing.canMove(doc, pageID: page.id, selection: [parent.id], to: destination))
            #expect(throws: LayerEditError.invalidSelection) {
                try LayerTreeEditing.move(doc, pageID: page.id, selection: [parent.id], to: destination)
            }
        }
        #expect(throws: LayerEditError.invalidSelection) {
            try LayerTreeEditing.move(doc, pageID: page.id, selection: [foreign.id], to: .pageEnd)
        }
        #expect(doc.pages[0] == page)
    }

    @Test(arguments: [false, true]) func lockedOrHiddenParentsRejectButLockedSiblingIsValidAnchor(hidden: Bool) throws {
        let a = DesignNode(kind: .rectangle)
        let blocked = DesignNode(kind: .group, isVisible: !hidden, isLocked: !hidden, children: [a])
        let target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [blocked, target]), doc = DesignDocument(pages: [page])
        #expect(throws: LayerEditError.lockedOrHidden) { try LayerTreeEditing.move(doc, pageID: page.id, selection: [a.id], to: .pageEnd) }
        #expect(throws: LayerEditError.lockedOrHidden) { try LayerTreeEditing.move(doc, pageID: page.id, selection: [target.id], to: .inside(blocked.id)) }
        let result = try LayerTreeEditing.move(doc, pageID: page.id, selection: [target.id], to: .below(blocked.id))
        #expect(result.document.pages[0].nodes == [target, blocked])
    }

    @Test func depthAndConvertedCoordinateLimitsRejectWithoutMutation() throws {
        let moving = DesignNode(kind: .rectangle, frame: CGRect(x: 1e9, y: 0, width: 10, height: 10))
        let target = DesignNode(kind: .group, frame: CGRect(x: -1e9, y: 0, width: 10, height: 10))
        let page = DesignPage(nodes: [moving, target]), doc = DesignDocument(pages: [page])
        #expect(throws: (any Error).self) { try LayerTreeEditing.move(doc, pageID: page.id, selection: [moving.id], to: .inside(target.id)) }
        var deep = DesignNode(kind: .group)
        let deepest = deep.id
        for _ in 1..<DocumentCodec.maximumDepth { deep = DesignNode(kind: .group, children: [deep]) }
        let shallow = DesignNode(kind: .rectangle)
        let deepPage = DesignPage(nodes: [deep, shallow]), deepDoc = DesignDocument(pages: [deepPage])
        #expect(!LayerTreeEditing.canMove(deepDoc, pageID: deepPage.id, selection: [shallow.id], to: .inside(deepest)))
        #expect(throws: (any Error).self) { try LayerTreeEditing.move(deepDoc, pageID: deepPage.id, selection: [shallow.id], to: .inside(deepest)) }
        #expect(doc.pages[0] == page)
    }

    @Test(arguments: [-1.0, .infinity, 1e7 + 1]) func invalidRawSizesCannotAdvertiseAValidDrop(width: Double) {
        let node = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: width, height: 20))
        let page = DesignPage(nodes: [node]), document = DesignDocument(pages: [page])
        #expect(!LayerTreeEditing.canMove(document, pageID: page.id, selection: [node.id], to: .pageEnd))
    }

    private func sameWorldPoints(_ ids: [UUID], before: DesignPage, after: DesignPage) throws {
        for id in ids {
            let a = try #require(SceneGeometry.worldTransform(id: id, in: before))
            let b = try #require(SceneGeometry.worldTransform(id: id, in: after))
            for point in [CGPoint.zero, CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 20)] {
                let x = point.applying(a), y = point.applying(b)
                #expect(abs(x.x - y.x) < 1e-7 && abs(x.y - y.y) < 1e-7)
            }
        }
    }
}

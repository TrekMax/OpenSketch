import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct LayerTreeDragTests {
    @Test func draggingSelectedRowsKeepsMultiSelectionAndCommitsOneUndo() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse), target = DesignNode(kind: .group)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [a, b, target])]))
        session.selection = [a.id, b.id]
        let original = session.document
        let request = try #require(session.beginSidebarLayerDrag(a.id))
        #expect(request.selection == [a.id, b.id] && session.document == original && !session.history.canUndo)
        #expect(session.canDropSidebarLayers(request.id, to: .inside(target.id)))
        #expect(session.document == original && !session.isDirty)
        #expect(session.commitSidebarLayerDrop(request.id, to: .inside(target.id)))
        #expect(session.document.node(id: target.id)?.children.map(\.id) == [a.id, b.id])
        #expect(session.selection == [a.id, b.id] && session.sidebarLayerDrag == nil)
        let moved = session.document
        session.undo(); #expect(session.document == original && !session.history.canUndo)
        session.redo(); #expect(session.document == moved)
    }

    @Test func draggingUnselectedRowChangesOnlyThatRowAndNoOpPreservesRedo() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [a, b])]))
        session.selection = [a.id]
        let first = try #require(session.beginSidebarLayerDrag(b.id))
        #expect(first.selection == [b.id] && session.selection == [b.id])
        #expect(session.commitSidebarLayerDrop(first.id, to: .below(a.id)))
        session.undo()
        let unchanged = try #require(session.beginSidebarLayerDrag(b.id))
        #expect(session.commitSidebarLayerDrop(unchanged.id, to: .above(a.id)))
        #expect(session.history.canRedo && !session.history.canUndo && !session.isDirty)
    }

    @Test func staleTokensAndChangedDocumentsNeverMoveLayers() throws {
        let a = DesignNode(kind: .rectangle), target = DesignNode(kind: .group)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [a, target])]))
        let old = try #require(session.beginSidebarLayerDrag(a.id))
        let current = try #require(session.beginSidebarLayerDrag(a.id))
        #expect(!session.commitSidebarLayerDrop(old.id, to: .inside(target.id)))
        #expect(session.sidebarLayerDrag?.id == current.id)
        session.document.name = "已改变"
        let changed = session.document
        #expect(!session.canDropSidebarLayers(current.id, to: .inside(target.id)))
        #expect(!session.commitSidebarLayerDrop(current.id, to: .inside(target.id)))
        #expect(session.document == changed && !session.history.canUndo)
    }

    @Test func pageSwitchAndInputBoundaryCancelDragAndRenamePreventsStarting() throws {
        let a = DesignNode(kind: .rectangle)
        let first = DesignPage(nodes: [a]), second = DesignPage()
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        _ = try #require(session.beginSidebarLayerDrag(a.id))
        session.selectPage(second.id)
        #expect(session.sidebarLayerDrag == nil)
        session.selectPage(first.id)
        session.startSidebarRename(.layer(pageID: first.id, nodeID: a.id))
        #expect(session.beginSidebarLayerDrag(a.id) == nil)
        session.finishSidebarRename(cancel: true)
        _ = try #require(session.beginSidebarLayerDrag(a.id))
        session.finishInput?()
        #expect(session.sidebarLayerDrag == nil && !session.history.canUndo)
    }

    @Test func lockedSourceAndMixedLockedSelectionCannotStart() {
        let a = DesignNode(kind: .rectangle), locked = DesignNode(kind: .ellipse, isLocked: true)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [a, locked])]))
        #expect(session.beginSidebarLayerDrag(locked.id) == nil)
        session.selection = [a.id, locked.id]
        #expect(session.beginSidebarLayerDrag(a.id) == nil)
        #expect(session.sidebarLayerDrag == nil && !session.isDirty)
    }

    @Test func canStartAValidSiblingReorderEvenWhenMovingToPageWouldOverflow() throws {
        let a = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 0, width: 20, height: 20))
        let b = DesignNode(kind: .ellipse)
        let parent = DesignNode(kind: .group, frame: CGRect(x: 1e9, y: 0, width: 100, height: 100), children: [a, b])
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [parent])]))
        let request = try #require(session.beginSidebarLayerDrag(a.id))
        #expect(!session.canDropSidebarLayers(request.id, to: .pageEnd))
        #expect(session.canDropSidebarLayers(request.id, to: .above(b.id)))
        #expect(session.commitSidebarLayerDrop(request.id, to: .above(b.id)))
        #expect(session.document.node(id: parent.id)?.children == [b, a])
    }

}

import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct SidebarSelectionTests {
    @Test func shiftSelectsPagesWithoutChangingDocumentOrCrossPageLayers() {
        let layer = DesignNode(kind: .rectangle)
        let first = DesignPage(nodes: [layer]), second = DesignPage(name: "第二页")
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        let original = session.document
        session.selection = [layer.id]
        session.selectPage(second.id, extending: true)
        #expect(session.selectedPageIDs == [first.id, second.id])
        #expect(session.pageID == second.id && session.selection.isEmpty)
        session.selectPage(first.id, extending: true)
        #expect(session.selectedPageIDs == [second.id] && session.pageID == second.id)
        session.selectPage(second.id, extending: true)
        #expect(session.selectedPageIDs == [second.id] && session.pageID == second.id)
        #expect(session.document == original && !session.isDirty && !session.history.canUndo)
    }

    @Test func normalClickOnActivePageClearsOtherPageHighlightsAndKeepsItsLayers() {
        let first = DesignPage(), layer = DesignNode(kind: .ellipse)
        let second = DesignPage(nodes: [layer])
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        session.selectPage(second.id, extending: true)
        session.selection = [layer.id]
        session.selectPage(second.id)
        #expect(session.selectedPageIDs == [second.id])
        #expect(session.selection == [layer.id])
    }

    @Test func removingActivePageFromSelectionUsesARemainingPage() {
        let first = DesignPage(), second = DesignPage()
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        session.selectPage(second.id, extending: true)
        session.selectPage(second.id, extending: true)
        #expect(session.selectedPageIDs == [first.id] && session.pageID == first.id)
    }

    @Test func pageSelectionReconcilesAfterUndoAndDocumentReplacement() {
        let session = EditorSession(), first = session.pageID
        session.addPage()
        let second = session.pageID
        session.selectPage(first, extending: true)
        #expect(session.selectedPageIDs == [first, second])
        session.undo()
        #expect(session.pageID == first && session.selectedPageIDs == [first])
        session.redo()
        #expect(session.selectedPageIDs == [first])
        session.selectPage(second, extending: true)
        session.replace(session.document)
        #expect(session.pageID == first && session.selectedPageIDs == [first])
    }

    @Test func pageSelectionFinishesInlineRenameAndRetainsRedoWhenUnchanged() throws {
        let session = EditorSession()
        session.startSidebarRename(.page(session.pageID))
        session.updateSidebarRename(try #require(session.sidebarRename?.request.id), name: "已提交名称")
        session.selectPage(session.pageID)
        #expect(session.page.name == "已提交名称" && session.sidebarRename == nil)
        session.undo()
        session.selectPage(session.pageID, extending: true)
        #expect(session.history.canRedo && !session.history.canUndo)
        session.selectPage(UUID(), extending: true)
        #expect(session.selectedPageIDs == [session.pageID])
    }

    @Test func undoRemovingActivePagePreservesOtherSelectedPages() {
        let first = DesignPage(), second = DesignPage()
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        session.addPage()
        let third = session.pageID
        session.selectPage(first.id)
        session.selectPage(second.id, extending: true)
        // Shift adding the newly created page makes it active without clearing the others.
        session.selectPage(third, extending: true)
        #expect(session.selectedPageIDs == [first.id, second.id, third] && session.pageID == third)
        session.undo()
        #expect(session.selectedPageIDs == [first.id, second.id])
        #expect(session.selectedPageIDs.contains(session.pageID))
    }
}

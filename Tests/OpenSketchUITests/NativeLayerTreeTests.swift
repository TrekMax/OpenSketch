import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct NativeLayerTreeTests {
    private func startDrag(_ coordinator: NativeLayerTree.Coordinator, items: [LayerTreeItem], to pasteboard: NSPasteboard) -> Bool {
        let writers = items.compactMap { coordinator.outlineView(NativeLayerOutline(), pasteboardWriterForItem: $0) }
        guard writers.count == items.count else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(writers) else { return false }
        return coordinator.beginDrag(items)
    }

    @Test func nativeTreeReversesSiblingsAndMapsOutlineInsertionIndexes() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse)
        let group = DesignNode(kind: .group, children: [a, b]), root = DesignNode(kind: .frame)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [group, root])]))
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        #expect(tree.numberOfRows == 5) // two roots, two children, root drop row
        #expect(coordinator.roots.map(\.id) == [root.id, group.id])
        let item = try #require(coordinator.items[group.id])
        #expect(item.children.map(\.id) == [b.id, a.id])
        #expect(coordinator.destination(item: nil, childIndex: 0) == .above(root.id))
        #expect(coordinator.destination(item: item, childIndex: NSOutlineViewDropOnItemIndex) == .inside(group.id))
        #expect(coordinator.destination(item: item, childIndex: 0) == .above(b.id))
        #expect(coordinator.destination(item: item, childIndex: 2) == .below(a.id))
        #expect(coordinator.destination(item: nil, childIndex: 2) == .below(group.id))
        #expect(coordinator.destination(item: coordinator.items[a.id], childIndex: -1) == nil)
    }

    @Test func nativePasteboardMovesSelectionOnceAndChecksSourceIdentity() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse), group = DesignNode(kind: .group)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [a, b, group])]))
        session.selection = [a.id, b.id]
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let before = session.document
        #expect(startDrag(coordinator, items: [try #require(coordinator.items[a.id]), try #require(coordinator.items[b.id])], to: pasteboard))
        #expect(coordinator.dragToken(source: NativeLayerOutline(), pasteboard: pasteboard) == nil)
        #expect(coordinator.accept(source: tree, pasteboard: pasteboard, destination: .inside(group.id)))
        #expect(session.document.node(id: group.id)?.children.map(\.id) == [a.id, b.id])
        #expect(session.selection == [a.id, b.id])
        #expect(!coordinator.accept(source: tree, pasteboard: pasteboard, destination: .pageEnd))
        session.undo()
        #expect(session.document == before && !session.history.canUndo)
    }

    @Test func cancelStaleAndLockedDragsCannotMutateDocument() throws {
        let node = DesignNode(kind: .rectangle), locked = DesignNode(kind: .ellipse, isLocked: true)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node, locked])]))
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(!startDrag(coordinator, items: [try #require(coordinator.items[locked.id])], to: pasteboard))
        #expect(startDrag(coordinator, items: [try #require(coordinator.items[node.id])], to: pasteboard))
        coordinator.endDrag()
        #expect(!coordinator.accept(source: tree, pasteboard: pasteboard, destination: .pageEnd))
        #expect(startDrag(coordinator, items: [try #require(coordinator.items[node.id])], to: pasteboard))
        session.document.name = "updated"
        #expect(!coordinator.accept(source: tree, pasteboard: pasteboard, destination: .pageEnd))
        #expect(session.page.nodes == [node, locked] && !session.history.canUndo)
    }

    @Test func selectionRefreshKeepsCellsAndExpansionWhileModelReloadKeepsIdentity() throws {
        let child = DesignNode(kind: .rectangle), sibling = DesignNode(kind: .ellipse)
        let group = DesignNode(kind: .group, children: [child])
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [group, sibling])]))
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let item = try #require(coordinator.items[group.id])
        tree.collapseItem(item)
        session.selection = [sibling.id]
        coordinator.update()
        #expect(!tree.isItemExpanded(item) && tree.selectedRowIndexes == [0])
        session.document.updateNode(id: sibling.id) { $0.name = "changed" }
        coordinator.update()
        #expect(coordinator.items[group.id] === item && !tree.isItemExpanded(item))
        #expect(tree.selectedRowIndexes == [0])
    }
    @Test func noncontiguousSelectionCanDropAtGapBesideAnotherMovingRow() throws {
        let nodes = (0..<4).map { DesignNode(name: String($0), kind: .rectangle) }
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: nodes)]))
        session.selection = [nodes[3].id, nodes[1].id]
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(startDrag(coordinator, items: [try #require(coordinator.items[nodes[3].id]), try #require(coordinator.items[nodes[1].id])], to: pasteboard))
        let destination = try #require(coordinator.destination(item: nil, childIndex: 2))
        #expect(coordinator.accept(source: tree, pasteboard: pasteboard, destination: destination))
        #expect(session.page.nodes.map(\.id) == [nodes[0].id, nodes[1].id, nodes[3].id, nodes[2].id])
    }

    @Test(arguments: [UInt16(51), UInt16(117)]) func nativeDeleteKeyDeletesSelectionWithOneUndo(key: UInt16) throws {
        let node = DesignNode(kind: .rectangle)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key))
        tree.keyDown(with: event)
        #expect(session.page.nodes.isEmpty)
        session.undo()
        #expect(session.page.nodes == [node] && !session.history.canUndo)
    }

    @Test func collapsedGroupsStayCollapsedAcrossPageSwitches() throws {
        let group = DesignNode(kind: .group, children: [DesignNode(kind: .rectangle)])
        let first = DesignPage(nodes: [group]), second = DesignPage()
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        tree.collapseItem(coordinator.items[group.id])
        session.selectPage(second.id); coordinator.update()
        session.selectPage(first.id); coordinator.update()
        #expect(!tree.isItemExpanded(coordinator.items[group.id]))
    }

    @Test func nativeInlineRenameSurvivesDraftUpdatesAndCommitsOnSelection() throws {
        _ = NSApplication.shared
        let a = DesignNode(name: "original", kind: .rectangle), b = DesignNode(kind: .ellipse)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [a, b])]))
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 240, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = scroll
        defer { window.close() }
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        window.contentView?.layoutSubtreeIfNeeded()
        session.startSidebarRename(.layer(pageID: session.pageID, nodeID: a.id)); coordinator.update()
        let row = tree.row(forItem: coordinator.items[a.id])
        let cell = try #require(tree.view(atColumn: 0, row: row, makeIfNecessary: true) as? LayerTreeCell)
        cell.configure(item: try #require(coordinator.items[a.id]), session: session)
        let field = try #require(cell.accessibilityChildren()?.compactMap { $0 as? NativeSidebarRenameField }.first)
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "renamed"
        session.updateSidebarRename(try #require(session.sidebarRename?.request.id), name: "renamed")
        coordinator.update()
        #expect(cell.accessibilityChildren()?.compactMap { $0 as? NativeSidebarRenameField }.first === field)
        tree.selectRowIndexes([0], byExtendingSelection: false)
        #expect(session.document.node(id: a.id)?.name == "renamed" && session.selection == [b.id])
        session.undo(); #expect(session.document.node(id: a.id)?.name == "original" && !session.history.canUndo)
    }

    @Test func malformedOrDifferentPasteboardRowsCannotUseAnActiveRequest() throws {
        let node = DesignNode(kind: .rectangle)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        let coordinator = NativeLayerTree.Coordinator(session: session)
        let scroll = coordinator.makeScrollView()
        let tree = try #require(scroll.documentView as? NativeLayerOutline)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(startDrag(coordinator, items: [try #require(coordinator.items[node.id])], to: pasteboard))
        #expect(coordinator.dragToken(source: tree, pasteboard: pasteboard) != nil)
        pasteboard.setString(UUID().uuidString, forType: NativeLayerTree.Coordinator.pasteboardType)
        #expect(coordinator.dragToken(source: tree, pasteboard: pasteboard) == nil)
        pasteboard.setString("not a node", forType: NativeLayerTree.Coordinator.pasteboardType)
        #expect(coordinator.dragToken(source: tree, pasteboard: pasteboard) == nil)
        #expect(!session.history.canUndo)
    }

    @Test func nativeCellSuppliesDragPreviewAndAccessibleIndependentControls() throws {
        _ = NSApplication.shared
        let node = DesignNode(name: "拖动预览", kind: .rectangle)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        let cell = LayerTreeCell(frame: CGRect(x: 0, y: 0, width: 196, height: 32))
        cell.configure(item: LayerTreeItem(node: node), session: session)
        cell.layoutSubtreeIfNeeded()
        #expect(!cell.draggingImageComponents.isEmpty)
        #expect(cell.textField?.stringValue == "拖动预览")
        #expect(cell.imageView?.image != nil)
        #expect(cell.accessibilityChildren()?.compactMap { $0 as? NSButton }.count == 2)
    }

}

import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct LayerCommandTests {
    @Test func groupingSelectsNewGroupAndHasOneUndoAndRedo() throws {
        let session = makeSession()
        let original = session.document
        let children = session.page.nodes.map(\.id)
        session.selection = [children[0], children[2]]
        session.perform(.group)
        let group = try #require(session.selected)
        #expect(group.kind == .group)
        #expect(group.children.map(\.id) == [children[0], children[2]])
        #expect(session.page.nodes.map(\.id) == [children[1], group.id])
        let grouped = session.document
        session.undo()
        #expect(session.document == original)
        #expect(!session.history.canUndo)
        session.redo()
        #expect(session.document == grouped)
        #expect(!session.history.canRedo)
    }

    @Test(arguments: [LayerCommand.ungroup, .order(.forward), .order(.backward), .order(.front), .order(.back),
                      .align(.left), .align(.horizontalCenter), .align(.right), .align(.top),
                      .align(.verticalCenter), .align(.bottom), .distribute(.horizontal), .distribute(.vertical)])
    func eachCommandProducesExactlyOneUndo(command: LayerCommand) {
        let session = makeSession()
        if command == .ungroup {
            session.document.pages[0].nodes = [DesignNode(kind: .group, children: session.page.nodes)]
            session.history = DocumentHistory(document: session.document)
            session.selection = Set(session.page.nodes.map(\.id))
        } else if case .order = command {
            session.selection = [session.page.nodes[1].id]
        } else {
            session.selection = Set(session.page.nodes.map(\.id))
        }
        let original = session.document
        session.perform(command)
        #expect(session.document != original)
        let changed = session.document
        session.undo()
        #expect(session.document == original)
        #expect(!session.history.canUndo)
        session.redo()
        #expect(session.document == changed)
    }

    @Test func capabilityReadsInvalidAndUnchangedCommandsLeaveHistoryClean() {
        let session = makeSession()
        let original = session.document
        session.selection = [session.page.nodes[0].id]
        for _ in 0..<10 { #expect(!session.canPerform(.group)) }
        session.perform(.group)
        #expect(session.document == original)
        #expect(!session.history.canUndo)
        session.perform(.order(.back))
        #expect(session.document == original)
        #expect(!session.isDirty)
        #expect(!session.history.canUndo)
        session.selection = Set(session.page.nodes.map(\.id))
        for _ in 0..<10 { #expect(session.canPerform(.group)) }
        #expect(session.document == original)
        #expect(!session.history.canUndo)
    }

    @Test func codecRejectionReportsErrorWithoutMutationAfterSuccessfulPreflight() {
        let session = makeSession()
        session.document.pages[0].nodes[0].text = String(repeating: "文", count: DocumentCodec.maximumStringBytes + 1)
        session.history = DocumentHistory(document: session.document)
        session.selection = Set(session.page.nodes.map(\.id))
        let original = session.document, selected = session.selection
        #expect(session.canPerform(.group))
        session.perform(.group)
        #expect(session.document == original)
        #expect(session.selection == selected)
        #expect(!session.history.canUndo)
        #expect(session.message.hasPrefix("无法"))
    }

    @Test func activeInlineTransactionCommitsBeforeLayerCommand() throws {
        let session = makeSession()
        session.document.pages[0].nodes[0].kind = .text
        session.history = DocumentHistory(document: session.document)
        let original = session.document
        let canvas = CanvasView(session: session)
        let id = session.page.nodes[0].id
        canvas.beginText(id)
        try #require(canvas.editor).string = "提交中的文字"
        session.selection = Set(session.page.nodes.prefix(2).map(\.id))
        session.perform(.group)
        #expect(canvas.editor == nil)
        #expect(session.selected?.kind == .group)
        #expect(session.document.node(id: id)?.text == "提交中的文字")
        session.undo()
        #expect(session.page.nodes.count == 3)
        #expect(session.document.node(id: id)?.text == "提交中的文字")
        session.undo()
        #expect(session.document == original)
        #expect(!session.history.canUndo)
    }

    @Test func treeKeepsParentsBeforeReversedChildrenAndRealDepth() {
        let leaf = DesignNode(name: "最深", kind: .rectangle)
        let inner = DesignNode(name: "内组", kind: .group, children: [leaf])
        let sibling = DesignNode(name: "前子层", kind: .ellipse)
        let outer = DesignNode(name: "外组", kind: .group, children: [inner, sibling])
        let front = DesignNode(name: "前层", kind: .rectangle)
        let page = DesignPage(nodes: [outer, front])
        let rows = LayerTreeRow.rows(in: page)
        #expect(rows.map(\.id) == [front.id, outer.id, sibling.id, inner.id, leaf.id])
        #expect(rows.map(\.depth) == [0, 0, 1, 1, 2])
        #expect(LayerTreeRow.rows(in: page, collapsed: [inner.id]).map(\.id) == [front.id, outer.id, sibling.id, inner.id])
        #expect(LayerTreeRow.rows(in: page, collapsed: [outer.id]).map(\.id) == [front.id, outer.id])
    }

    @Test func shiftLayerSelectionTogglesMembership() {
        let session = makeSession()
        let ids = session.page.nodes.map(\.id)
        session.selectLayer(ids[0], extending: false)
        session.selectLayer(ids[1], extending: true)
        #expect(session.selection == [ids[0], ids[1]])
        session.selectLayer(ids[0], extending: true)
        #expect(session.selection == [ids[1]])
    }

    @Test func nativeLayerMenuRoutesToTheCurrentDocumentAndExposesShortcuts() throws {
        let app = NSApplication.shared
        let oldMenu = app.mainMenu, oldResponder = app.nextResponder
        defer { app.mainMenu = oldMenu; app.nextResponder = oldResponder }
        let controller = AppController()
        let first = controller.workspace.current
        first.session.replace(makeSession().document)
        first.session.selection = Set(first.session.page.nodes.map(\.id))
        controller.makeMenus()
        let menu = try #require(app.mainMenu?.item(withTitle: "图层")?.submenu)
        let group = try #require(menu.item(withTitle: "编组"))
        #expect(group.keyEquivalent == "g")
        #expect(group.keyEquivalentModifierMask == [.command])
        let ungroup = try #require(menu.item(withTitle: "取消编组"))
        #expect(ungroup.keyEquivalent == "g")
        #expect(ungroup.keyEquivalentModifierMask == [.command, .shift])
        for (title, key, shift) in [("上移一层", "]", false), ("下移一层", "[", false), ("置于顶层", "]", true), ("置于底层", "[", true)] {
            let item = try #require(menu.item(withTitle: title))
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == (shift ? [.command, .shift] : [.command]))
        }
        #expect(menu.item(withTitle: "对齐")?.submenu?.items.count == 6)
        #expect(menu.item(withTitle: "等距分布")?.submenu?.items.count == 2)
        #expect(controller.validateMenuItem(group))
        #expect(!controller.validateMenuItem(ungroup))
        let second = controller.workspace.newDocument()
        second.session.replace(makeSession().document)
        second.session.selection = Set(second.session.page.nodes.map(\.id))
        let original = first.session.document
        #expect(app.sendAction(try #require(group.action), to: group.target, from: group))
        #expect(first.session.document == original)
        #expect(second.session.selected?.kind == .group)
        #expect(!controller.validateMenuItem(group))
        #expect(controller.validateMenuItem(ungroup))
    }

    @Test(arguments: [("g", UInt16(5), false), ("g", UInt16(5), true),
                      ("]", UInt16(30), false), ("[", UInt16(33), false),
                      ("]", UInt16(30), true), ("[", UInt16(33), true)])
    func nativeTextInputDisablesLayerMenuAndDoesNotCommitOrChangeDocument(characters: String, keyCode: UInt16, shift: Bool) throws {
        let app = NSApplication.shared
        let oldMenu = app.mainMenu, oldResponder = app.nextResponder
        defer { app.mainMenu = oldMenu; app.nextResponder = oldResponder }
        let controller = AppController()
        controller.makeMenus()
        controller.session.replace(makeSession().document)
        controller.session.selection = Set(controller.session.page.nodes.map(\.id))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        controller.window = window
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        window.contentView = field
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "原生输入"
        let original = controller.session.document
        let bar = try #require(app.mainMenu)
        let menu = try #require(bar.item(withTitle: "图层")?.submenu)
        let item = try #require(menu.item(withTitle: "编组"))
        #expect(!controller.validateMenuItem(item))
        menu.update()
        #expect(!item.isEnabled)
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        let handled = bar.performKeyEquivalent(with: key)
        #expect(!handled)
        controller.performLayerCommand(item)
        #expect(controller.session.document == original)
        #expect(window.firstResponder === editor)
        #expect(!controller.session.history.canUndo)
    }

    @Test(arguments: [false, true]) func canvasUsesOutermostGroupUnlessOptionSelectsDeepest(direct: Bool) throws {
        let leaf = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 30, height: 30))
        let inner = DesignNode(kind: .group, frame: CGRect(x: 10, y: 10, width: 80, height: 80), children: [leaf])
        let outer = DesignNode(kind: .group, frame: CGRect(x: 20, y: 20, width: 150, height: 150), children: [inner])
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [outer])]))
        #expect(session.canvasSelectionTarget(leaf.id, direct: direct) == (direct ? leaf.id : outer.id))
        let fixture = makeCanvas(session)
        defer { fixture.window.close() }
        let event = try mouse(.leftMouseDown, at: CGPoint(x: 50, y: 50), canvas: fixture.canvas, modifiers: direct ? .option : [])
        fixture.canvas.mouseDown(with: event)
        #expect(session.selection == [direct ? leaf.id : outer.id])
        fixture.canvas.mouseUp(with: event)
    }

    @Test func groupedTextDoubleClickSelectsTextForInspectorFallback() throws {
        let text = DesignNode(kind: .text, frame: CGRect(x: 10, y: 10, width: 100, height: 40), text: "检查器中的文字")
        let group = DesignNode(kind: .group, frame: CGRect(x: 20, y: 20, width: 160, height: 100), children: [text])
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [group])]))
        let original = session.document
        let fixture = makeCanvas(session)
        defer { fixture.window.close() }
        let point = CGPoint(x: 50, y: 50)
        fixture.canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, canvas: fixture.canvas))
        fixture.canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, canvas: fixture.canvas))
        #expect(session.selection == [group.id])

        fixture.canvas.mouseDown(with: try mouse(.leftMouseDown, at: point, canvas: fixture.canvas, clickCount: 2))
        fixture.canvas.mouseUp(with: try mouse(.leftMouseUp, at: point, canvas: fixture.canvas, clickCount: 2))

        #expect(session.selection == [text.id])
        #expect(session.selected?.kind == .text)
        #expect(session.selected?.text == "检查器中的文字")
        #expect(fixture.canvas.editor == nil)
        #expect(fixture.canvas.textID == nil)
        #expect(session.message.contains("检查器"))
        #expect(session.document == original)
        #expect(!session.history.canUndo)
        #expect(!session.history.isEditing)
    }

    @Test func frameChildrenRemainDirectlySelectableAndGroupsCannotResize() throws {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 30, height: 30))
        let frame = DesignNode(kind: .frame, frame: CGRect(x: 20, y: 20, width: 100, height: 100), children: [child])
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [frame])]))
        #expect(session.canvasSelectionTarget(child.id, direct: false) == child.id)
        session.document.pages[0].nodes[0].kind = .group
        session.selection = [frame.id]
        let original = session.document.node(id: frame.id)?.frame.size
        let fixture = makeCanvas(session)
        defer { fixture.window.close() }
        fixture.canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 120, y: 120), canvas: fixture.canvas))
        #expect(fixture.canvas.resizing == nil)
        fixture.canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 150, y: 150), canvas: fixture.canvas))
        fixture.canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 150, y: 150), canvas: fixture.canvas))
        #expect(session.document.node(id: frame.id)?.frame.size == original)
    }

    @Test func contextMenusUseTheClickedRowOrPreserveItsMultiSelection() {
        let session = makeSession()
        let ids = session.page.nodes.map(\.id)
        session.selection = [ids[0], ids[1]]
        #expect(session.contextMenuSelection(for: ids[0]) == [ids[0], ids[1]])
        #expect(session.canPerform(.group, selection: session.contextMenuSelection(for: ids[0])))
        #expect(session.contextMenuSelection(for: ids[2]) == [ids[2]])
        #expect(!session.canPerform(.group, selection: session.contextMenuSelection(for: ids[2])))
        #expect(session.selection == [ids[0], ids[1]])
    }

    @Test func selectedGroupDoesNotDrawAResizeHandle() throws {
        let group = DesignNode(kind: .group, frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [group])]))
        session.grid = false
        let fixture = makeCanvas(session)
        defer { fixture.window.close() }
        func pixel() throws -> NSColor {
            fixture.canvas.needsDisplay = true
            let bitmap = try #require(fixture.canvas.bitmapImageRepForCachingDisplay(in: fixture.canvas.bounds))
            fixture.canvas.cacheDisplay(in: fixture.canvas.bounds, to: bitmap)
            return try #require(bitmap.colorAt(x: Int(118 * CGFloat(bitmap.pixelsWide) / fixture.canvas.bounds.width),
                                              y: Int(118 * CGFloat(bitmap.pixelsHigh) / fixture.canvas.bounds.height))?.usingColorSpace(.sRGB))
        }
        let baseline = try pixel()
        session.selection = [group.id]
        let selected = try pixel()
        #expect(abs(selected.redComponent - baseline.redComponent) < 0.002)
        #expect(abs(selected.greenComponent - baseline.greenComponent) < 0.002)
        #expect(abs(selected.blueComponent - baseline.blueComponent) < 0.002)
    }

    private func makeSession() -> EditorSession {
        EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [
            DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 20, height: 30)),
            DesignNode(kind: .ellipse, frame: CGRect(x: 40, y: 60, width: 30, height: 20)),
            DesignNode(kind: .rectangle, frame: CGRect(x: 110, y: 140, width: 40, height: 50))
        ])]))
    }

    private func makeCanvas(_ session: EditorSession) -> (canvas: CanvasView, window: NSWindow) {
        _ = NSApplication.shared
        session.pan = .zero
        let canvas = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        return (canvas, window)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, canvas: CanvasView, modifiers: NSEvent.ModifierFlags = [], clickCount: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers, timestamp: 0, windowNumber: canvas.window!.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1))
    }
}

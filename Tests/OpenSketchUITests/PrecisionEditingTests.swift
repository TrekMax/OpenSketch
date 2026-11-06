import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct PrecisionEditingTests {
    @Test func blankDragSelectsTwoAndEscapeRestoresInitialSelection() throws {
        let f = fixture(); defer { f.window.close() }
        let ids = f.session.page.nodes.map(\.id)
        f.session.selection = [ids[2]]
        try drag(f, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 100, y: 100))
        #expect(f.session.selection == [ids[0], ids[1]])
        f.canvas.keyDown(with: try key(53, f))
        #expect(f.session.selection == [ids[2]])
        #expect(!f.session.history.isEditing)
        #expect(!f.session.isDirty)
    }

    @Test func shiftMarqueeAddsAndMouseUpCreatesNoHistory() throws {
        let f = fixture(); defer { f.window.close() }
        let ids = f.session.page.nodes.map(\.id)
        f.session.selection = [ids[2]]
        try drag(f, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 100, y: 100), flags: .shift)
        f.canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 100, y: 100), f))
        #expect(f.session.selection == Set(ids))
        #expect(!f.session.history.canUndo)
        #expect(!f.session.history.isEditing)
    }

    @Test func repeatedArrowsCommitOneUndoAtLastKeyUpAndEscapeCancelsWholeSegment() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.selection = [id]
        let original = f.session.document
        for repeatIndex in 0..<3 { f.canvas.keyDown(with: try key(124, f, repeatKey: repeatIndex > 0)) }
        #expect(f.session.document.node(id: id)?.frame.minX == 23)
        #expect(f.session.history.isEditing)
        f.canvas.keyUp(with: try key(124, f, type: .keyUp))
        let moved = f.session.document
        f.session.undo(); #expect(f.session.document == original); #expect(!f.session.history.canUndo)
        f.session.redo(); #expect(f.session.document == moved)
        f.canvas.keyDown(with: try key(125, f, flags: .shift))
        #expect(f.session.document.node(id: id)?.frame.minY == 30)
        f.canvas.keyDown(with: try key(53, f))
        #expect(f.session.document == moved)
        #expect(!f.session.history.isEditing)
    }

    @Test func focusLossCommitsNudgeWithoutCommittingInlineTextOnEntry() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.selection = [id]
        f.window.makeFirstResponder(f.canvas)
        f.canvas.keyDown(with: try key(124, f))
        let field = NSTextField(frame: CGRect(x: 200, y: 200, width: 80, height: 30))
        f.canvas.addSubview(field); f.window.makeFirstResponder(field)
        #expect(!f.session.history.isEditing)
        #expect(f.session.history.canUndo)
        f.session.undo()
        f.session.document.updateNode(id: id) { $0.kind = .text; $0.text = "原文" }
        f.session.history = DocumentHistory(document: f.session.document)
        f.window.makeFirstResponder(f.canvas)
        f.canvas.beginText(id)
        let editor = try #require(f.canvas.editor)
        #expect(f.window.firstResponder === editor)
        #expect(f.session.history.isEditing)
        editor.string = "修改文字"
        f.session.finishInput?()
        #expect(f.session.document.node(id: id)?.text == "修改文字")
        f.session.undo(); #expect(f.session.document.node(id: id)?.text == "原文")
    }

    @Test func invalidSelectionMovementIsAtomic() {
        let a = DesignNode(kind: .rectangle, frame: CGRect(x: 1e9, y: 0, width: 20, height: 20))
        let b = DesignNode(kind: .rectangle, frame: CGRect(x: 20, y: 20, width: 20, height: 20))
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [b, a])]))
        s.selection = [a.id, b.id]; let original = s.document
        s.beginGesture(); s.moveSelection(by: CGSize(width: 1, height: 0))
        #expect(s.document == original)
        #expect(s.message.hasPrefix("无法"))
        #expect(s.message.contains("坐标"))
        s.commitGesture(); #expect(!s.history.canUndo)
    }

    @Test func snappingGuidesFollowHeldDragControlBypassesAndReleaseClears() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.selection = [id]
        try drag(f, from: CGPoint(x: 25, y: 25), to: CGPoint(x: 60, y: 45))
        #expect(f.session.document.node(id: id)?.frame.origin == CGPoint(x: 60, y: 40))
        #expect(!f.canvas.guides.isEmpty)
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 60, y: 45), f, flags: .control))
        #expect(f.session.document.node(id: id)?.frame.origin == CGPoint(x: 55, y: 40))
        #expect(f.canvas.guides.isEmpty)
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 60, y: 45), f))
        #expect(!f.canvas.guides.isEmpty)
        f.canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 60, y: 45), f))
        #expect(f.canvas.guides.isEmpty)
        f.session.undo(); #expect(f.session.document.node(id: id)?.frame.origin == CGPoint(x: 20, y: 20))
    }

    @Test func snappingToleranceUsesScreenPointsAndDisabledSessionStaysRaw() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.selection = [id]; f.session.zoom = 2
        try drag(f, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 122, y: 90))
        #expect(f.session.document.node(id: id)?.frame.minX == 56)
        f.canvas.keyDown(with: try key(53, f))
        #expect(f.canvas.guides.isEmpty)
        f.session.snapping = false; f.session.zoom = 1
        try drag(f, from: CGPoint(x: 25, y: 25), to: CGPoint(x: 60, y: 45))
        #expect(f.session.document.node(id: id)?.frame.minX == 55)
        #expect(f.canvas.guides.isEmpty)
        f.session.finishInput?()
        #expect(!f.session.history.isEditing)
    }

    @Test func marqueeReturnsBelowThresholdResetsToClickSelection() throws {
        let f = fixture(); defer { f.window.close() }
        try drag(f, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 100, y: 100))
        #expect(f.session.selection.count == 2)
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 6, y: 6), f))
        #expect(f.session.selection.isEmpty)
        f.canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 6, y: 6), f))
        #expect(!f.session.isDirty)
    }

    @Test func nativeTextAndNumericRespondersReceiveArrowsWithoutMovingLayers() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.document.updateNode(id: id) { $0.kind = .text; $0.text = "abc" }
        f.session.history = DocumentHistory(document: f.session.document)
        f.session.selection = [id]
        let original = f.session.document
        f.window.makeFirstResponder(f.canvas); f.canvas.beginText(id)
        let text = try #require(f.canvas.editor)
        #expect(f.window.firstResponder === text)
        text.setSelectedRange(NSRange(location: 0, length: 0))
        try #require(f.window.firstResponder).keyDown(with: try key(124, f))
        #expect(text.selectedRange().location == 1)
        #expect(f.session.document == original)
        #expect(f.session.history.isEditing)
        f.session.finishInput?()
        let number = NSTextField(frame: CGRect(x: 220, y: 200, width: 100, height: 30))
        number.formatter = NumberFormatter(); number.stringValue = "123"
        f.canvas.addSubview(number); number.selectText(nil)
        let numericEditor = try #require(number.currentEditor() as? NSTextView)
        #expect(f.window.firstResponder === numericEditor)
        numericEditor.setSelectedRange(NSRange(location: 0, length: 0))
        try #require(f.window.firstResponder).keyDown(with: try key(124, f))
        #expect(numericEditor.selectedRange().location == 1)
        #expect(f.session.document == original)
        #expect(!f.session.history.canUndo)
    }

    @Test func viewportChangeAndDocumentSwitchCommitToOriginSessionOnly() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.selection = [id]
        f.canvas.keyDown(with: try key(124, f))
        f.canvas.zoom(to: 2, anchor: .zero)
        #expect(!f.session.history.isEditing)
        f.session.undo(); #expect(f.session.document.node(id: id)?.frame.minX == 20)
        let workspace = DocumentWorkspace()
        workspace.current.session.replace(f.session.document)
        let first = workspace.current
        let c = CanvasView(session: first.session)
        first.session.selection = [id]
        c.keyDown(with: try key(124, f))
        first.session.snapping = false
        let second = workspace.newDocument()
        #expect(first.session.document.node(id: id)?.frame.minX == 21)
        #expect(first.session.history.canUndo)
        #expect(second.session.snapping)
        #expect(!second.session.isDirty)
        c.keyUp(with: try key(124, f, type: .keyUp))
        #expect(!second.session.history.canUndo)
        first.session.undo(); #expect(first.session.document.node(id: id)?.frame.minX == 20)
    }

    @Test func twoHeldDirectionsFinishOnlyAtLastReleaseAndRotatedChildUsesWorldDelta() throws {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        let parent = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 90, children: [child])
        let f = fixture(); defer { f.window.close() }
        f.session.replace(DesignDocument(pages: [DesignPage(nodes: [parent])]))
        f.session.selection = [child.id]
        let original = f.session.document
        f.canvas.keyDown(with: try key(124, f)); f.canvas.keyDown(with: try key(125, f, flags: .shift))
        let frame = try #require(f.session.document.node(id: child.id)?.frame)
        #expect(abs(frame.minX - 20) < 1e-9)
        #expect(abs(frame.minY - 9) < 1e-9)
        f.canvas.keyUp(with: try key(124, f, type: .keyUp)); #expect(f.session.history.isEditing)
        f.canvas.keyUp(with: try key(125, f, type: .keyUp)); #expect(!f.session.history.isEditing)
        f.session.undo(); #expect(f.session.document == original); #expect(!f.session.history.canUndo)
    }

    @Test func heldMarqueeDrawsOverlayAndCancelRemovesItWithoutChangingDocument() throws {
        let f = fixture(); defer { f.window.close() }
        f.session.grid = false
        let original = f.session.document
        let baseline = try pixel(f.canvas, x: 90, y: 20)
        try drag(f, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 100, y: 100))
        let held = try pixel(f.canvas, x: 90, y: 20)
        #expect(colorDistance(held, baseline) > 0.02)
        f.canvas.keyDown(with: try key(53, f))
        let cancelled = try pixel(f.canvas, x: 90, y: 20)
        #expect(colorDistance(cancelled, baseline) < 0.002)
        #expect(f.session.document == original)
        #expect(!f.session.isDirty)
    }

    @Test func failedSnappedMoveClearsGuidesAndPreservesAllPreviousGeometry() throws {
        let f = fixture(); defer { f.window.close() }
        let id = f.session.page.nodes[0].id
        f.session.selection = [id]
        try drag(f, from: CGPoint(x: 25, y: 25), to: CGPoint(x: 60, y: 45))
        #expect(!f.canvas.guides.isEmpty)
        let last = f.session.document
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 1e9 + 100, y: 45), f))
        #expect(f.session.document == last)
        #expect(f.canvas.guides.isEmpty)
        #expect(f.session.message.hasPrefix("无法"))
        f.canvas.keyDown(with: try key(53, f))
        #expect(f.session.document.node(id: id)?.frame.minX == 20)
        #expect(!f.session.history.canUndo)
    }

    @Test func ordinaryClickAndSmallMarqueeAtZoomStayClean() throws {
        let f = fixture(); defer { f.window.close() }
        f.canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 25, y: 25), f))
        f.canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 25, y: 25), f))
        #expect(!f.session.history.canUndo); #expect(!f.session.isDirty)
        f.session.zoom = 2
        try drag(f, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 6))
        if case let .marquee(_, rect, _, _) = f.canvas.precision { #expect(rect == nil) }
        else { Issue.record("Blank drag must remain a marquee") }
        f.session.finishInput?()
        #expect(!f.session.history.isEditing); #expect(!f.session.history.canUndo)
    }

    @Test func selectAllCommandAndToolShortcutCommitHeldArrowsBeforeChangingState() throws {
        let f = fixture(); defer { f.window.close() }
        let controller = AppController()
        controller.session.replace(f.session.document)
        let session = controller.session
        let canvas = CanvasView(session: session)
        let ids = session.page.nodes.map(\.id)
        session.selection = [ids[0]]
        let original = session.document
        canvas.keyDown(with: try key(124, f))
        controller.selectAll(nil)
        #expect(!session.history.isEditing)
        #expect(session.selection == Set(ids))
        canvas.keyUp(with: try key(124, f, type: .keyUp))
        session.undo(); #expect(session.document == original); #expect(!session.history.canUndo)
        session.selection = [ids[0]]
        canvas.keyDown(with: try key(124, f))
        canvas.keyDown(with: try key(15, f))
        #expect(session.tool == .rectangle)
        #expect(!session.history.isEditing)
        #expect(session.document.node(id: ids[0])?.frame.minX == 21)
        session.undo(); #expect(session.document == original)
    }

    @Test func windowLosingKeyCommitsHeldKeyboardTransaction() throws {
        let f = fixture(); defer { f.window.close() }
        f.session.selection = [f.session.page.nodes[0].id]
        f.canvas.keyDown(with: try key(124, f))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
        #expect(!f.session.history.isEditing)
        #expect(f.session.history.canUndo)
        if case .nudge = f.canvas.precision { Issue.record("Window focus loss left keyboard state active") }
    }

    @Test func heldSnapGuideDrawsInWorldCoordinatesAndMouseUpRemovesItsPixels() throws {
        let f = fixture(); defer { f.window.close() }
        f.session.grid = false
        f.session.document.pages[0].nodes[1].frame.origin.y = 100
        f.session.history = DocumentHistory(document: f.session.document)
        f.session.selection = [f.session.page.nodes[0].id]
        try drag(f, from: CGPoint(x: 25, y: 25), to: CGPoint(x: 60, y: 45))
        #expect(!f.canvas.guides.isEmpty)
        let held = try pixel(f.canvas, x: 60, y: 77)
        f.canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 60, y: 45), f))
        let released = try pixel(f.canvas, x: 60, y: 77)
        #expect(colorDistance(held, released) > 0.02)
        #expect(f.canvas.guides.isEmpty)
    }

    @Test func shiftMarqueeSuppressesPreviouslySelectedDescendantWhenContainerIsIncluded() throws {
        let f = fixture(); defer { f.window.close() }
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 5, y: 5, width: 10, height: 10))
        let frame = DesignNode(kind: .frame, frame: CGRect(x: 20, y: 20, width: 60, height: 60), children: [child])
        f.session.replace(DesignDocument(pages: [DesignPage(nodes: [frame])]))
        f.session.pan = .zero
        f.session.selection = [child.id]
        try drag(f, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 100, y: 100), flags: .shift)
        #expect(f.session.selection == [frame.id])
        f.canvas.keyDown(with: try key(53, f))
        #expect(f.session.selection == [child.id])
        #expect(!f.session.history.canUndo)
    }

    @Test func lockedRootRejectsWholeMoveWithChineseStatus() {
        let f = fixture(); defer { f.window.close() }
        let ids = f.session.page.nodes.map(\.id)
        f.session.document.pages[0].nodes[1].isLocked = true
        f.session.history = DocumentHistory(document: f.session.document)
        f.session.selection = [ids[0], ids[1]]
        let original = f.session.document
        f.session.beginGesture(); f.session.moveSelection(by: CGSize(width: 1, height: 0)); f.session.commitGesture()
        #expect(f.session.document == original)
        #expect(f.session.message.contains("锁定"))
        #expect(!f.session.history.canUndo)
    }

    private func pixel(_ canvas: CanvasView, x: CGFloat, y: CGFloat) throws -> NSColor {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.needsDisplay = true; canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        return try #require(bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / canvas.bounds.width),
                                          y: Int(y * CGFloat(bitmap.pixelsHigh) / canvas.bounds.height))?.usingColorSpace(.sRGB))
    }
    private func colorDistance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
    }

    private func fixture() -> (session: EditorSession, canvas: CanvasView, window: NSWindow) {
        _ = NSApplication.shared
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [
            DesignNode(kind: .rectangle, frame: CGRect(x: 20, y: 20, width: 20, height: 20)),
            DesignNode(kind: .rectangle, frame: CGRect(x: 60, y: 60, width: 20, height: 20)),
            DesignNode(kind: .rectangle, frame: CGRect(x: 180, y: 140, width: 20, height: 20))
        ])]))
        s.pan = .zero
        let c = CanvasView(session: s)
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false; w.contentView = c
        return (s, c, w)
    }
    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, _ f: (session: EditorSession, canvas: CanvasView, window: NSWindow), flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: f.canvas.convert(point, to: nil), modifierFlags: flags, timestamp: 0, windowNumber: f.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    private func key(_ code: UInt16, _ f: (session: EditorSession, canvas: CanvasView, window: NSWindow), flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, repeatKey: Bool = false) throws -> NSEvent {
        let character: String = switch code { case 123: "\u{F702}"; case 124: "\u{F703}"; case 125: "\u{F701}"; case 126: "\u{F700}"; case 15: "r"; default: "\u{1B}" }
        return try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: f.window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: repeatKey, keyCode: code))
    }
    private func drag(_ f: (session: EditorSession, canvas: CanvasView, window: NSWindow), from: CGPoint, to: CGPoint, flags: NSEvent.ModifierFlags = []) throws {
        f.canvas.mouseDown(with: try mouse(.leftMouseDown, from, f, flags: flags))
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, to, f, flags: flags))
    }
}

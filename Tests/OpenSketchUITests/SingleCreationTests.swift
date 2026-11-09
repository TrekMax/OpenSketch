import Testing
import AppKit
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct SingleCreationTests {
    @Test(arguments: [EditorTool.rectangle, .ellipse, .frame], [false, true])
    func shapeCreationReturnsToSelectionAndUndoesOnce(tool: EditorTool, drag: Bool) throws {
        let fixture = CanvasFixture(tool: tool)
        defer { fixture.window.close() }
        try fixture.create(drag: drag)
        let node = try #require(fixture.session.page.nodes.first)
        #expect(node.kind.rawValue == tool.rawValue)
        #expect(fixture.session.selection == [node.id])
        #expect(fixture.session.tool == .select)
        #expect(!fixture.session.history.isEditing)
        try fixture.click(at: CGPoint(x: 340, y: 240))
        #expect(fixture.session.page.nodes.map(\.id) == [node.id])
        fixture.session.undo()
        #expect(fixture.session.page.nodes.isEmpty)
        #expect(!fixture.session.history.canUndo)
        #expect(!fixture.session.isDirty)
        fixture.session.redo()
        #expect(fixture.session.page.nodes == [node])
    }

    @Test(arguments: [false, true])
    func newTextReturnsToSelectionAfterCommitOrCancel(cancel: Bool) throws {
        let fixture = CanvasFixture(tool: .text)
        defer { fixture.window.close() }
        try fixture.create()
        let node = try #require(fixture.session.page.nodes.first)
        let editor = try #require(fixture.canvas.editor)
        #expect(fixture.session.tool == .text)
        #expect(fixture.window.firstResponder === editor)
        editor.string = "你好 👩🏽‍💻"
        if cancel {
            editor.keyDown(with: try fixture.key(code: 53, characters: "\u{1b}"))
        } else {
            #expect(editor.performKeyEquivalent(with: try fixture.key(code: 36, characters: "\r", modifiers: .command)))
        }
        #expect(fixture.canvas.editor == nil)
        #expect(fixture.session.tool == .select)
        #expect(fixture.session.document.node(id: node.id)?.text == (cancel ? "输入文字" : "你好 👩🏽‍💻"))
        try fixture.click(at: CGPoint(x: 340, y: 240))
        #expect(fixture.session.page.nodes.map(\.id) == [node.id])
        if !cancel {
            fixture.session.undo()
            #expect(fixture.session.document.node(id: node.id)?.text == "输入文字")
        }
        fixture.session.undo()
        #expect(fixture.session.page.nodes.isEmpty)
        #expect(!fixture.session.history.canUndo)
        #expect(!fixture.session.isDirty)
    }

    @Test func outsideClickCommitsNewTextWithoutCreatingAnotherLayer() throws {
        let fixture = CanvasFixture(tool: .text)
        defer { fixture.window.close() }
        try fixture.create()
        let id = try #require(fixture.canvas.textID)
        try #require(fixture.canvas.editor).string = "完成"
        try fixture.click(at: CGPoint(x: 340, y: 240))
        #expect(fixture.canvas.editor == nil)
        #expect(fixture.session.page.nodes.map(\.id) == [id])
        #expect(fixture.session.document.node(id: id)?.text == "完成")
        #expect(fixture.session.tool == .select)
    }

    @Test(arguments: [EditorTool.rectangle, .ellipse, .frame, .text])
    func escapeCancelsCreationBeforeMouseUp(tool: EditorTool) throws {
        let fixture = CanvasFixture(tool: tool)
        defer { fixture.window.close() }
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        fixture.canvas.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: CGPoint(x: 100, y: 80)))
        #expect(fixture.session.page.nodes.count == 1)
        fixture.canvas.keyDown(with: try fixture.key(code: 53, characters: "\u{1b}"))
        fixture.canvas.mouseUp(with: try fixture.mouse(.leftMouseUp, at: CGPoint(x: 100, y: 80)))
        #expect(fixture.session.page.nodes.isEmpty)
        #expect(fixture.canvas.editor == nil)
        #expect(fixture.canvas.start == nil)
        #expect(!fixture.session.history.isEditing)
        #expect(!fixture.session.history.canUndo)
        #expect(!fixture.session.isDirty)
        #expect(fixture.session.tool == .select)
    }

    @Test func penCreatesOpenPathAndCommitsAsOneUndo() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 60))
        try fixture.click(at: CGPoint(x: 100, y: 140))
        #expect(fixture.session.page.nodes.count == 1)
        #expect(fixture.session.history.isEditing)
        fixture.canvas.keyDown(with: try fixture.key(code: 36, characters: "\r"))
        let node = try #require(fixture.session.page.nodes.first)
        #expect(node.kind == .path)
        #expect(node.path.commands == [
            .move(to: CGPoint(x: 0, y: 0)),
            .line(to: CGPoint(x: 100, y: 20)),
            .line(to: CGPoint(x: 60, y: 100))
        ])
        #expect(fixture.session.tool == .select)
        #expect(!fixture.session.history.isEditing)
        fixture.session.undo()
        #expect(fixture.session.page.nodes.isEmpty)
    }

    @Test func draggingPenPointCreatesCubicSegment() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 140, y: 40)))
        fixture.canvas.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: CGPoint(x: 140, y: 100)))
        fixture.canvas.mouseUp(with: try fixture.mouse(.leftMouseUp, at: CGPoint(x: 140, y: 100)))
        fixture.canvas.keyDown(with: try fixture.key(code: 36, characters: "\r"))
        let node = try #require(fixture.session.page.nodes.first)
        guard case .cubic(let control1, let control2, let destination) = node.path.commands.last else {
            Issue.record("Expected a cubic segment")
            return
        }
        #expect(control1 == CGPoint(x: 100, y: 0))
        #expect(control2 == CGPoint(x: 100, y: -60))
        #expect(destination == CGPoint(x: 100, y: 0))
    }

    @Test func penDoubleClickClosesPathAndEscapeCancelsDraft() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 40))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 40, y: 40), clickCount: 2))
        let closed = try #require(fixture.session.page.nodes.first)
        #expect(closed.path.commands.last == .close)
        #expect(fixture.session.tool == .select)

        fixture.session.tool = .pen
        try fixture.click(at: CGPoint(x: 200, y: 200))
        fixture.canvas.keyDown(with: try fixture.key(code: 53, characters: "\u{1b}"))
        #expect(fixture.session.page.nodes.count == 1)
        #expect(fixture.session.tool == .select)
        #expect(!fixture.session.history.isEditing)
    }

    @Test func doubleClickingAPathEntersNodeEditingAndDraggingMovesItsPoint() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 40))
        fixture.canvas.keyDown(with: try fixture.key(code: 36, characters: "\r"))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 40, y: 40), clickCount: 2))
        fixture.canvas.mouseDragged(with: try fixture.mouse(.leftMouseDragged, at: CGPoint(x: 60, y: 60)))
        fixture.canvas.mouseUp(with: try fixture.mouse(.leftMouseUp, at: CGPoint(x: 60, y: 60)))
        let node = try #require(fixture.session.page.nodes.first)
        #expect(node.path.commands.first == .move(to: CGPoint(x: 20, y: 20)))
        #expect(fixture.session.history.canUndo)
    }

    @Test func nodeEditingDeletesSelectedPointWithOneUndo() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 140))
        fixture.canvas.keyDown(with: try fixture.key(code: 36, characters: "\r"))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 140, y: 40), clickCount: 2))
        fixture.canvas.keyDown(with: try fixture.key(code: 51, characters: "\u{7f}"))
        let node = try #require(fixture.session.page.nodes.first)
        #expect(node.path.commands == [
            .move(to: CGPoint(x: 0, y: 0)),
            .line(to: CGPoint(x: 100, y: 100))
        ])
        #expect(fixture.session.history.canUndo)
        fixture.session.undo()
        #expect(fixture.session.page.nodes.first?.path.commands.count == 3)
    }

    @Test func nodeEditingSupportsShiftMultiSelectionAndOptionInsertion() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 140))
        fixture.canvas.keyDown(with: try fixture.key(code: 36, characters: "\r"))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 40, y: 40), clickCount: 2))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 140, y: 140), modifiers: .shift))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 90, y: 40), clickCount: 2, modifiers: .option))
        fixture.canvas.mouseUp(with: try fixture.mouse(.leftMouseUp, at: CGPoint(x: 90, y: 40), clickCount: 2, modifiers: .option))
        let node = try #require(fixture.session.page.nodes.first)
        #expect(node.path.commands.count == 4)
        #expect(fixture.session.history.canUndo)
    }

    @Test func nodeEditingTogglesClosedAndReversesPath() throws {
        let fixture = CanvasFixture(tool: .pen)
        defer { fixture.window.close() }
        try fixture.click(at: CGPoint(x: 40, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 40))
        try fixture.click(at: CGPoint(x: 140, y: 140))
        fixture.canvas.keyDown(with: try fixture.key(code: 36, characters: "\r"))
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 40, y: 40), clickCount: 2))
        fixture.canvas.keyDown(with: try fixture.key(code: 8, characters: "c"))
        #expect(fixture.session.page.nodes.first?.path.commands.last == .close)
        fixture.canvas.keyDown(with: try fixture.key(code: 15, characters: "r"))
        #expect(fixture.session.page.nodes.first?.path.commands.first == .move(to: CGPoint(x: 100, y: 100)))
        #expect(fixture.session.history.canUndo)
    }

    @Test(arguments: [false, true])
    func completingOrCancellingDragPreservesNewTool(cancel: Bool) throws {
        let fixture = CanvasFixture(tool: .rectangle)
        defer { fixture.window.close() }
        fixture.canvas.mouseDown(with: try fixture.mouse(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        fixture.canvas.keyDown(with: try fixture.key(code: 31, characters: "o"))
        if cancel { fixture.canvas.keyDown(with: try fixture.key(code: 53, characters: "\u{1b}")) }
        fixture.canvas.mouseUp(with: try fixture.mouse(.leftMouseUp, at: CGPoint(x: 100, y: 80)))
        #expect(fixture.session.tool == .ellipse)
        #expect(fixture.session.page.nodes.count == (cancel ? 0 : 1))
        try fixture.click(at: CGPoint(x: 340, y: 240))
        #expect(fixture.session.page.nodes.last?.kind == .ellipse)
        #expect(fixture.session.tool == .select)
    }

    @Test func changingToolDuringTextEditingCreatesThatToolOnNextClick() throws {
        let fixture = CanvasFixture(tool: .text)
        defer { fixture.window.close() }
        try fixture.create()
        let textID = try #require(fixture.canvas.textID)
        try #require(fixture.canvas.editor).string = "文字"
        fixture.session.tool = .ellipse // Simulate an explicit tool change before pending text cleanup.
        try fixture.click(at: CGPoint(x: 340, y: 240))
        #expect(fixture.canvas.editor == nil)
        #expect(fixture.session.document.node(id: textID)?.text == "文字")
        #expect(fixture.session.page.nodes.map(\.kind) == [.text, .ellipse])
        #expect(fixture.session.tool == .select)
    }

    @Test(arguments: [false, true])
    func completingOrCancellingNewTextPreservesNewTool(cancel: Bool) throws {
        let fixture = CanvasFixture(tool: .text)
        defer { fixture.window.close() }
        try fixture.create()
        let editor = try #require(fixture.canvas.editor)
        fixture.session.tool = .ellipse
        if cancel { editor.keyDown(with: try fixture.key(code: 53, characters: "\u{1b}")) }
        else { #expect(editor.performKeyEquivalent(with: try fixture.key(code: 36, characters: "\r", modifiers: .command))) }
        #expect(fixture.canvas.editor == nil)
        #expect(fixture.session.tool == .ellipse)
    }

    @Test func textCanBeExplicitlySelectedAgainAfterCompletion() throws {
        let fixture = CanvasFixture(tool: .text)
        defer { fixture.window.close() }
        try fixture.create()
        let editor = try #require(fixture.canvas.editor)
        #expect(editor.performKeyEquivalent(with: try fixture.key(code: 36, characters: "\r", modifiers: .command)))
        #expect(fixture.session.tool == .select)
        fixture.canvas.keyDown(with: try fixture.key(code: 17, characters: "t"))
        try fixture.click(at: CGPoint(x: 340, y: 240))
        #expect(fixture.session.page.nodes.map(\.kind) == [.text, .text])
        #expect(fixture.canvas.editor != nil)
        fixture.canvas.finishText(commit: false)
    }
}

@MainActor private struct CanvasFixture {
    let session: EditorSession
    let canvas: CanvasView
    let window: NSWindow

    init(tool: EditorTool) {
        _ = NSApplication.shared
        session = EditorSession()
        session.pan = .zero
        session.tool = tool
        canvas = CanvasView(session: session)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        window.makeFirstResponder(canvas)
    }

    func mouse(_ type: NSEvent.EventType, at point: CGPoint, clickCount: Int = 1,
               modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1))
    }

    func key(code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    func click(at point: CGPoint) throws {
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: point))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: point))
    }

    func create(drag: Bool = true) throws {
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 20, y: 20)))
        if drag { canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 140, y: 100))) }
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 140, y: 100)))
    }
}

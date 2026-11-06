import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct InspectorEditingTests {
    @Test(arguments: InspectorNumberProperty.allCases)
    func numericPropertiesShareFiniteValidationAndRanges(property: InspectorNumberProperty) throws {
        let s = fixture(kind: .text), id = try #require(s.selection.first)
        let original = s.document
        for value in [Double.nan, .infinity, -.infinity] { s.setInspectorNumber(property, nodeID: id, value: value) }
        #expect(s.document == original)
        #expect(!s.history.canUndo)
        s.setInspectorNumber(property, nodeID: id, value: -2e10)
        let low = try #require(s.document.node(id: id))
        let limits: (Double, Double) = switch property {
        case .x, .y: (-1e9, 1e9)
        case .width, .height: (1, 1e7)
        case .rotation: (-200, 200)
        case .opacity: (0, 100)
        case .strokeWidth: (0, 10000)
        case .cornerRadius: (0, 1e7)
        case .fontSize: (1, 1000)
        }
        #expect(property.value(in: low) == limits.0)
        s.setInspectorNumber(property, nodeID: id, value: 2e10)
        let high = try #require(s.document.node(id: id))
        #expect(property.value(in: high) == limits.1)
        #expect(throws: Never.self) { _ = try DocumentCodec.encode(s.document) }
        if property == .opacity { #expect(high.style.opacity == 1) }
    }

    @Test func repeatedRelativeUpdatesCommitOneUndoAndRedo() throws {
        let s = fixture(), id = try #require(s.selection.first), original = s.document
        let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 10)
        s.scrubInspectorNumber(token, translation: 25)
        #expect(s.document.node(id: id)?.frame.minX == 45)
        #expect(s.canUndo)
        #expect(s.history.isEditing)
        s.finishInspectorEdit(token)
        let edited = s.document
        s.undo(); #expect(s.document == original); #expect(!s.history.canUndo)
        s.redo(); #expect(s.document == edited); #expect(!s.history.canRedo)
    }

    @Test(arguments: [(NSEvent.ModifierFlags(), CGFloat(30)), (NSEvent.ModifierFlags.shift, CGFloat(120)), (NSEvent.ModifierFlags.option, CGFloat(21)), (NSEvent.ModifierFlags([.shift, .option]), CGFloat(21))])
    func modifiersScaleTotalTranslation(flags: NSEvent.ModifierFlags, expected: CGFloat) throws {
        let s = fixture(), id = try #require(s.selection.first)
        let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 10, modifiers: flags)
        #expect(s.document.node(id: id)?.frame.minX == expected)
        s.finishInspectorEdit(token)
    }

    @Test func cancelAndReturnToOriginPreservePriorRedo() throws {
        let s = fixture(), id = try #require(s.selection.first)
        s.setInspectorNumber(.x, nodeID: id, value: 30); s.undo()
        let original = s.document
        var token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 25); s.finishInspectorEdit(token, cancel: true)
        #expect(s.document == original); #expect(s.history.canRedo); #expect(!s.history.canUndo)
        token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 25); s.scrubInspectorNumber(token, translation: 0)
        #expect(!s.canUndo)
        s.finishInspectorEdit(token)
        #expect(s.document == original); #expect(s.history.canRedo); #expect(!s.history.canUndo)
    }

    @Test(arguments: [false, true]) func blockedAncestorPreventsDirectAndScrubEdits(hidden: Bool) {
        let child = DesignNode(kind: .rectangle)
        var group = DesignNode(kind: .group, children: [child])
        group.isVisible = !hidden; group.isLocked = !hidden
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [group])]))
        s.selection = [child.id]; let original = s.document
        #expect(s.beginInspectorEdit(.x, nodeID: child.id) == nil)
        s.setInspectorNumber(.x, nodeID: child.id, value: 30)
        #expect(s.document == original); #expect(!s.history.canUndo)
    }

    @Test func groupSizeIsReadOnly() throws {
        let s = fixture(kind: .group), id = try #require(s.selection.first), original = s.document
        #expect(s.beginInspectorEdit(.width, nodeID: id) == nil)
        s.setInspectorNumber(.height, nodeID: id, value: 400)
        #expect(s.document == original)
    }

    @Test func selectionAndPageChangesEndTheTransactionAndIgnoreLateEvents() throws {
        let s = fixture(), id = try #require(s.selection.first)
        let other = DesignNode(kind: .rectangle)
        s.document.pages[0].nodes.append(other)
        let second = DesignPage(); s.document.pages.append(second)
        s.history = DocumentHistory(document: s.document)
        var token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 5); s.selection = [other.id]
        s.scrubInspectorNumber(token, translation: 100); s.finishInspectorEdit(token, cancel: true)
        #expect(s.document.node(id: id)?.frame.minX == 25)
        #expect(s.document.node(id: other.id)?.frame.minX == other.frame.minX)
        #expect(!s.history.isEditing)
        token = try #require(s.beginInspectorEdit(.y, nodeID: other.id))
        s.scrubInspectorNumber(token, translation: 10); s.selectPage(second.id)
        s.scrubInspectorNumber(token, translation: 100)
        #expect(s.document.node(id: other.id)?.frame.minY == other.frame.minY + 10)
        #expect(!s.history.isEditing)
    }

    @Test func workspaceSwitchReplaceAndUndoCannotLeakLateInput() throws {
        let workspace = DocumentWorkspace(), first = workspace.current.session
        first.replace(fixture().document)
        let id = first.page.nodes[0].id; first.selection = [id]
        let token = try #require(first.beginInspectorEdit(.x, nodeID: id))
        first.scrubInspectorNumber(token, translation: 25)
        let second = workspace.newDocument().session, blank = second.document
        first.scrubInspectorNumber(token, translation: 200)
        #expect(first.document.node(id: id)?.frame.minX == 45)
        #expect(second.document == blank); #expect(!second.history.canUndo)
        first.undo(); #expect(first.document.node(id: id)?.frame.minX == 20)
        first.selection = [id]
        let replacementToken = try #require(first.beginInspectorEdit(.x, nodeID: id))
        first.scrubInspectorNumber(replacementToken, translation: 15)
        first.replace(blank); first.scrubInspectorNumber(replacementToken, translation: 100)
        #expect(first.document == blank); #expect(!first.history.isEditing)
    }

    @Test func inspectorStartFinishesCanvasTextAndUndoInterruptsScrub() throws {
        _ = NSApplication.shared
        let s = fixture(kind: .text), id = try #require(s.selection.first)
        let canvas = CanvasView(session: s); canvas.beginText(id)
        try #require(canvas.editor).string = "已提交"
        let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        #expect(canvas.editor == nil)
        #expect(s.document.node(id: id)?.text == "已提交")
        s.scrubInspectorNumber(token, translation: 10); s.undo()
        #expect(s.document.node(id: id)?.frame.minX == 20)
        #expect(s.document.node(id: id)?.text == "已提交")
        s.scrubInspectorNumber(token, translation: 200)
        #expect(s.document.node(id: id)?.frame.minX == 20)
        s.undo(); #expect(s.document.node(id: id)?.text == "")
    }

    @Test func saveFinishesScrubBeforeEncodingAndRetainsUndo() throws {
        _ = NSApplication.shared
        let controller = AppController(), s = controller.session
        s.replace(fixture().document)
        let id = s.page.nodes[0].id; s.selection = [id]
        let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 25)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".opensketch")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(controller.saveDocument(forcePanel: false, chooseDestination: { _ in url }))
        #expect(try DocumentCodec.load(from: url).node(id: id)?.frame.minX == 45)
        #expect(!s.history.isEditing); #expect(!s.isDirty)
        s.undo(); #expect(s.document.node(id: id)?.frame.minX == 20); #expect(s.isDirty)
    }

    @Test func nativeLabelThresholdEscapeAndLateMouseUp() throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        let id = try #require(s.selection.first)
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: control.scrubLabel.convert(CGPoint(x: x, y: 10), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        control.scrubLabel.mouseDown(with: try mouse(.leftMouseDown, 5))
        control.scrubLabel.mouseDragged(with: try mouse(.leftMouseDragged, 7))
        #expect(!s.history.isEditing); #expect(s.document.node(id: id)?.frame.minX == 20)
        control.scrubLabel.mouseDragged(with: try mouse(.leftMouseDragged, 15))
        #expect(s.document.node(id: id)?.frame.minX == 30)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        control.scrubLabel.keyDown(with: escape)
        control.scrubLabel.mouseUp(with: try mouse(.leftMouseUp, 15))
        #expect(s.document.node(id: id)?.frame.minX == 20); #expect(!s.history.canUndo)
        #expect(!s.history.isEditing)
        #expect(control.field.accessibilityIdentifier() == "inspector.x")
        #expect(control.scrubLabel.accessibilityIdentifier() == "inspector.x.scrub")
    }

    @Test func nativeFieldTypingSaveFocusLossAndDetachmentCommit() throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        let id = try #require(s.selection.first)
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.insertText("42", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        s.finishInput?()
        #expect(s.document.node(id: id)?.frame.minX == 42)
        #expect(!s.history.isEditing); #expect(s.history.canUndo)
        window.makeFirstResponder(nil)
        s.undo(); #expect(s.document.node(id: id)?.frame.minX == 20)
        let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(token, translation: 10)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!s.history.isEditing); #expect(s.document.node(id: id)?.frame.minX == 30)
        let next = try #require(s.beginInspectorEdit(.x, nodeID: id))
        s.scrubInspectorNumber(next, translation: 5)
        control.removeFromSuperview()
        #expect(!s.history.isEditing); #expect(s.document.node(id: id)?.frame.minX == 35)
    }

    @Test func nativeNumericTextKeepsArrowKeysAndEscapeCancelsTyping() throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        let id = try #require(s.selection.first)
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let arrow = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
        editor.keyDown(with: arrow)
        #expect(editor.selectedRange().location == 1)
        #expect(s.document.node(id: id)?.frame.minX == 20)
        editor.insertText("75", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        #expect(control.control(control.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(!s.history.isEditing); #expect(!s.history.canUndo)
        #expect(s.document.node(id: id)?.frame.minX == 20)
    }

    @Test func coordinatedFinishKeepsCanvasCallbackAndDoesNotRetainSession() throws {
        weak var released: EditorSession?
        var retainedFinish: (() -> Void)?
        do {
            let s = fixture(); released = s
            let id = try #require(s.selection.first)
            var calls = 0
            s.finishInput = { calls += 1 }
            retainedFinish = s.finishInput
            let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
            #expect(calls == 1)
            s.scrubInspectorNumber(token, translation: 10)
            s.finishInput?()
            #expect(calls == 2); #expect(!s.history.isEditing)
            #expect(s.history.canUndo)
        }
        #expect(released == nil)
        retainedFinish?()
    }

    @Test func scrubMenuValidationIsPureAndCommandUndoEndsOnlyOneTransaction() throws {
        _ = NSApplication.shared
        let controller = AppController(), s = controller.session
        s.replace(fixture().document)
        let id = s.page.nodes[0].id; s.selection = [id]
        let token = try #require(s.beginInspectorEdit(.x, nodeID: id))
        let item = NSMenuItem(title: "撤销", action: #selector(AppController.undo(_:)), keyEquivalent: "z")
        #expect(!controller.validateMenuItem(item))
        s.scrubInspectorNumber(token, translation: 10)
        for _ in 0..<3 { #expect(controller.validateMenuItem(item)) }
        #expect(s.history.isEditing)
        controller.undo(nil)
        #expect(s.document.node(id: id)?.frame.minX == 20)
        #expect(!s.history.canUndo); #expect(s.history.canRedo)
        s.scrubInspectorNumber(token, translation: 100)
        #expect(s.document.node(id: id)?.frame.minX == 20)
    }

    @Test(arguments: [false, true]) func nativeReturnAndTabCommitTyping(tab: Bool) throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        let next = NSTextField(frame: CGRect(x: 10, y: 60, width: 100, height: 26))
        window.contentView?.addSubview(next)
        control.field.nextKeyView = next
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.insertText("55", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        if tab { editor.insertTab(nil) } else { editor.insertNewline(nil) }
        #expect(s.selected?.frame.minX == 55)
        #expect(!s.history.isEditing); #expect(s.history.canUndo)
        if tab { #expect(next.currentEditor() != nil) }
        s.undo(); #expect(s.selected?.frame.minX == 20)
    }

    @Test func focusLossAllowsANewEditingSegmentInTheSameField() throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.insertText("55", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!s.history.isEditing)
        // Restoring the window does not reselect the field or replace its editor.
        #expect(control.field.currentEditor() === editor)
        editor.insertText("65", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        window.makeFirstResponder(nil)
        #expect(s.selected?.frame.minX == 65)
        s.undo(); #expect(s.selected?.frame.minX == 55)
    }

    @Test func anOldFieldEditorCannotRestartInputAfterRebindingToAnotherNode() throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        let originalID = try #require(s.selection.first)
        let other = DesignNode(kind: .rectangle, frame: CGRect(x: 90, y: 30, width: 80, height: 60))
        s.document.pages[0].nodes.append(other)
        s.history = DocumentHistory(document: s.document)
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.insertText("55", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        s.selection = [other.id]
        control.configure(session: s, nodeID: other.id, property: .x)
        #expect(control.field.currentEditor() == nil)
        editor.insertText("65", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        window.makeFirstResponder(nil)
        #expect(s.document.node(id: originalID)?.frame.minX == 55)
        #expect(s.document.node(id: other.id)?.frame.minX == 90)
        #expect(!s.history.isEditing)
    }

    @Test func nativeTextUndoRemainsLocalUntilTheFieldCommits() throws {
        let (s, control, window) = nativeFixture(); defer { window.close() }
        s.setInspectorNumber(.y, nodeID: s.selection.first!, value: 80)
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.insertText("75", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        #expect(editor.undoManager?.canUndo == true)
        editor.undoManager?.undo()
        #expect(editor.string == "20")
        #expect(s.selected?.frame.minX == 20)
        #expect(s.selected?.frame.minY == 80)
        window.makeFirstResponder(nil)
        #expect(!s.history.isEditing)
        s.undo(); #expect(s.selected?.frame.minY == 30)
    }

    @Test func numericControlResolvesItsOwnLightAndDarkSurface() throws {
        let (_, control, window) = nativeFixture(); defer { window.close() }
        control.appearance = NSAppearance(named: .aqua)
        control.viewDidChangeEffectiveAppearance()
        let light = try #require(control.layer?.backgroundColor)
        control.appearance = NSAppearance(named: .darkAqua)
        control.viewDidChangeEffectiveAppearance()
        let dark = try #require(control.layer?.backgroundColor)
        let lightColor = try #require(NSColor(cgColor: light)?.usingColorSpace(.sRGB))
        let darkColor = try #require(NSColor(cgColor: dark)?.usingColorSpace(.sRGB))
        #expect(lightColor.redComponent > 0.9)
        #expect(abs(darkColor.redComponent - 0.2) < 0.01)
    }

    @Test(arguments: [InspectorNumberProperty.width, .rotation, .opacity])
    func returningToOriginRestoresTheExactStoredValue(property: InspectorNumberProperty) throws {
        let s = fixture(), id = try #require(s.selection.first)
        s.document.updateNode(id: id) {
            $0.frame.size.width = 0; $0.rotation = 720; $0.style.opacity = 0.12345678912345678
        }
        s.history = DocumentHistory(document: s.document)
        let original = s.document
        let token = try #require(s.beginInspectorEdit(property, nodeID: id))
        s.scrubInspectorNumber(token, translation: 20)
        s.scrubInspectorNumber(token, translation: 0)
        s.finishInspectorEdit(token)
        #expect(s.document == original)
        #expect(!s.history.canUndo)
    }

    @Test(arguments: [InspectorNumberProperty.opacity, .cornerRadius, .height])
    func refreshedNumericGlyphsMatchAFreshNativeControl(property: InspectorNumberProperty) throws {
        let (s, reused, window) = nativeFixture(); defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        let id = try #require(s.selection.first)
        s.document.updateNode(id: id) { $0.style.opacity = 0.7; $0.style.cornerRadius = 8; $0.frame.size.height = 120 }
        reused.configure(session: s, nodeID: id, property: property)
        reused.layoutSubtreeIfNeeded()
        let before = try #require(reused.bitmapImageRepForCachingDisplay(in: reused.bounds))
        reused.cacheDisplay(in: reused.bounds, to: before)
        s.document.updateNode(id: id) { $0.style.opacity = 1; $0.style.cornerRadius = 0; $0.frame.size.height = 80 }
        reused.configure(session: s, nodeID: id, property: property)
        reused.layoutSubtreeIfNeeded()
        // A new destination avoids mistaking transparent drawing over an old
        // caller-owned bitmap for stale pixels inside the native view itself.
        let bitmap = try #require(reused.bitmapImageRepForCachingDisplay(in: reused.bounds))
        reused.cacheDisplay(in: reused.bounds, to: bitmap)
        let fresh = InspectorNumberControl(frame: reused.frame)
        window.contentView?.addSubview(fresh)
        fresh.configure(session: s, nodeID: id, property: property)
        fresh.layoutSubtreeIfNeeded()
        let expected = try #require(fresh.bitmapImageRepForCachingDisplay(in: fresh.bounds))
        fresh.cacheDisplay(in: fresh.bounds, to: expected)
        #expect(bitmap.pixelsWide == expected.pixelsWide)
        #expect(bitmap.pixelsHigh == expected.pixelsHigh)
        var differingPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if bitmap.colorAt(x: x, y: y) != expected.colorAt(x: x, y: y) { differingPixels += 1 }
            }
        }
        #expect(differingPixels == 0)
    }

    private func nativeFixture() -> (EditorSession, InspectorNumberControl, NSWindow) {
        _ = NSApplication.shared
        let s = fixture()
        let control = InspectorNumberControl(frame: CGRect(x: 10, y: 10, width: 108, height: 26))
        control.configure(session: s, nodeID: s.selection.first!, property: .x)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(control)
        control.layoutSubtreeIfNeeded()
        return (s, control, window)
    }

    private func fixture(kind: NodeKind = .rectangle) -> EditorSession {
        let node = DesignNode(kind: kind, frame: CGRect(x: 20, y: 30, width: 80, height: 60))
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        return session
    }
}

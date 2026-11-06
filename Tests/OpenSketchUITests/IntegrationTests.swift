import Testing
import AppKit
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct IntegrationTests {
    @Test func cancelledMoveRestoresCleanSnapshot() {
        let node = DesignNode(kind: .rectangle)
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        s.selection = [node.id]
        s.beginGesture(); s.moveSelection(by: CGSize(width: 40, height: 20))
        #expect(s.isDirty)
        s.cancelGesture()
        #expect(s.document.node(id: node.id)?.frame.origin == .zero)
        #expect(!s.isDirty)
        #expect(!s.history.canUndo)
    }
    @Test func parentAndChildMoveOnceAndUndoOnce() {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 30, height: 40))
        let parent = DesignNode(kind: .frame, children: [child])
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [parent])]))
        s.selection = [parent.id, child.id]
        s.beginGesture(); s.moveSelection(by: CGSize(width: 50, height: 60)); s.commitGesture()
        #expect(s.document.node(id: child.id)?.frame.origin == CGPoint(x: 10, y: 20))
        #expect(s.document.node(id: parent.id)?.frame.origin == CGPoint(x: 50, y: 60))
        s.undo(); #expect(!s.isDirty); #expect(!s.history.canUndo)
    }
    @Test func lockedAncestorBlocksMoveAndZeroDragKeepsClean() {
        let child = DesignNode(kind: .rectangle)
        let parent = DesignNode(kind: .frame, isLocked: true, children: [child])
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [parent])]))
        s.selection = [child.id]; s.beginGesture(); s.moveSelection(by: CGSize(width: 5, height: 8)); s.commitGesture()
        #expect(!s.isDirty)
        s.beginGesture(); s.moveSelection(by: .zero); s.commitGesture(); #expect(!s.history.canUndo)
    }
    @Test func unicodeLayoutAndVectorExport() throws {
        let node = DesignNode(kind: .text, frame: CGRect(x: 0, y: 0, width: 240, height: 80), text: "中文 👩🏽‍💻", fontName: "Missing-Font")
        #expect(TextLayout.measure(node).height > 0)
        let page = DesignPage(nodes: [node])
        let png = try Exporter.png(page: page, bounds: CGRect(x: 0, y: 0, width: 240, height: 80))
        let image = try #require(NSBitmapImageRep(data: png))
        #expect(image.pixelsWide == 240)
        let pdf = try Exporter.pdf(page: page, bounds: CGRect(x: 0, y: 0, width: 240, height: 80))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        #expect(throws: (any Error).self) { try Exporter.png(page: page, bounds: CGRect(x: 0, y: 0, width: 100000, height: 100000)) }
    }
    @Test func inspectionRejectsInvalidArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sketch")
        try Data("not zip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) { try SketchFileInspector.inspect(url) }
        #expect(try Data(contentsOf: url) == Data("not zip".utf8))
    }
    @Test func copiedNestedNodeRetainsWorldPosition() throws {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 30, height: 40))
        let parent = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 200, width: 200, height: 200), children: [child])
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [parent])]))
        s.selection = [child.id]; s.duplicate()
        let copy = try #require(s.selected)
        #expect(copy.frame.origin == CGPoint(x: 130, y: 240))
    }
    @Test func sidebarDuplicateCommitsInlineTextBeforeSnapshotAndKeepsUndoBoundaries() throws {
        let node = DesignNode(kind: .text, text: "A")
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        s.selection = [node.id]
        let canvas = CanvasView(session: s)
        canvas.beginText(node.id)
        let editor = try #require(canvas.editor)
        editor.string = "B"
        #expect(s.document.node(id: node.id)?.text == "A")

        s.duplicate() // Same direct session operation as the sidebar button.

        let copy = try #require(s.selected)
        #expect(copy.id != node.id)
        #expect(canvas.editor == nil)
        #expect(s.document.node(id: node.id)?.text == "B")
        #expect(copy.text == "B")
        s.undo()
        #expect(s.page.nodes.count == 1)
        #expect(s.document.node(id: copy.id) == nil)
        #expect(s.document.node(id: node.id)?.text == "B")
        s.undo()
        #expect(s.document.node(id: node.id)?.text == "A")
        #expect(!s.history.canUndo)
        #expect(!s.isDirty)
    }
    @Test func textWithoutFillStaysInvisibleInCanvasPNGAndPDFButStillMeasures() throws {
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 80)
        let defaultText = DesignNode(kind: .text, frame: bounds, text: "Visible text")
        var unfilledText = defaultText
        unfilledText.style.fill = nil
        // Text stroke is intentionally unsupported, including when the fill is absent.
        unfilledText.style.stroke = .black
        unfilledText.style.strokeWidth = 4
        #expect(defaultText.style.fill == .black)
        #expect(TextLayout.measure(unfilledText) == TextLayout.measure(defaultText))
        #expect(TextLayout.measure(unfilledText).height > 0)

        for node in [defaultText, unfilledText] {
            let page = DesignPage(nodes: [node])
            let canvas = try bitmap(size: bounds.size) { CanvasRenderer.draw(page: page, in: $0) }
            let png = try #require(NSBitmapImageRep(data: Exporter.png(page: page, bounds: bounds)))
            let pdfData = try Exporter.pdf(page: page, bounds: bounds)
            let provider = try #require(CGDataProvider(data: pdfData as CFData))
            let pdfDocument = try #require(CGPDFDocument(provider))
            let pdfPage = try #require(pdfDocument.page(at: 1))
            let pdf = try bitmap(size: bounds.size) { $0.drawPDFPage(pdfPage) }
            for image in [canvas, png, pdf] {
                #expect(hasVisiblePixels(image) == (node.style.fill != nil))
            }
        }
    }
    @Test func oversizedRoundedRectangleDrawsUniformClampedCorners() throws {
        let node = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 200, height: 20),
                              style: NodeStyle(fill: .black, cornerRadius: 100))
        let page = DesignPage(nodes: [node])
        let png = try Exporter.png(page: page, bounds: node.frame)
        let image = try #require(NSBitmapImageRep(data: png))
        #expect(SceneGeometry.hitTest(CGPoint(x: 20, y: 2), in: page) == node.id)
        #expect(try #require(image.colorAt(x: 20, y: 2)).alphaComponent > 0.99)
        #expect(SceneGeometry.hitTest(CGPoint(x: 1, y: 1), in: page) == nil)
        #expect(try #require(image.colorAt(x: 1, y: 1)).alphaComponent < 0.01)
    }

    private func bitmap(size: CGSize, draw: (CGContext) -> Void) throws -> NSBitmapImageRep {
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try #require(NSGraphicsContext(bitmapImageRep: image))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = graphics.cgContext
        context.clear(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(context)
        return image
    }
    private func hasVisiblePixels(_ image: NSBitmapImageRep) -> Bool {
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide where (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 { return true }
        }
        return false
    }
    @Test func documentUndoMenuRoutesPastWindowUndoManagerFromCanvas() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu, previousResponder = app.nextResponder
        defer { app.mainMenu = previousMenu; app.nextResponder = previousResponder }
        let controller = AppController()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.window = window
        let canvas = CanvasView(session: controller.session)
        window.contentView = canvas
        #expect(window.makeFirstResponder(canvas))
        controller.makeMenus()
        let edit = try #require(app.mainMenu?.item(withTitle: "编辑")?.submenu)
        let undo = try #require(edit.item(withTitle: "撤销"))
        let redo = try #require(edit.item(withTitle: "重做"))
        let node = DesignNode(kind: .rectangle)
        controller.session.insert([node])
        #expect(window.undoManager?.canUndo == false)
        #expect(controller.validateMenuItem(undo))
        #expect(!controller.validateMenuItem(redo))
        // A nil-target menu action reaches the window's native undo implementation first.
        #expect(undo.target === controller)
        #expect((undo.target as? NSResponder ?? window).tryToPerform(try #require(undo.action), with: undo))
        #expect(controller.session.page.nodes.isEmpty)
        #expect(!controller.validateMenuItem(undo))
        #expect(controller.validateMenuItem(redo))
        #expect(redo.target === controller)
        #expect((redo.target as? NSResponder ?? window).tryToPerform(try #require(redo.action), with: redo))
        #expect(controller.session.page.nodes.map(\.id) == [node.id])
        #expect(undo.keyEquivalent == "z")
        #expect(undo.keyEquivalentModifierMask == [.command])
        #expect(redo.keyEquivalent == "z")
        #expect(redo.keyEquivalentModifierMask == [.command, .shift])
    }
    @Test(arguments: [false, true]) func undoMenuPreservesNativeTextAndFieldEditorHistory(fieldEditor: Bool) throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu, previousResponder = app.nextResponder
        defer { app.mainMenu = previousMenu; app.nextResponder = previousResponder }
        let controller = AppController()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.window = window
        let textView: NSTextView
        if fieldEditor {
            let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
            window.contentView = field
            field.selectText(nil)
            textView = try #require(field.currentEditor() as? NSTextView)
            #expect(textView.isFieldEditor)
        } else {
            textView = InlineTextView(frame: window.contentView!.bounds)
            window.contentView = textView
            #expect(window.makeFirstResponder(textView))
        }
        textView.allowsUndo = true
        controller.makeMenus()
        let edit = try #require(app.mainMenu?.item(withTitle: "编辑")?.submenu)
        let undo = try #require(edit.item(withTitle: "撤销"))
        let redo = try #require(edit.item(withTitle: "重做"))
        controller.session.insert([DesignNode(kind: .rectangle)])
        let document = controller.session.document
        let manager = try #require(textView.undoManager)
        manager.removeAllActions()
        #expect(!controller.validateMenuItem(undo)) // Document history must not leak into text editing.
        textView.string = "A"
        textView.insertText("B", replacementRange: NSRange(location: 0, length: 1))
        #expect(manager.canUndo)
        #expect(controller.validateMenuItem(undo))
        controller.undo(undo)
        #expect(textView.string == "A")
        #expect(controller.session.document == document)
        #expect(controller.validateMenuItem(redo))
        controller.redo(redo)
        #expect(textView.string == "B")
        #expect(controller.session.document == document)
    }
    @Test(arguments: [false, true]) func inlineCommandReturnCommitsUnicodeAsOneTransaction(keyEquivalent: Bool) throws {
        _ = NSApplication.shared
        let node = DesignNode(kind: .text, text: "A")
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        let canvas = CanvasView(session: session)
        canvas.beginText(node.id)
        let editor = try #require(canvas.editor)
        editor.string = "你好，openSketch 👩🏽‍💻"
        let event = try keyEvent(code: 36, characters: "\r", modifiers: .command)
        if keyEquivalent { #expect(editor.performKeyEquivalent(with: event)) }
        else { editor.keyDown(with: event) }
        #expect(canvas.editor == nil)
        #expect(session.document.node(id: node.id)?.text == "你好，openSketch 👩🏽‍💻")
        #expect(session.history.canUndo)
        session.undo()
        #expect(session.document.node(id: node.id)?.text == "A")
        #expect(!session.history.canUndo)
        #expect(!session.isDirty)
    }
    @Test func inlineEscapeCancelsUnicodeEditWithoutHistoryEntry() throws {
        _ = NSApplication.shared
        let node = DesignNode(kind: .text, text: "A")
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        let canvas = CanvasView(session: session)
        canvas.beginText(node.id)
        let editor = try #require(canvas.editor)
        editor.string = "取消 👩🏽‍💻"
        editor.keyDown(with: try keyEvent(code: 53, characters: "\u{1b}"))
        #expect(canvas.editor == nil)
        #expect(session.document.node(id: node.id)?.text == "A")
        #expect(!session.history.canUndo)
        #expect(!session.isDirty)
    }
    @Test func inlineMarkedTextRetainsNativeCompositionBeforeCommandReturnCommit() throws {
        _ = NSApplication.shared
        let node = DesignNode(kind: .text, text: "A")
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        let canvas = CanvasView(session: session)
        canvas.beginText(node.id)
        let editor = try #require(canvas.editor)
        editor.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 1))
        #expect(editor.hasMarkedText())
        let event = try keyEvent(code: 36, characters: "\r", modifiers: .command)
        _ = editor.performKeyEquivalent(with: event)
        #expect(canvas.editor != nil)
        #expect(session.document.node(id: node.id)?.text == "A")
        #expect(!session.history.canUndo)
        editor.unmarkText()
        #expect(editor.performKeyEquivalent(with: event))
        #expect(canvas.editor == nil)
        #expect(session.document.node(id: node.id)?.text == "你")
    }
    private func keyEvent(code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }
    @Test func groupOpacityCompositesOverlappingChildrenOnce() throws {
        let red = NodeStyle(fill: RGBAColor(red: 1, green: 0, blue: 0))
        let a = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 60, height: 40), style: red)
        let b = DesignNode(kind: .rectangle, frame: CGRect(x: 30, y: 0, width: 60, height: 40), style: red)
        let group = DesignNode(kind: .group, style: NodeStyle(opacity: 0.5), children: [a,b])
        let data = try Exporter.png(page: DesignPage(nodes: [group]), bounds: CGRect(x: 0, y: 0, width: 100, height: 40))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let outside = try #require(bitmap.colorAt(x: 10, y: 20))
        let overlap = try #require(bitmap.colorAt(x: 40, y: 20))
        #expect(abs(outside.alphaComponent - 0.5) < 0.02)
        #expect(abs(overlap.alphaComponent - outside.alphaComponent) < 0.01)
    }
    @Test func actualZipMetadataSuccessAndOversizeRejection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let meta = folder.appendingPathComponent("meta.json")
        try Data(#"{"version":196,"appVersion":"2026.1","build":12,"compatibilityVersion":99}"#.utf8).write(to: meta)
        func zip(_ name: String) throws -> URL {
            let output = folder.appendingPathComponent(name + ".sketch")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); process.currentDirectoryURL = folder; process.arguments = ["-q",output.path,"meta.json"]; try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0); return output
        }
        let valid = try zip("valid"); #expect(try SketchFileInspector.inspect(valid).version == 196)
        try Data(repeating: 32, count: 1_048_577).write(to: meta)
        let oversized = try zip("oversized")
        #expect(throws: (any Error).self) { try SketchFileInspector.inspect(oversized) }
    }

    @Test func pageUndoReconcilesActivePageBeforeInsertion() {
        let s = EditorSession(); let firstPage = s.pageID
        s.addPage(); s.undo()
        #expect(s.pageID == firstPage)
        s.beginGesture(); #expect(s.create(DesignNode(name: "新建图形", kind: .rectangle))); s.commitGesture()
        #expect(s.page.nodes.count == 1)
        s.undo(); #expect(s.page.nodes.isEmpty)
        s.insert([DesignNode(name: "粘贴", kind: .rectangle)])
        #expect(s.page.nodes.count == 1)
        #expect(s.selected?.name == "粘贴")
        s.undo(); s.redo()
        #expect(s.document.pages.contains { $0.id == s.pageID })
        #expect(s.page.nodes.count == 1)
    }
    @Test func copiedCompositionKeepsOrderedSiblings() {
        let nodes = ["底层", "中层", "顶层"].map { DesignNode(name: $0, kind: .rectangle) }
        let s = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: nodes)]))
        s.selection = [nodes[2].id, nodes[0].id, nodes[1].id]
        #expect(s.detachedSelection().map(\.name) == ["底层", "中层", "顶层"])
        s.duplicate()
        #expect(s.page.nodes.suffix(3).map(\.name) == ["底层", "中层", "顶层"])
    }
    @Test func roundedPixelAllocationMustFitBudget() {
        #expect(throws: (any Error).self) { try Exporter.validate(CGRect(x: 0, y: 0, width: 8000.01, height: 7999.99)) }
    }

    @Test func selectionGeometryRespectsHiddenClippedAndStrokedNodes() throws {
        let child = DesignNode(kind: .rectangle, frame: CGRect(x: 80, y: 10, width: 40, height: 30), style: NodeStyle(fill: .white, stroke: .black, strokeWidth: 10))
        var parent = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 100, height: 100), clipsContent: true, children: [child])
        let geometry = try #require(CanvasRenderer.selectionGeometry(id: child.id, page: DesignPage(nodes: [parent])))
        #expect(geometry.localBounds == CGRect(x: -5, y: -5, width: 50, height: 40))
        #expect(geometry.visibleBounds == CGRect(x: 75, y: 5, width: 25, height: 40))
        parent.isVisible = false
        #expect(CanvasRenderer.selectionGeometry(id: child.id, page: DesignPage(nodes: [parent])) == nil)
    }

    @Test func exampleIsOriginalEditableDocument() throws {
        let document = EditorSession.exampleDocument()
        let restored = try DocumentCodec.decode(DocumentCodec.encode(document))
        #expect(restored.pages.count == 1)
        #expect(restored.pages[0].nodes.first?.kind == .frame)
        #expect(SceneGeometry.traversal(in: restored.pages[0]).contains { $0.kind == .text && $0.text.contains("你好") })
    }
    @Test func failedInsertionKeepsSelectionAndDocument() {
        let s = EditorSession(); let node = DesignNode(kind: .rectangle)
        s.insert([node]); let before = s.document; let selected = s.selection
        s.insert([node])
        #expect(s.document == before); #expect(s.selection == selected)
        #expect(s.message.contains("无法插入"))
    }

}

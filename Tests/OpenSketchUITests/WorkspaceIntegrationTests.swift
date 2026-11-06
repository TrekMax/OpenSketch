import Testing
import AppKit
import SwiftUI
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct WorkspaceIntegrationTests {
    @Test func newDocumentKeepsTheOriginalSessionAndViewport() {
        let controller = makeController()
        let first = controller.session
        first.zoom = 2.5
        first.pan = CGPoint(x: 210, y: 90)

        controller.newDocument(nil)

        #expect(controller.session !== first)
        #expect(first.zoom == 2.5)
        #expect(first.pan == CGPoint(x: 210, y: 90))
    }

    @Test func exampleOpensInANewSessionAndRetainsTheInitialDocument() {
        let controller = makeController()
        let first = controller.session
        let original = first.document

        controller.openExample(nil)

        #expect(controller.session !== first)
        #expect(first.document == original)
        #expect(!first.isDirty)
        #expect(controller.session.document.name == "示例设计")
        #expect(controller.session.isDirty)
    }

    @Test func openRetainsAllFilesBeforeAWindowExists() throws {
        _ = NSApplication.shared
        let controller = AppController()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstURL = folder.appendingPathComponent("一.opensketch")
        let secondURL = folder.appendingPathComponent("二.opensketch")
        try DocumentCodec.save(DesignDocument(name: "一"), to: firstURL)
        try DocumentCodec.save(DesignDocument(name: "二"), to: secondURL)

        controller.openURL(firstURL)
        let first = controller.session
        controller.openURL(secondURL)

        #expect(controller.workspace.documents.count == 3)
        #expect(first.document.name == "一")
        #expect(controller.session.document.name == "二")
        #expect(controller.session !== first)
    }

    @Test func closeShortcutTargetsTheCurrentDocumentController() throws {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu, previousResponder = app.nextResponder
        defer { app.mainMenu = previousMenu; app.nextResponder = previousResponder }
        let controller = makeController()
        controller.makeMenus()
        let file = try #require(app.mainMenu?.item(withTitle: "文件")?.submenu)
        let close = try #require(file.items.first { $0.keyEquivalent == "w" })
        #expect(close.target === controller)
        #expect(close.action != #selector(NSWindow.performClose(_:)))
    }

    @Test(arguments: [false, true]) func exportKeepsTheDocumentThatOpenedTheDestinationPanel(pdf: Bool) throws {
        let controller = makeController()
        let first = controller.workspace.current
        first.session.insert([DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 90, height: 40))])
        controller.newDocument(nil)
        let second = controller.workspace.current
        second.session.insert([DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 180, height: 80))])
        controller.selectDocument(first.id)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let filename = pdf ? "目标.pdf" : "目标.png"
        let url = folder.appendingPathComponent(filename)

        controller.export(pdf: pdf, chooseDestination: {
            controller.selectDocument(second.id)
            return url
        })

        let data = try Data(contentsOf: url)
        if pdf {
            let provider = try #require(CGDataProvider(data: data as CFData))
            let page = try #require(CGPDFDocument(provider)?.page(at: 1))
            #expect(page.getBoxRect(.mediaBox).size == CGSize(width: 90, height: 40))
        } else {
            let image = try #require(NSBitmapImageRep(data: data))
            #expect(image.pixelsWide == 90)
            #expect(image.pixelsHigh == 40)
        }
        #expect(first.session.message == "已导出 \(filename)")
        #expect(second.session.message != "已导出 \(filename)")
    }

    @Test func toolbarContainsDocumentTabsThatStayBoundedOnResize() throws {
        let controller = makeController()
        let toolbar = NSToolbar(identifier: "workspace-test")
        let tabs = try #require(controller.toolbar(toolbar, itemForItemIdentifier: .init("document.tabs"), willBeInsertedIntoToolbar: true))
        let view = try #require(tabs.view)
        #expect(view.frame.width > 0)
        #expect(view.frame.width < controller.window.frame.width - 300)
        let originalWidth = view.frame.width
        controller.window.setContentSize(CGSize(width: 980, height: 700))
        #expect(view.frame.width < originalWidth)
        #expect(view.frame.width >= 160)
    }

    @Test func hostedCanvasChangesIdentityWhenTheActiveDocumentChanges() throws {
        let controller = makeController()
        let first = controller.workspace.current
        let host = NSHostingView(rootView: EditorRootView(workspace: controller.workspace, appearance: controller.appearance))
        controller.window.contentView = host
        host.layoutSubtreeIfNeeded()
        let firstCanvas = try #require(canvas(in: host))
        #expect(firstCanvas.session === first.session)
        controller.newDocument(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        let secondCanvas = try #require(canvas(in: host))
        #expect(secondCanvas !== firstCanvas)
        #expect(secondCanvas.session === controller.session)
        controller.selectDocument(first.id)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        #expect(try #require(canvas(in: host)).session === first.session)
    }

    @Test func switchingCommitsInlineTextAndRoutesUndoToTheCurrentDocument() throws {
        let controller = makeController()
        let first = controller.workspace.current
        let text = DesignNode(kind: .text, text: "A")
        first.session.insert([text])
        controller.newDocument(nil)
        let second = controller.workspace.current
        let rectangle = DesignNode(kind: .rectangle)
        second.session.insert([rectangle])
        controller.selectDocument(first.id)
        let canvas = CanvasView(session: first.session)
        controller.window.contentView = canvas
        canvas.beginText(text.id)
        let editor = try #require(canvas.editor)
        editor.string = "中文 B"

        controller.selectDocument(second.id)

        #expect(canvas.editor == nil)
        #expect(controller.window.firstResponder !== editor)
        #expect(first.session.document.node(id: text.id)?.text == "中文 B")
        controller.undo(nil)
        #expect(second.session.page.nodes.isEmpty)
        #expect(first.session.document.node(id: text.id)?.text == "中文 B")
        controller.selectDocument(first.id)
        controller.undo(nil)
        #expect(first.session.document.node(id: text.id)?.text == "A")
        #expect(second.session.page.nodes.isEmpty)
    }

    @Test func switchingResignsNativeFieldEditorBeforeDocumentUndo() throws {
        let controller = makeController()
        let first = controller.workspace.current
        first.session.insert([DesignNode(kind: .rectangle)])
        controller.newDocument(nil)
        let second = controller.workspace.current
        second.session.insert([DesignNode(kind: .ellipse)])
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        controller.window.contentView = field
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.allowsUndo = true
        editor.string = "A"
        editor.insertText("B", replacementRange: NSRange(location: 0, length: 1))
        #expect(editor.undoManager?.canUndo == true)

        controller.selectDocument(first.id)
        controller.undo(nil)

        #expect(controller.window.firstResponder !== editor)
        #expect(first.session.page.nodes.isEmpty)
        #expect(second.session.page.nodes.count == 1)
        #expect(field.stringValue == "B")
    }

    @Test func duplicateOpenKeepsUnsavedEditsAndAllFinderFilesAreRetained() throws {
        let controller = makeController()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstURL = folder.appendingPathComponent("一.opensketch")
        let secondURL = folder.appendingPathComponent("二.opensketch")
        try DocumentCodec.save(DesignDocument(name: "一"), to: firstURL)
        try DocumentCodec.save(DesignDocument(name: "二"), to: secondURL)
        controller.application(NSApplication.shared, openFiles: [firstURL.path, secondURL.path])
        #expect(controller.workspace.documents.count == 3)
        let second = controller.workspace.current
        second.session.insert([DesignNode(kind: .rectangle)])
        controller.selectDocument(controller.workspace.documents[1].id)
        controller.openURL(secondURL)
        #expect(controller.workspace.documents.count == 3)
        #expect(controller.workspace.currentID == second.id)
        #expect(second.session.page.nodes.count == 1)
        #expect(second.session.isDirty)
    }

    @Test func savingDuringADestinationChangeKeepsTheOriginalTarget() throws {
        let controller = makeController()
        let first = controller.workspace.current
        first.session.change { $0.name = "应保存的文档" }
        controller.newDocument(nil)
        let second = controller.workspace.current
        second.session.change { $0.name = "保留未保存" }
        controller.selectDocument(first.id)
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("保存目标.opensketch")

        let saved = controller.saveDocument(forcePanel: true, chooseDestination: { target in
            #expect(target.id == first.id)
            controller.selectDocument(second.id)
            return url
        })

        #expect(saved)
        #expect(try DocumentCodec.load(from: url).name == "应保存的文档")
        #expect(first.session.url == url)
        #expect(!first.session.isDirty)
        #expect(second.session.url == nil)
        #expect(second.session.isDirty)
    }

    @Test func saveAsRefusesAnotherOpenDocumentsCanonicalPath() throws {
        let controller = makeController()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("已打开.opensketch")
        try DocumentCodec.save(DesignDocument(name: "磁盘原文档"), to: url)
        controller.openURL(url)
        let opened = controller.workspace.current
        controller.newDocument(nil)
        let target = controller.workspace.current
        target.session.change { $0.name = "不得覆盖" }
        let alias = folder.appendingPathComponent("别名")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)

        #expect(throws: (any Error).self) {
            try controller.writeDocument(target, to: alias.appendingPathComponent("已打开.opensketch"))
        }
        #expect(try DocumentCodec.load(from: url).name == "磁盘原文档")
        #expect(target.session.url == nil)
        #expect(target.session.isDirty)
        #expect(opened.session.document.name == "磁盘原文档")
    }

    @Test func backgroundClosePromptsForItsTargetAndCancelRetainsEverything() {
        let controller = makeController()
        let first = controller.workspace.current
        first.session.insert([DesignNode(kind: .rectangle)])
        controller.newDocument(nil)
        let second = controller.workspace.current
        second.session.insert([DesignNode(kind: .ellipse)])
        var prompted: [UUID] = []
        controller.closeDecision = { target in prompted.append(target.id); return .cancel }

        #expect(!controller.closeDocuments([first.id]))
        #expect(prompted == [first.id])
        #expect(controller.workspace.documents.map(\.id) == [first.id, second.id])
        #expect(controller.workspace.currentID == second.id)
    }

    @Test func windowCloseAndQuitAreTransactionalAcrossAllDocuments() {
        let controller = makeController()
        let first = controller.workspace.current
        first.session.insert([DesignNode(kind: .rectangle)])
        controller.newDocument(nil)
        let second = controller.workspace.current
        second.session.insert([DesignNode(kind: .ellipse)])
        var prompted: [UUID] = []
        controller.closeDecision = { target in
            prompted.append(target.id)
            return target.id == first.id ? .discard : .cancel
        }

        #expect(!controller.windowShouldClose(controller.window))
        #expect(prompted == [first.id, second.id])
        #expect(controller.workspace.documents.map(\.id) == [first.id, second.id])
        prompted = []
        #expect(controller.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        #expect(prompted == [first.id, second.id])
        #expect(controller.workspace.currentID == second.id)
        controller.closeDecision = { _ in .discard }
        #expect(controller.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(controller.workspace.isPlaceholder)
    }

    @Test func closingBackgroundDocumentSavesThatDocumentAndKeepsCurrentUnsaved() throws {
        let controller = makeController()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = controller.workspace.current
        let url = folder.appendingPathComponent("后台.opensketch")
        first.session.url = url
        first.session.change { $0.name = "后台更改" }
        controller.newDocument(nil)
        let second = controller.workspace.current
        second.session.insert([DesignNode(kind: .rectangle)])
        controller.closeDecision = { _ in .save }

        #expect(controller.closeDocuments([first.id]))
        #expect(try DocumentCodec.load(from: url).name == "后台更改")
        #expect(controller.workspace.documents.map(\.id) == [second.id])
        #expect(controller.workspace.currentID == second.id)
        #expect(second.session.isDirty)
    }

    @Test func closingLastTabHidesWindowAndReopenConsumesTheFreshPlaceholder() {
        let controller = makeController()
        let originalID = controller.workspace.currentID
        controller.closeCurrentDocument(nil)
        #expect(controller.workspace.isPlaceholder)
        #expect(controller.workspace.currentID != originalID)
        #expect(!controller.window.isVisible)
        let freshID = controller.workspace.currentID
        #expect(controller.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        #expect(!controller.workspace.isPlaceholder)
        #expect(controller.workspace.currentID == freshID)
        controller.newDocument(nil)
        #expect(controller.workspace.documents.count == 2)
    }

    @Test func exampleFitsItsNewCanvasAfterItAppears() throws {
        let controller = makeController()
        let host = NSHostingView(rootView: EditorRootView(workspace: controller.workspace, appearance: controller.appearance))
        controller.window.contentView = host
        host.layoutSubtreeIfNeeded()
        _ = try #require(canvas(in: host))
        controller.openExample(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        let activeCanvas = try #require(canvas(in: host))
        let frame = try #require(controller.session.page.nodes.first)
        let center = CGPoint(x: frame.frame.midX * controller.session.zoom + controller.session.pan.x,
                             y: frame.frame.midY * controller.session.zoom + controller.session.pan.y)
        #expect(abs(center.x - activeCanvas.bounds.midX) < 1)
        #expect(abs(center.y - activeCanvas.bounds.midY) < 1)
        let example = controller.workspace.current
        example.session.zoom = 2.5
        example.session.pan = CGPoint(x: 310, y: 170)
        activeCanvas.needsLayout = true
        activeCanvas.layoutSubtreeIfNeeded()
        #expect(example.session.zoom == 2.5)
        #expect(example.session.pan == CGPoint(x: 310, y: 170))
        controller.newDocument(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        controller.selectDocument(example.id)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        #expect(example.session.zoom == 2.5)
        #expect(example.session.pan == CGPoint(x: 310, y: 170))
    }

    @Test func nativeToolbarCommandsUseTheSelectedDocument() throws {
        let controller = makeController()
        let first = controller.workspace.current
        first.session.zoom = 2
        first.session.insert([DesignNode(kind: .rectangle)])
        let toolbar = NSToolbar(identifier: "workspace-test")
        let newItem = try #require(controller.toolbar(toolbar, itemForItemIdentifier: .init("document.new"), willBeInsertedIntoToolbar: true))
        let newButton = try #require(newItem.view as? NSButton)
        newButton.performClick(nil)
        let second = controller.workspace.current
        #expect(second.id != first.id)
        #expect(first.session.page.nodes.count == 1)
        second.session.zoom = 4
        controller.selectDocument(first.id)
        let sizeItem = try #require(controller.toolbar(toolbar, itemForItemIdentifier: .init("view.zoomSlider"), willBeInsertedIntoToolbar: true))
        let host = try #require(sizeItem.view as? NSHostingView<ZoomControlView>)
        #expect(host.rootView.workspace === controller.workspace)
        controller.actualSize(nil)
        #expect(first.session.zoom == 1)
        #expect(second.session.zoom == 4)
        controller.selectDocument(second.id)
        controller.actualSize(nil)
        #expect(second.session.zoom == 1)
    }

    @Test func cancelledSavePreservesTheDocumentAndItsDirtyHistory() {
        let controller = makeController()
        let target = controller.workspace.current
        target.session.insert([DesignNode(kind: .rectangle)])
        let document = target.session.document
        #expect(!controller.saveDocument(forcePanel: true, chooseDestination: { _ in nil }))
        #expect(controller.workspace.documents.map(\.id) == [target.id])
        #expect(target.session.document == document)
        #expect(target.session.url == nil)
        #expect(target.session.isDirty)
        #expect(target.session.history.canUndo)
    }

    private func canvas(in view: NSView) -> CanvasView? {
        if let canvas = view as? CanvasView { return canvas }
        return view.subviews.lazy.compactMap { canvas(in: $0) }.first
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeController() -> AppController {
        _ = NSApplication.shared
        let controller = AppController()
        let window = WorkspaceTestWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.window = window
        window.delegate = controller
        return controller
    }
}

@MainActor private final class WorkspaceTestWindow: NSWindow {
    override func makeKeyAndOrderFront(_ sender: Any?) {}
}

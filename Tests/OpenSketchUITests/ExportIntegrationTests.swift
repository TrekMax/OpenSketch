import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct ExportIntegrationTests {
    @Test(arguments: [false, true])
    func destinationChangesCannotChangeTheCapturedGeometry(pdf: Bool) throws {
        let controller = makeController()
        defer { controller.window.close() }
        let target = controller.workspace.current
        let node = DesignNode(name: "图标", kind: .rectangle, frame: CGRect(x: 10, y: 20, width: 37, height: 19))
        target.session.replace(DesignDocument(pages: [DesignPage(nodes: [node])]))
        target.session.selection = [node.id]
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(pdf ? "快照.pdf" : "快照.png")
        controller.export(pdf: pdf, chooseDestination: {
            target.session.document.updateNode(id: node.id) { $0.frame.size = CGSize(width: 200, height: 100) }
            target.session.selection = []
            target.session.exportOptions = ExportOptions(format: .pdf, scope: .page, scale: 3)
            controller.workspace.newDocument()
            return url
        })
        #expect(try outputSize(at: url, pdf: pdf) == CGSize(width: 37, height: 19))
        #expect(target.session.message == "已导出 \(url.lastPathComponent)")
        #expect(controller.session.message != target.session.message)
    }

    @Test func optionsAreSessionLocalAndNeverEnterDocumentHistory() throws {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        let original = first.session.document
        first.session.exportOptions = ExportOptions(format: .pdf, scope: .page, scale: 3)
        let second = workspace.newDocument()
        #expect(second.session.exportOptions == ExportOptions())
        workspace.select(first.id)
        #expect(first.session.exportOptions == ExportOptions(format: .pdf, scope: .page, scale: 3))
        #expect(first.session.document == original)
        #expect(!first.session.isDirty)
        #expect(!first.session.canUndo)
    }

    @Test func previewResolvesEmptySelectionWithoutOverwritingExplicitScope() throws {
        let node = DesignNode(kind: .rectangle, frame: CGRect(x: 100, y: 10, width: 23, height: 17))
        let sibling = DesignNode(kind: .rectangle, frame: CGRect(x: 300, y: 50, width: 70, height: 20))
        let page = DesignPage(name: "一", nodes: [node, sibling])
        let otherPage = DesignPage(name: "二", size: CGSize(width: 333, height: 222))
        let session = EditorSession(document: DesignDocument(pages: [page, otherPage]))
        let whole = try session.prepareExport().snapshot.bounds
        #expect(whole.size == CGSize(width: 270, height: 60))
        #expect(session.exportOptions.scope == .selection)
        session.selection = [node.id]
        #expect(try session.prepareExport().dimensions == CGSize(width: 23, height: 17))
        session.exportOptions.scope = .page
        #expect(try session.prepareExport().snapshot.bounds == whole)
        session.selectPage(otherPage.id)
        #expect(try session.prepareExport().dimensions == otherPage.size)
        #expect(session.exportOptions.scope == .page)
    }

    @Test func lockedSelectionExportsWhileHiddenSelectionShowsAReason() throws {
        var node = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 31, height: 21))
        node.isLocked = true
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        #expect(try session.prepareExport().dimensions == CGSize(width: 31, height: 21))
        session.document.updateNode(id: node.id) { $0.isVisible = false }
        #expect(throws: (any Error).self) { try session.prepareExport() }
    }

    @Test(arguments: [false, true])
    func sharedActionUsesSessionScaleAndMenuFormatOverride(pdf: Bool) throws {
        let controller = makeController()
        defer { controller.window.close() }
        let session = controller.session
        let node = DesignNode(name: "画板", kind: .frame, frame: CGRect(x: 20, y: 30, width: 29.5, height: 13.5))
        session.replace(DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        session.exportOptions = ExportOptions(format: pdf ? .png : .pdf, scale: 3)
        let original = session.document
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(pdf ? "倍率.pdf" : "倍率.png")
        let preview = try session.prepareExport(format: pdf ? .pdf : .png)
        #expect(preview.dimensions == (pdf ? CGSize(width: 29.5, height: 13.5) : CGSize(width: 89, height: 41)))
        #expect(preview.filename == (pdf ? "画板.pdf" : "画板@3x.png"))
        controller.export(pdf: pdf, chooseDestination: { url })
        #expect(try outputSize(at: url, pdf: pdf) == preview.dimensions)
        #expect(session.document == original)
        #expect(!session.isDirty)
        #expect(!session.canUndo)
        #expect(session.exportOptions.format == (pdf ? .png : .pdf))
        #expect(session.exportOptions.scale == 3)
    }

    @Test(arguments: [false, true])
    func exportFinishesNativeNumberInputAndCancellationPreservesDocumentURL(writeFile: Bool) throws {
        let controller = makeController()
        defer { controller.window.close() }
        let session = controller.session
        let node = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        session.replace(DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        let control = InspectorNumberControl(frame: CGRect(x: 0, y: 0, width: 100, height: 26))
        controller.window.contentView = control
        control.configure(session: session, nodeID: node.id, property: .width)
        control.field.selectText(nil)
        let editor = try #require(control.field.currentEditor() as? NSTextView)
        editor.insertText("47", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let message = session.message
        let url = folder.appendingPathComponent("数值.png")
        controller.export(pdf: false, chooseDestination: {
            #expect(session.document.node(id: node.id)?.frame.width == 47)
            return writeFile ? url : nil
        })
        if writeFile { #expect(try outputSize(at: url, pdf: false) == CGSize(width: 47, height: 10)) }
        else { #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty) }
        #expect(session.url == nil)
        #expect(session.message == (writeFile ? "已导出 数值.png" : message))
        #expect(session.inspectorEdit == nil)
        #expect(session.isDirty)
        session.undo()
        #expect(session.document.node(id: node.id)?.frame.width == 20)
        #expect(!session.canUndo)
    }

    @Test func sharedActionCommitsCanvasTextBeforeCapturingAndKeepsCoordinator() throws {
        let controller = makeController()
        defer { controller.window.close() }
        let session = controller.session
        let node = DesignNode(kind: .text, frame: CGRect(x: 0, y: 0, width: 60, height: 30), text: "A")
        session.replace(DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        let canvas = CanvasView(session: session)
        controller.window.contentView = canvas
        canvas.beginText(node.id)
        let editor = try #require(canvas.editor)
        editor.string = "中文 B"
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("文字.png")
        controller.export(documentID: controller.workspace.currentID, chooseDestination: { prepared in
            #expect(prepared.snapshot.page.nodes.first?.text == "中文 B")
            #expect(canvas.editor == nil)
            return url
        })
        #expect(try outputSize(at: url, pdf: false) == CGSize(width: 60, height: 30))
        canvas.beginText(node.id)
        canvas.editor?.string = "下一次"
        session.finishInput?()
        #expect(session.document.node(id: node.id)?.text == "下一次")
    }

    @Test func panelActionTargetsTheExplicitDocumentInsteadOfCurrentWorkspace() throws {
        let controller = makeController()
        defer { controller.window.close() }
        let first = controller.workspace.current
        let node = DesignNode(kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 41, height: 25))
        first.session.replace(DesignDocument(pages: [DesignPage(nodes: [node])]))
        first.session.selection = [node.id]
        first.session.exportOptions.scale = 2
        let second = controller.workspace.newDocument()
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("后台.png")
        controller.export(documentID: first.id, chooseDestination: { _ in url })
        #expect(try outputSize(at: url, pdf: false) == CGSize(width: 82, height: 50))
        #expect(controller.workspace.currentID == second.id)
        #expect(first.session.message == "已导出 后台.png")
        #expect(second.session.message != first.session.message)
    }

    @Test func cancellingAnExportWithoutPendingInputDoesNotChangeHistoryOrURL() throws {
        let controller = makeController()
        defer { controller.window.close() }
        let session = controller.session
        let original = session.document
        let message = session.message
        let originalURL = URL(fileURLWithPath: "/tmp/original.opensketch")
        session.url = originalURL
        controller.export(documentID: controller.workspace.currentID, chooseDestination: { _ in nil })
        #expect(session.document == original)
        #expect(session.url == originalURL)
        #expect(session.message == message)
        #expect(!session.isDirty)
        #expect(!session.canUndo)
    }

    @Test func previewRejectsOversizedPNGAndPDFAlwaysIgnoresPNGScale() throws {
        let node = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 9000, height: 2))
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        session.exportOptions.scale = 3
        #expect(throws: (any Error).self) { try session.prepareExport() }
        session.exportOptions.format = .pdf
        #expect(try session.prepareExport().dimensions == CGSize(width: 9000, height: 2))
        #expect(try session.prepareExport().options.scale == 1)
        #expect(session.exportOptions.scale == 3)
    }

    private func outputSize(at url: URL, pdf: Bool) throws -> CGSize {
        let data = try Data(contentsOf: url)
        if pdf {
            let provider = try #require(CGDataProvider(data: data as CFData))
            return try #require(CGPDFDocument(provider)?.page(at: 1)).getBoxRect(.mediaBox).size
        }
        let image = try #require(NSBitmapImageRep(data: data))
        return CGSize(width: image.pixelsWide, height: image.pixelsHigh)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeController() -> AppController {
        _ = NSApplication.shared
        let controller = AppController()
        let window = ExportTestWindow(contentRect: CGRect(x: -20000, y: -20000, width: 1100, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        controller.window = window
        return controller
    }
}

@MainActor private final class ExportTestWindow: NSWindow {
    override func makeKeyAndOrderFront(_ sender: Any?) {}
}

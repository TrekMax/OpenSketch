import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct SidebarRenameTests {
    @Test func inactivePageRenamePreservesSelectionAndSavesUnicode() throws {
        let node = DesignNode(name: "卡片", kind: .rectangle)
        let first = DesignPage(name: "首页", nodes: [node]), second = DesignPage(name: "页面 2")
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        session.selection = [node.id]
        let original = session.document
        let request = try #require(session.beginSidebarRename(.page(second.id)))
        try session.commitSidebarRename(request, name: "  设置 👩🏽‍💻  ")
        #expect(session.document.pages[1].name == "设置 👩🏽‍💻")
        #expect(session.document.pages[0] == first)
        #expect(session.pageID == first.id && session.selection == [node.id])
        let renamed = session.document
        session.undo(); #expect(session.document == original && !session.history.canUndo)
        session.redo(); #expect(session.document == renamed)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("命名.opensketch")
        try DocumentCodec.save(renamed, to: url)
        #expect(try DocumentCodec.load(from: url) == renamed)
    }

    @Test(arguments: NodeKind.allCases)
    func clickedLayerOnlyChangesItsName(kind: NodeKind) throws {
        let target = DesignNode(name: "原名", kind: kind, isVisible: false, isLocked: true)
        let sibling = DesignNode(name: "其他", kind: .rectangle)
        let group = DesignNode(name: "容器", kind: .group, isLocked: true, children: [target, sibling])
        let page = DesignPage(nodes: [group]), otherPage = DesignPage(name: "另页")
        let session = EditorSession(document: DesignDocument(pages: [page, otherPage]))
        session.selection = [target.id, sibling.id]
        let original = session.document
        let request = try #require(session.beginSidebarRename(.layer(pageID: page.id, nodeID: target.id)))
        try session.commitSidebarRename(request, name: "登录 / 按钮 ✨")
        var expected = target; expected.name = "登录 / 按钮 ✨"
        #expect(session.document.node(id: target.id) == expected)
        #expect(session.document.node(id: sibling.id) == sibling)
        #expect(session.selection == [target.id, sibling.id])
        #expect(session.document.pages[1] == otherPage)
        session.undo(); #expect(session.document == original && !session.history.canUndo)
    }

    @Test func openingCancellingAndUnchangedNamePreserveRedo() throws {
        let session = EditorSession(), id = session.pageID
        let request = try #require(session.beginSidebarRename(.page(id)))
        try session.commitSidebarRename(request, name: "临时名")
        session.undo()
        let original = session.document
        let cancelled = try #require(session.beginSidebarRename(.page(id)))
        #expect(cancelled.originalName == "页面 1")
        #expect(session.document == original && session.history.canRedo && !session.isDirty)
        try session.commitSidebarRename(cancelled, name: "页面 1")
        #expect(session.document == original && session.history.canRedo && !session.history.canUndo)
    }

    @Test(arguments: ["", " \n\t ", "A\nB", "A\u{0}B"])
    func invalidNamesLeaveDocumentAndHistoryUntouched(name: String) throws {
        let session = EditorSession(), original = session.document
        let request = try #require(session.beginSidebarRename(.page(session.pageID)))
        #expect(throws: (any Error).self) { try session.commitSidebarRename(request, name: name) }
        #expect(session.document == original && !session.isDirty && !session.history.canUndo)
    }

    @Test func oversizedNameIsRejectedBeforeMutatingTheDocument() throws {
        let session = EditorSession(), original = session.document
        let request = try #require(session.beginSidebarRename(.page(session.pageID)))
        let oversized = String(repeating: "a", count: DocumentCodec.maximumStringBytes + 1)
        #expect(throws: (any Error).self) { try session.commitSidebarRename(request, name: oversized) }
        #expect(session.document == original && !session.history.canUndo)
    }

    @Test func requestTargetsOriginalPageAfterSelectionChanges() throws {
        let node = DesignNode(name: "目标", kind: .rectangle)
        let page = DesignPage(nodes: [node]), other = DesignPage()
        let session = EditorSession(document: DesignDocument(pages: [page, other]))
        let request = try #require(session.beginSidebarRename(.layer(pageID: page.id, nodeID: node.id)))
        session.selectPage(other.id)
        try session.commitSidebarRename(request, name: "仍是目标")
        #expect(session.pageID == other.id && session.selection.isEmpty)
        #expect(session.document.node(id: node.id)?.name == "仍是目标")
        #expect(session.document.pages[1] == other)
    }

    @Test func deletedMovedReplacedAndConcurrentlyRenamedTargetsAreRejected() throws {
        let node = DesignNode(name: "目标", kind: .rectangle), page = DesignPage()
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node]), page]))
        #expect(session.beginSidebarRename(.page(UUID())) == nil)
        #expect(session.beginSidebarRename(.layer(pageID: page.id, nodeID: node.id)) == nil)
        let request = try #require(session.beginSidebarRename(.layer(pageID: session.pageID, nodeID: node.id)))
        session.document.updateNode(id: node.id) { $0.name = "外部修改" }
        let changed = session.document
        #expect(throws: (any Error).self) { try session.commitSidebarRename(request, name: "迟到的提交") }
        #expect(session.document == changed && !session.history.canUndo)
        session.document.removeNode(id: node.id)
        let removed = session.document
        #expect(throws: (any Error).self) { try session.commitSidebarRename(request, name: "已删") }
        #expect(session.document == removed)
        try session.document.insertNode(node, into: page.id)
        let moved = session.document
        #expect(throws: (any Error).self) { try session.commitSidebarRename(request, name: "已移动") }
        #expect(session.document == moved)
        session.replace(.blank())
        let replacement = session.document
        #expect(throws: (any Error).self) { try session.commitSidebarRename(request, name: "旧文档") }
        #expect(session.document == replacement && !session.history.canUndo)
    }

    @Test func pendingInspectorInputAndRenameHaveSeparateUndo() throws {
        let node = DesignNode(name: "原名", kind: .rectangle)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        session.selection = [node.id]
        let token = try #require(session.beginInspectorEdit(.x, nodeID: node.id))
        session.scrubInspectorNumber(token, translation: 15)
        let request = try #require(session.beginSidebarRename(.layer(pageID: session.pageID, nodeID: node.id)))
        #expect(!session.history.isEditing && session.document.node(id: node.id)?.frame.minX == 15)
        try session.commitSidebarRename(request, name: "新名")
        session.undo()
        #expect(session.document.node(id: node.id)?.name == "原名")
        #expect(session.document.node(id: node.id)?.frame.minX == 15)
        session.undo(); #expect(session.document.node(id: node.id) == node)
    }

    @Test func pendingCanvasTextIsCommittedBeforeRename() throws {
        _ = NSApplication.shared
        let node = DesignNode(name: "文字层", kind: .text, text: "原文字")
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [node])]))
        let canvas = CanvasView(session: session)
        canvas.beginText(node.id)
        try #require(canvas.editor).string = "输入中的文字"
        let request = try #require(session.beginSidebarRename(.layer(pageID: session.pageID, nodeID: node.id)))
        #expect(canvas.editor == nil && session.document.node(id: node.id)?.text == "输入中的文字")
        try session.commitSidebarRename(request, name: "新文字层")
        session.undo()
        #expect(session.document.node(id: node.id)?.name == "文字层")
        #expect(session.document.node(id: node.id)?.text == "输入中的文字")
        session.undo(); #expect(session.document.node(id: node.id) == node)
    }

    @Test func inlineDraftCommitsAtInputBoundaryAndIgnoresLateEvents() throws {
        let session = EditorSession(), original = session.document
        session.startSidebarRename(.page(session.pageID))
        let token = try #require(session.sidebarRename?.request.id)
        session.updateSidebarRename(token, name: "行内页面")
        #expect(session.document == original && !session.isDirty)
        session.finishInput?()
        #expect(session.sidebarRename == nil && session.page.name == "行内页面")
        session.updateSidebarRename(token, name: "迟到输入")
        session.finishSidebarRename(token: token, cancel: true)
        #expect(session.page.name == "行内页面")
        session.undo(); #expect(session.document == original && !session.history.canUndo)
    }

    @Test func inlineCancelAndInvalidCommitPreserveOriginalAndRedo() throws {
        let session = EditorSession()
        let request = try #require(session.beginSidebarRename(.page(session.pageID)))
        try session.commitSidebarRename(request, name: "暂名"); session.undo()
        let original = session.document
        session.startSidebarRename(.page(session.pageID))
        let token = try #require(session.sidebarRename?.request.id)
        session.updateSidebarRename(token, name: "不保存")
        session.finishSidebarRename(token: token, cancel: true)
        #expect(session.document == original && session.history.canRedo)
        session.startSidebarRename(.page(session.pageID))
        session.updateSidebarRename(try #require(session.sidebarRename?.request.id), name: "  ")
        session.finishInput?()
        #expect(session.document == original && session.history.canRedo && session.sidebarRename == nil)
        #expect(session.message.contains(L10n.text("名称不能为空。")))
    }

    @Test(arguments: [false, true]) func nativeInlineFieldEnterAndEscape(cancel: Bool) throws {
        _ = NSApplication.shared
        let session = EditorSession(), original = session.document
        session.startSidebarRename(.page(session.pageID))
        let request = try #require(session.sidebarRename?.request)
        let field = NativeSidebarRenameField(session: session, request: request)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 220, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = field
        defer { window.close() }
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("原行新名", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        #expect(session.document == original)
        #expect(field.control(field, textView: editor, doCommandBy: NSSelectorFromString(cancel ? "cancelOperation:" : "insertNewline:")))
        #expect(session.sidebarRename == nil)
        #expect(session.page.name == (cancel ? "页面 1" : "原行新名"))
        if cancel { #expect(!session.history.canUndo) }
        else { session.undo(); #expect(session.document == original && !session.history.canUndo) }
    }

    @Test func staleNativeFieldCannotReplaceCurrentDraftReader() throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.startSidebarRename(.page(session.pageID))
        let stale = try #require(session.sidebarRename?.request)
        session.finishSidebarRename(cancel: true)
        session.startSidebarRename(.page(session.pageID))
        let current = NativeSidebarRenameField(session: session, request: try #require(session.sidebarRename?.request))
        current.stringValue = "当前名称"
        let late = NativeSidebarRenameField(session: session, request: stale)
        late.stringValue = "过期名称"
        session.finishInput?()
        #expect(session.page.name == "当前名称")
    }

    @Test func nativeInlineFieldInputBoundaryReadsLatestEditorValue() throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.startSidebarRename(.page(session.pageID))
        let request = try #require(session.sidebarRename?.request)
        let field = NativeSidebarRenameField(session: session, request: request)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 220, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = field
        defer { window.close() }
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        // Exercise an input boundary before a text-change notification arrives.
        editor.string = "最新编辑内容"
        session.finishInput?()
        #expect(session.page.name == "最新编辑内容" && session.sidebarRename == nil)
        session.undo(); #expect(session.page.name == "页面 1" && !session.history.canUndo)
    }

    @Test func nativeInlineFieldFocusLossCommitsExactlyOnce() throws {
        _ = NSApplication.shared
        let session = EditorSession()
        session.startSidebarRename(.page(session.pageID))
        let request = try #require(session.sidebarRename?.request)
        let field = NativeSidebarRenameField(session: session, request: request)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 220, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = field
        defer { window.close() }
        field.selectText(nil)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("失焦提交", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        window.makeFirstResponder(nil)
        #expect(session.page.name == "失焦提交" && session.sidebarRename == nil)
        field.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        session.undo(); #expect(session.page.name == "页面 1" && !session.history.canUndo)
    }
}

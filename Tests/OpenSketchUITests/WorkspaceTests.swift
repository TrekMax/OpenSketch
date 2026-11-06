import Testing
import AppKit
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct WorkspaceTests {
    @Test func newDocumentsKeepIndependentContentSelectionViewportAndHistory() {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        let node = DesignNode(kind: .rectangle)
        first.session.change { $0.pages[0].nodes.append(node) }
        first.session.selection = [node.id]
        first.session.zoom = 2
        first.session.pan = CGPoint(x: 120, y: 80)
        first.session.tool = .ellipse

        let second = workspace.newDocument()
        #expect(second.id != first.id)
        #expect(second.session !== first.session)
        #expect(second.title != first.title)
        #expect(workspace.documents.map(\.id) == [first.id, second.id])
        #expect(workspace.currentID == second.id)
        #expect(second.session.page.nodes.isEmpty)
        #expect(second.session.selection.isEmpty)
        #expect(second.session.zoom == 1)
        #expect(!second.session.history.canUndo)
        second.session.change { $0.name = "第二份" }
        second.session.undo()
        #expect(!second.session.isDirty)

        #expect(workspace.select(first.id))
        #expect(workspace.current.session.document.node(id: node.id) != nil)
        #expect(first.session.selection == [node.id])
        #expect(first.session.zoom == 2)
        #expect(first.session.pan == CGPoint(x: 120, y: 80))
        #expect(first.session.tool == .ellipse)
        first.session.undo()
        #expect(first.session.page.nodes.isEmpty)
        #expect(!first.session.isDirty)
        #expect(workspace.currentID == first.id)
    }

    @Test func newFromCleanInitialDocumentAlwaysAddsATab() {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        let second = workspace.newDocument()
        #expect(workspace.documents.count == 2)
        #expect(first.id != second.id)
        #expect(first.title != second.title)
        #expect(!workspace.select(UUID()))
        #expect(workspace.currentID == second.id)
    }

    @Test func switchingAndNewFinishRealInlineTextBeforeChangingCurrentDocument() throws {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        let node = DesignNode(kind: .text, text: "原文")
        first.session.change { $0.pages[0].nodes.append(node) }
        let canvas = CanvasView(session: first.session)
        canvas.beginText(node.id)
        try #require(canvas.editor).string = "新建前提交"
        let second = workspace.newDocument()
        #expect(canvas.editor == nil)
        #expect(first.session.document.node(id: node.id)?.text == "新建前提交")
        #expect(workspace.select(first.id))
        canvas.beginText(node.id)
        try #require(canvas.editor).string = "切换前提交"
        #expect(workspace.select(second.id))
        #expect(canvas.editor == nil)
        #expect(first.session.document.node(id: node.id)?.text == "切换前提交")
        first.session.undo()
        #expect(first.session.document.node(id: node.id)?.text == "新建前提交")
    }

    @Test func openingDeduplicatesCanonicalURLWithoutReloadingEditedDocument() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("设计.opensketch")
        let saved = DesignDocument(name: "磁盘版本")
        try DocumentCodec.save(saved, to: url)
        let workspace = DocumentWorkspace()
        let initial = workspace.current
        initial.session.change { $0.name = "未保存文档" }
        let opened = try workspace.open(url)
        #expect(workspace.documents.map(\.id) == [initial.id, opened.id])
        #expect(opened.session.document == saved)
        #expect(opened.session.url == url)
        #expect(!opened.session.isDirty)
        #expect(opened.title == "设计")
        opened.session.change { $0.name = "内存修改" }
        #expect(workspace.select(initial.id))
        let alternate = directory.appendingPathComponent("子目录/../设计.opensketch")
        let again = try workspace.open(alternate)
        #expect(again.id == opened.id)
        #expect(workspace.currentID == opened.id)
        #expect(workspace.documents.count == 2)
        #expect(again.session.document.name == "内存修改")
        #expect(again.session.isDirty)
        #expect(initial.session.document.name == "未保存文档")
        #expect(workspace.document(matching: alternate, excluding: initial.id)?.id == opened.id)
        #expect(workspace.document(matching: alternate, excluding: opened.id) == nil)
        let alias = directory.appendingPathComponent("别名", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        #expect(try workspace.open(alias.appendingPathComponent("设计.opensketch")).id == opened.id)
        #expect(workspace.documents.count == 2)
        #expect(try DocumentCodec.load(from: url) == saved)
    }

    @Test func failedOpenKeepsCurrentContentAndOrder() throws {
        let workspace = DocumentWorkspace()
        let initial = workspace.current
        initial.session.change { $0.name = "保留我" }
        #expect(throws: (any Error).self) {
            try workspace.open(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        }
        #expect(workspace.currentID == initial.id)
        #expect(workspace.documents.count == 1)
        #expect(initial.session.document.name == "保留我")
        #expect(initial.session.isDirty)
    }

    @Test func cancelAfterDiscardRetainsEveryDocumentAndItsDirtyState() {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        first.session.change { $0.name = "保留一" }
        let second = workspace.newDocument()
        second.session.change { $0.name = "保留二" }
        var visited: [UUID] = []
        let closed = workspace.closeAll(decide: { document in
            visited.append(document.id)
            return document.id == first.id ? .discard : .cancel
        }, save: { _ in Issue.record("取消事务不应保存"); return false })
        #expect(!closed)
        #expect(visited == [first.id, second.id])
        #expect(workspace.documents.map(\.id) == [first.id, second.id])
        #expect(workspace.currentID == second.id)
        #expect(first.session.isDirty)
        #expect(second.session.isDirty)
        #expect(first.session.document.name == "保留一")
    }

    @Test func saveFailureRetainsAllDocumentsIncludingEarlierDiscard() {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        first.session.change { $0.name = "不保存但保留" }
        let second = workspace.newDocument()
        second.session.change { $0.name = "保存失败" }
        var attempted: [UUID] = []
        let closed = workspace.closeAll(decide: { $0.id == first.id ? .discard : .save }, save: {
            attempted.append($0.id)
            return false
        })
        #expect(!closed)
        #expect(attempted == [second.id])
        #expect(workspace.documents.map(\.id) == [first.id, second.id])
        #expect(workspace.currentID == second.id)
        #expect(first.session.isDirty)
        #expect(second.session.isDirty)
    }

    @Test func saveBeforeLaterCancelOnlyMarksSavedDocumentAndKeepsItsUndoHistory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = DocumentWorkspace()
        let first = workspace.current
        first.session.change { $0.name = "已保存" }
        let second = workspace.newDocument()
        second.session.change { $0.name = "取消" }
        let url = directory.appendingPathComponent("已保存.opensketch")
        let closed = workspace.closeAll(decide: { $0.id == first.id ? .save : .cancel }, save: { document in
            do {
                try DocumentCodec.save(document.session.document, to: url)
                document.session.url = url
                return true
            } catch { Issue.record(error); return false }
        })
        #expect(!closed)
        #expect(workspace.documents.map(\.id) == [first.id, second.id])
        #expect(workspace.currentID == second.id)
        #expect(!first.session.isDirty)
        #expect(second.session.isDirty)
        #expect(try DocumentCodec.load(from: url) == first.session.document)
        #expect(first.title == "已保存")
        first.session.undo()
        #expect(first.session.isDirty)
        #expect(second.session.document.name == "取消")
    }

    @Test func closeFinishesInlineTextBeforeDirtyCheckAndCanBeCancelled() throws {
        let workspace = DocumentWorkspace()
        let document = workspace.current
        let node = DesignNode(kind: .text, text: "已保存")
        document.session.change { $0.pages[0].nodes.append(node) }
        document.session.history.markSaved(document: document.session.document)
        let canvas = CanvasView(session: document.session)
        canvas.beginText(node.id)
        try #require(canvas.editor).string = "关闭前提交"
        var asked = false
        let closed = workspace.close([document.id], decide: { candidate in
            asked = true
            #expect(candidate.session.document.node(id: node.id)?.text == "关闭前提交")
            return .cancel
        }, save: { _ in false })
        #expect(asked)
        #expect(!closed)
        #expect(canvas.editor == nil)
        #expect(document.session.isDirty)
        #expect(workspace.currentID == document.id)
        document.session.undo()
        #expect(document.session.document.node(id: node.id)?.text == "已保存")
        #expect(!document.session.isDirty)
    }

    @Test func closingCleanDocumentsSkipsPromptsKeepsOrderAndSelectsAdjacentSurvivor() {
        let workspace = DocumentWorkspace()
        let first = workspace.current
        let second = workspace.newDocument()
        let third = workspace.newDocument()
        workspace.select(second.id)
        let decide: (EditorDocument) -> DocumentCloseDecision = { _ in Issue.record("干净文档不应询问"); return .cancel }
        let save: (EditorDocument) -> Bool = { _ in Issue.record("干净文档不应保存"); return false }
        #expect(workspace.close([second.id], decide: decide, save: save))
        #expect(workspace.documents.map(\.id) == [first.id, third.id])
        #expect(workspace.currentID == third.id)
        #expect(workspace.close([first.id], decide: decide, save: save))
        #expect(workspace.currentID == third.id)
        #expect(workspace.close([UUID()], decide: decide, save: save))
        #expect(workspace.documents.map(\.id) == [third.id])
    }

    @Test func lastCloseCreatesFreshPlaceholderAndOnlyNextNewReusesIt() {
        let workspace = DocumentWorkspace()
        let initial = workspace.current
        initial.session.change { $0.name = "丢弃" }
        #expect(workspace.closeAll(decide: { _ in .discard }, save: { _ in false }))
        let placeholder = workspace.current
        #expect(workspace.isPlaceholder)
        #expect(workspace.documents.count == 1)
        #expect(placeholder.id != initial.id)
        #expect(placeholder.session !== initial.session)
        #expect(placeholder.title != initial.title)
        #expect(!placeholder.session.isDirty)
        #expect(!placeholder.session.history.canUndo)
        #expect(placeholder.session.page.nodes.isEmpty)
        let reopened = workspace.newDocument()
        #expect(reopened.id == placeholder.id)
        #expect(workspace.documents.count == 1)
        #expect(!workspace.isPlaceholder)
        let added = workspace.newDocument()
        #expect(added.id != reopened.id)
        #expect(workspace.documents.count == 2)
    }

    @Test func showingPlaceholderConsumesItsSpecialNewBehavior() {
        let workspace = DocumentWorkspace()
        #expect(workspace.closeAll(decide: { _ in .discard }, save: { _ in false }))
        let placeholder = workspace.current
        workspace.activatePlaceholder()
        #expect(!workspace.isPlaceholder)
        #expect(workspace.newDocument().id != placeholder.id)
        #expect(workspace.documents.count == 2)
    }

    @Test func openFromPlaceholderReplacesOnlyThatPlaceholder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("打开.opensketch")
        let document = DesignDocument(name: "打开")
        try DocumentCodec.save(document, to: url)
        let workspace = DocumentWorkspace()
        #expect(workspace.closeAll(decide: { _ in .discard }, save: { _ in false }))
        let placeholderID = workspace.currentID
        let opened = try workspace.open(url)
        #expect(workspace.documents.map(\.id) == [opened.id])
        #expect(opened.id != placeholderID)
        #expect(opened.session.document == document)
        #expect(!workspace.isPlaceholder)
        #expect(workspace.newDocument().id != opened.id)
    }

    @Test func closingBackgroundDocumentSavesOnlyThatSession() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = DocumentWorkspace()
        let first = workspace.current
        first.session.change { $0.name = "后台文档" }
        let second = workspace.newDocument()
        second.session.change { $0.name = "当前文档" }
        let url = directory.appendingPathComponent("后台.opensketch")
        #expect(workspace.close([first.id], decide: { _ in .save }, save: { document in
            do {
                try DocumentCodec.save(document.session.document, to: url)
                document.session.url = url
                return true
            } catch { Issue.record(error); return false }
        }))
        #expect(try DocumentCodec.load(from: url).name == "后台文档")
        #expect(!first.session.isDirty)
        #expect(first.session.history.canUndo)
        #expect(workspace.documents.map(\.id) == [second.id])
        #expect(workspace.currentID == second.id)
        #expect(second.session.isDirty)
        #expect(second.session.url == nil)
    }

    @Test(arguments: [false, true]) func editedPlaceholderIsPreservedByNewAndOpen(_ openFile: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("打开.opensketch")
        try DocumentCodec.save(DesignDocument(name: "磁盘文档"), to: url)
        let workspace = DocumentWorkspace()
        #expect(workspace.closeAll(decide: { _ in .discard }, save: { _ in false }))
        let placeholder = workspace.current
        placeholder.session.change { $0.name = "占位文档中的修改" }
        let added = try openFile ? workspace.open(url) : workspace.newDocument()
        #expect(added.id != placeholder.id)
        #expect(workspace.documents.map(\.id) == [placeholder.id, added.id])
        #expect(placeholder.session.document.name == "占位文档中的修改")
        #expect(placeholder.session.isDirty)
        #expect(!workspace.isPlaceholder)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

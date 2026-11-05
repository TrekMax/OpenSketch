import Foundation
import Testing
@testable import OpenSketchCore

@Test func gestureCommitsOneUndoEntryAndRestoresRedo() throws {
    var document = DesignDocument()
    let original = document
    var history = DocumentHistory(document: document)
    history.begin(document: document)
    document.name = "拖动中"
    document.name = "拖动结束"
    #expect(history.isEditing)
    #expect({ history.commit(document: document) }())
    let edited = document
    #expect(history.isDirty(document))
    document = try #require({ history.undo(current: document) }())
    #expect(document == original)
    #expect(!history.canUndo)
    #expect(!history.isDirty(document))
    #expect({ history.redo(current: document) }() == edited)
}

@Test func cancellationRestoresOriginalAndPreservesRedo() throws {
    var document = DesignDocument()
    var history = DocumentHistory(document: document)
    history.begin(document: document)
    document.name = "已提交"
    #expect({ history.commit(document: document) }())
    document = try #require({ history.undo(current: document) }())
    history.begin(document: document)
    document.name = "取消的拖动"
    document = try #require({ history.cancel() }())
    #expect(document.name == "未命名")
    #expect(!history.isDirty(document))
    #expect(history.canRedo)
    #expect(!history.isEditing)
}

@Test func noOpCommitPreservesRedoAndNestedBeginKeepsGestureOrigin() throws {
    var document = DesignDocument()
    let original = document
    var history = DocumentHistory(document: document)
    history.begin(document: document)
    document.name = "第一步"
    history.begin(document: document)
    document.name = "最终"
    #expect({ history.commit(document: document) }())
    document = try #require({ history.undo(current: document) }())
    #expect(document == original)
    history.begin(document: document)
    #expect({ !history.commit(document: document) }())
    #expect(history.canRedo)
    #expect({ history.redo(current: document) }()?.name == "最终")
}

@Test func undoToSavedRevisionIsCleanAndSaveDoesNotClearUndo() throws {
    var document = DesignDocument()
    var history = DocumentHistory(document: document)
    history.begin(document: document)
    document.name = "已保存"
    #expect({ history.commit(document: document) }())
    history.markSaved(document: document)
    #expect(!history.isDirty(document))
    #expect(history.canUndo)
    history.begin(document: document)
    document.name = "后续编辑"
    #expect({ history.commit(document: document) }())
    #expect(history.isDirty(document))
    document = try #require({ history.undo(current: document) }())
    #expect(document.name == "已保存")
    #expect(!history.isDirty(document))
    document = try #require({ history.undo(current: document) }())
    #expect(history.isDirty(document))
    document = try #require({ history.redo(current: document) }())
    #expect(!history.isDirty(document))
}

@Test func savingInsideGestureAndThenCancellingUsesActualSavedContent() throws {
    var document = DesignDocument()
    let original = document
    var history = DocumentHistory(document: document)
    history.begin(document: document)
    document.name = "手势中保存的状态"
    history.markSaved(document: document)
    #expect(!history.isDirty(document))
    document.name = "保存后的移动"
    #expect(history.isDirty(document))
    #expect(!history.canUndo)
    #expect({ history.undo(current: document) }() == nil)
    document = try #require({ history.cancel() }())
    #expect(document == original)
    #expect(history.isDirty(document))
    #expect(!history.canUndo)
}

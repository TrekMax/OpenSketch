import Foundation

public struct DocumentHistory: Sendable {
    private var undoStack: [DesignDocument] = []
    private var redoStack: [DesignDocument] = []
    private var pending: DesignDocument?
    private var saved: DesignDocument

    public init(document: DesignDocument) { saved = document }
    public var canUndo: Bool { pending == nil && !undoStack.isEmpty }
    public var canRedo: Bool { pending == nil && !redoStack.isEmpty }
    public var isEditing: Bool { pending != nil }

    /// Repeated begin calls within a gesture keep its original snapshot.
    public mutating func begin(document: DesignDocument) {
        if pending == nil { pending = document }
    }

    @discardableResult
    public mutating func commit(document: DesignDocument) -> Bool {
        guard let original = pending else { return false }
        pending = nil
        guard original != document else { return false }
        undoStack.append(original)
        redoStack.removeAll()
        return true
    }

    /// The caller must apply the returned original document.
    public mutating func cancel() -> DesignDocument? {
        defer { pending = nil }
        return pending
    }

    public mutating func undo(current: DesignDocument) -> DesignDocument? {
        guard pending == nil, let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public mutating func redo(current: DesignDocument) -> DesignDocument? {
        guard pending == nil, let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public mutating func markSaved(document: DesignDocument) { saved = document }
    public func isDirty(_ document: DesignDocument) -> Bool { document != saved }
}

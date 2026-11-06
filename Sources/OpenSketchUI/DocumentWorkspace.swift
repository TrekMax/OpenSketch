import Foundation
import Observation
import OpenSketchCore

@MainActor struct EditorDocument: Identifiable {
    let id = UUID()
    let session: EditorSession
    let untitledTitle: String
    var title: String { session.url?.deletingPathExtension().lastPathComponent ?? untitledTitle }
}

enum DocumentCloseDecision { case save, discard, cancel }

@MainActor @Observable final class DocumentWorkspace {
    private(set) var documents: [EditorDocument]
    private(set) var currentID: UUID
    private(set) var isPlaceholder = false
    private var nextUntitledNumber = 2
    var current: EditorDocument { documents.first { $0.id == currentID }! }

    init() {
        let first = EditorDocument(session: EditorSession(), untitledTitle: "未命名 1")
        documents = [first]
        currentID = first.id
    }

    @discardableResult func newDocument() -> EditorDocument {
        current.session.finishInput?()
        if isPlaceholder && !current.session.isDirty {
            isPlaceholder = false
            return current
        }
        isPlaceholder = false
        let document = makeUntitledDocument()
        documents.append(document)
        currentID = document.id
        return document
    }

    @discardableResult func select(_ id: UUID) -> Bool {
        guard documents.contains(where: { $0.id == id }) else { return false }
        guard id != currentID else { return true }
        current.session.finishInput?()
        currentID = id
        return true
    }

    @discardableResult func open(_ url: URL) throws -> EditorDocument {
        if let existing = document(matching: url) {
            select(existing.id)
            return existing
        }
        let loaded = try DocumentCodec.load(from: url)
        current.session.finishInput?()
        let document = makeUntitledDocument(session: EditorSession(document: loaded))
        document.session.url = url
        if isPlaceholder && !current.session.isDirty { documents = [document] }
        else { documents.append(document) }
        currentID = document.id
        isPlaceholder = false
        return document
    }

    func document(matching url: URL, excluding id: UUID? = nil) -> EditorDocument? {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        return documents.first {
            $0.id != id && $0.session.url?.standardizedFileURL.resolvingSymlinksInPath() == canonical
        }
    }

    /// Consume the last-close placeholder when a controller shows it on reopen.
    func activatePlaceholder() { isPlaceholder = false }

    /// Removal is transactional. Completed file saves are intentionally retained
    /// if a later document cancels or fails to save.
    @discardableResult func close(
        _ ids: Set<UUID>,
        decide: (EditorDocument) -> DocumentCloseDecision,
        save: (EditorDocument) -> Bool
    ) -> Bool {
        let pending = documents.filter { ids.contains($0.id) }
        guard !pending.isEmpty else { return true }
        current.session.finishInput?()
        for document in pending where document.id != currentID { document.session.finishInput?() }
        for document in pending where document.session.isDirty {
            switch decide(document) {
            case .cancel: return false
            case .discard: break
            case .save:
                guard save(document) else { return false }
                document.session.history.markSaved(document: document.session.document)
            }
        }
        let remaining = documents.filter { !ids.contains($0.id) }
        if remaining.isEmpty {
            let placeholder = makeUntitledDocument()
            documents = [placeholder]
            currentID = placeholder.id
            isPlaceholder = true
        } else if ids.contains(currentID) {
            let currentIndex = documents.firstIndex { $0.id == currentID }!
            let next = documents.dropFirst(currentIndex + 1).first { !ids.contains($0.id) } ?? remaining[remaining.count - 1]
            documents = remaining
            currentID = next.id
        } else {
            documents = remaining
        }
        return true
    }

    @discardableResult func closeAll(
        decide: (EditorDocument) -> DocumentCloseDecision,
        save: (EditorDocument) -> Bool
    ) -> Bool {
        close(Set(documents.map(\.id)), decide: decide, save: save)
    }

    private func makeUntitledDocument(session: EditorSession = EditorSession()) -> EditorDocument {
        defer { nextUntitledNumber += 1 }
        return EditorDocument(session: session, untitledTitle: "未命名 \(nextUntitledNumber)")
    }
}

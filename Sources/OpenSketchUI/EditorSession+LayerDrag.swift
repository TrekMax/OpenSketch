import AppKit
import OpenSketchCore

struct SidebarLayerDrag: Equatable, Sendable {
    static let typeIdentifier = "org.opensketch.layer-tree-drag"
    let id = UUID()
    let pageID: UUID
    let selection: Set<UUID>
    let document: DesignDocument
    /// A process-local advertised type carries identity through pasteboard bridging.
    var itemTypeIdentifier: String { Self.typeIdentifier + "." + id.uuidString.lowercased() }
}

extension EditorSession {
    func beginSidebarLayerDrag(_ rowID: UUID) -> SidebarLayerDrag? {
        guard sidebarRename == nil else { return nil }
        finishInput?()
        let moving = contextMenuSelection(for: rowID)
        guard LayerTreeEditing.canDrag(document, pageID: pageID, selection: moving) else { return nil }
        let request = SidebarLayerDrag(pageID: pageID, selection: moving, document: document)
        selection = moving
        sidebarLayerDrag = request
        return request
    }

    func canDropSidebarLayers(_ token: UUID, to destination: LayerDropDestination) -> Bool {
        guard let request = sidebarLayerDrag, request.id == token,
              request.pageID == pageID, request.document == document else { return false }
        return LayerTreeEditing.canMove(document, pageID: pageID, selection: request.selection, to: destination)
    }

    @discardableResult func commitSidebarLayerDrop(_ token: UUID, to destination: LayerDropDestination) -> Bool {
        guard let request = sidebarLayerDrag, request.id == token else { return false }
        finishInput?()
        guard request.pageID == pageID, request.document == document else {
            message = "图层拖动已取消：页面或文档已改变。"
            return false
        }
        do {
            let result = try LayerTreeEditing.move(document, pageID: pageID, selection: request.selection, to: destination)
            if result.document != document {
                history.begin(document: document)
                document = result.document
                history.commit(document: document)
            }
            selection = result.selection
            return true
        } catch {
            message = "无法移动图层：目标无效、对象已锁定或隐藏，或超出文档限制。"
            return false
        }
    }

    func sidebarLayerDragProvider(for rowID: UUID) -> NSItemProvider {
        guard let request = beginSidebarLayerDrag(rowID) else { return NSItemProvider() }
        let provider = NSItemProvider()
        provider.suggestedName = request.id.uuidString
        let data = Data(request.id.uuidString.utf8)
        for type in [SidebarLayerDrag.typeIdentifier, request.itemTypeIdentifier] {
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    func sidebarDragToken(from providers: [NSItemProvider]) -> UUID? {
        guard providers.count == 1, let request = sidebarLayerDrag,
              providers[0].hasItemConformingToTypeIdentifier(SidebarLayerDrag.typeIdentifier),
              providers[0].registeredTypeIdentifiers.contains(request.itemTypeIdentifier) else { return nil }
        return request.id
    }

    /// Accept only this session's provider, then revalidate its bytes and document
    /// on the main actor after asynchronous delivery. Never trust a display name alone.
    func acceptSidebarLayerDrop(_ providers: [NSItemProvider], to destination: LayerDropDestination,
                                completion: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard let token = sidebarDragToken(from: providers), canDropSidebarLayers(token, to: destination) else { return false }
        providers[0].loadDataRepresentation(forTypeIdentifier: SidebarLayerDrag.typeIdentifier) { [weak self] data, error in
            let valid = error == nil && data == Data(token.uuidString.utf8)
            Task { @MainActor in
                guard let self else { completion(false); return }
                guard valid else {
                    if self.sidebarLayerDrag?.id == token { self.sidebarLayerDrag = nil }
                    completion(false)
                    return
                }
                completion(self.commitSidebarLayerDrop(token, to: destination))
            }
        }
        return true
    }
}

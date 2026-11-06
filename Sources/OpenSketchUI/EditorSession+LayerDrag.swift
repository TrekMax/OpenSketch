import Foundation
import OpenSketchCore

struct SidebarLayerDrag: Equatable, Sendable {
    let id = UUID()
    let pageID: UUID
    let selection: Set<UUID>
    let document: DesignDocument
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

}

import Foundation
import OpenSketchCore

enum SidebarRenameTarget: Equatable {
    case page(UUID)
    case layer(pageID: UUID, nodeID: UUID)

    var title: String {
        switch self { case .page: "重命名页面"; case .layer: "重命名图层" }
    }

    fileprivate func name(in document: DesignDocument) -> String? {
        switch self {
        case .page(let id): document.pages.first { $0.id == id }?.name
        case .layer(let pageID, let nodeID):
            document.pageContaining(nodeID: nodeID) == pageID ? document.node(id: nodeID)?.name : nil
        }
    }
}

struct SidebarRenameRequest: Identifiable {
    let id = UUID()
    let documentID: UUID
    let target: SidebarRenameTarget
    let originalName: String
}

struct SidebarRenameEdit {
    let request: SidebarRenameRequest
    var name: String
}

extension EditorSession {
    func startSidebarRename(_ target: SidebarRenameTarget) {
        guard let request = beginSidebarRename(target) else { return }
        sidebarRename = SidebarRenameEdit(request: request, name: request.originalName)
    }

    func updateSidebarRename(_ token: UUID, name: String) {
        guard sidebarRename?.request.id == token else { return }
        sidebarRename?.name = name
    }

    func finishSidebarRename(token: UUID? = nil, cancel: Bool = false) {
        guard let edit = sidebarRename, token == nil || token == edit.request.id else { return }
        let name = cancel ? edit.name : (sidebarRenameText?() ?? edit.name)
        // Clear ownership before committing: commit also finishes other input owners.
        sidebarRename = nil
        sidebarRenameText = nil
        guard !cancel else { return }
        do { try commitSidebarRename(edit.request, name: name) }
        catch { message = error.localizedDescription }
    }

    func beginSidebarRename(_ target: SidebarRenameTarget) -> SidebarRenameRequest? {
        finishInput?()
        guard let name = target.name(in: document) else { return nil }
        return SidebarRenameRequest(documentID: document.id, target: target, originalName: name)
    }

    /// Rename metadata independently of selection, visibility and geometry locks.
    func commitSidebarRename(_ request: SidebarRenameRequest, name proposedName: String) throws {
        finishInput?()
        guard request.documentID == document.id, let currentName = request.target.name(in: document) else {
            throw EditorError.invalid("重命名对象已不存在或不再属于原页面。")
        }
        guard currentName == request.originalName else {
            throw EditorError.invalid("名称已被修改，请取消后重新打开重命名。")
        }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw EditorError.invalid("名称不能为空。") }
        guard !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw EditorError.invalid("名称不能包含换行或控制字符。")
        }
        guard name.utf8.count <= DocumentCodec.maximumStringBytes else {
            throw EditorError.invalid("名称过长，请缩短后重试。")
        }
        guard name != currentName else { return }

        var candidate = document
        switch request.target {
        case .page(let id):
            guard let index = candidate.pages.firstIndex(where: { $0.id == id }) else { return }
            candidate.pages[index].name = name
        case .layer(_, let nodeID):
            candidate.updateNode(id: nodeID) { $0.name = name }
        }
        do { _ = try DocumentCodec.encode(candidate) }
        catch { throw EditorError.invalid("无法重命名：文档数据无效或超出格式大小限制。") }
        history.begin(document: document)
        document = candidate
        history.commit(document: document)
    }
}

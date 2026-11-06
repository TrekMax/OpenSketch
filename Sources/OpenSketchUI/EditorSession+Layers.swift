import AppKit
import OpenSketchCore

extension EditorSession {
    func canPerform(_ command: LayerCommand) -> Bool {
        canPerform(command, selection: selection)
    }

    func canPerform(_ command: LayerCommand, selection: Set<UUID>) -> Bool {
        LayerEditing.canApply(command, to: document, pageID: pageID, selection: selection)
    }

    func perform(_ command: LayerCommand) {
        finishInput?()
        do {
            let result = try LayerEditing.apply(command, to: document, pageID: pageID, selection: selection)
            if result.document != document { change { $0 = result.document } }
            selection = result.selection
        } catch {
            let reason: String
            switch error {
            case LayerEditError.invalidSelection: reason = "请选择适用的图层"
            case LayerEditError.differentParents: reason = "所选图层必须位于同一容器"
            case LayerEditError.lockedOrHidden: reason = "图层或祖先已锁定 / 隐藏"
            case LayerEditError.styledGroup: reason = "编组包含填充、描边或不透明度效果"
            case LayerEditError.invalidGeometry: reason = "图层几何数据无效或超出范围"
            case DocumentCodecError.limitExceeded: reason = "文档内容超出格式或大小限制"
            default: reason = "文档数据无效：\(error.localizedDescription)"
            }
            message = "无法\(command.title)：\(reason)"
        }
    }

    func canvasSelectionTarget(_ hit: UUID, direct: Bool) -> UUID {
        guard !direct else { return hit }
        var target = hit
        var parent = document.parentID(of: hit)
        while let id = parent {
            if document.node(id: id)?.kind == .group { target = id }
            parent = document.parentID(of: id)
        }
        return target
    }

    func selectLayer(_ id: UUID, event: NSEvent?, fallbackModifiers: NSEvent.ModifierFlags) {
        let modifiers = event?.modifierFlags ?? fallbackModifiers
        selectLayer(id, extending: modifiers.contains(.shift))
    }

    func selectLayer(_ id: UUID, extending: Bool) {
        finishInput?()
        if extending {
            if selection.contains(id) { selection.remove(id) }
            else { selection.insert(id) }
        } else { selection = [id] }
    }

    func contextMenuSelection(for id: UUID) -> Set<UUID> {
        selection.contains(id) ? selection : [id]
    }

    func canEditContextLayers(for id: UUID) -> Bool {
        let target = contextMenuSelection(for: id)
        let pageIDs = Set(SceneGeometry.traversal(in: page).map(\.id))
        return !target.isEmpty && target.isSubset(of: pageIDs) && target.allSatisfy(editable)
    }

    func duplicateContextLayers(for id: UUID) {
        finishInput?()
        guard canEditContextLayers(for: id) else { return }
        selection = contextMenuSelection(for: id)
        duplicate()
    }

    func deleteContextLayers(for id: UUID) {
        finishInput?()
        guard canEditContextLayers(for: id) else { return }
        selection = contextMenuSelection(for: id)
        deleteSelection()
    }
}

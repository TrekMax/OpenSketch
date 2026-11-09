import AppKit
import OpenSketchCore

extension EditorSession {
    func canPerform(_ command: LayerCommand) -> Bool {
        canPerform(command, selection: selection)
    }

    func canPerform(_ command: LayerCommand, selection: Set<UUID>) -> Bool {
        if case .boolean(let operation) = command {
            return BooleanLayerEditing.canApply(operation, to: document, pageID: pageID, selection: selection)
        }
        return LayerEditing.canApply(command, to: document, pageID: pageID, selection: selection)
    }

    func perform(_ command: LayerCommand) {
        finishInput?()
        if case .boolean(let operation) = command {
            do {
                let result = try BooleanLayerEditing.apply(operation, to: document, pageID: pageID, selection: selection)
                change { $0 = result.document }
                self.selection = result.selection
            } catch {
                setMessage(.format("无法%@：%@", [.key(command.titleKey), .error(error)]))
            }
            return
        }
        do {
            let result = try LayerEditing.apply(command, to: document, pageID: pageID, selection: selection)
            var updated = result.document
            if command == .group {
                for id in result.selection where document.node(id: id) == nil {
                    updated.updateNode(id: id) { $0.name = L10n.text("编组") }
                }
            }
            if updated != document { change { $0 = updated } }
            selection = result.selection
        } catch {
            let reason: LocalizedMessage
            switch error {
            case LayerEditError.invalidSelection: reason = .key("请选择适用的图层")
            case LayerEditError.differentParents: reason = .key("所选图层必须位于同一容器")
            case LayerEditError.lockedOrHidden: reason = .key("图层或祖先已锁定 / 隐藏")
            case LayerEditError.styledGroup: reason = .key("编组包含填充、描边或不透明度效果")
            case LayerEditError.invalidGeometry: reason = .key("图层几何数据无效或超出范围")
            case DocumentCodecError.limitExceeded: reason = .key("文档内容超出格式或大小限制")
            default: reason = .format("文档数据无效：%@", [.error(error)])
            }
            setMessage(.format("无法%@：%@", [.key(command.titleKey), reason]))
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

import AppKit
import OpenSketchCore

/// Display units, validation and mutation are identical for typing and scrubbing.
enum InspectorNumberProperty: String, CaseIterable {
    case x, y, width, height, rotation, opacity, strokeWidth, cornerRadius, fontSize

    var title: String {
        switch self {
        case .x: "X"; case .y: "Y"; case .width: "宽"; case .height: "高"
        case .rotation: "旋转"; case .opacity: "透明度"; case .strokeWidth: "线宽"
        case .cornerRadius: "圆角"; case .fontSize: "字号"
        }
    }
    var label: String {
        switch self { case .width: "W"; case .height: "H"; case .rotation: "↻"; case .opacity: "%"; default: title }
    }
    var identifier: String { "inspector.\(rawValue)" }
    func canEdit(_ node: DesignNode) -> Bool {
        switch self {
        case .width, .height: node.kind != .group
        case .fontSize: node.kind == .text
        case .strokeWidth, .cornerRadius: node.kind != .group
        default: true
        }
    }
    func value(in node: DesignNode) -> Double {
        switch self {
        case .x: node.frame.origin.x; case .y: node.frame.origin.y
        case .width: node.frame.width; case .height: node.frame.height
        case .rotation: node.rotation; case .opacity: node.style.opacity * 100
        case .strokeWidth: node.style.strokeWidth; case .cornerRadius: node.style.cornerRadius
        case .fontSize: node.fontSize
        }
    }
    func normalized(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        switch self {
        case .x, .y: return min(1e9, max(-1e9, value))
        case .width, .height: return min(1e7, max(1, value))
        case .rotation: return value.truncatingRemainder(dividingBy: 360)
        case .opacity: return min(100, max(0, value))
        case .strokeWidth: return min(10000, max(0, value))
        case .cornerRadius: return min(1e7, max(0, value))
        case .fontSize: return min(1000, max(1, value))
        }
    }
    func restore(from original: DesignNode, to node: inout DesignNode) {
        if self == .opacity { node.style.opacity = original.style.opacity }
        else { write(value(in: original), to: &node) }
    }
    func write(_ value: Double, to node: inout DesignNode) {
        switch self {
        case .x: node.frame.origin.x = value; case .y: node.frame.origin.y = value
        case .width: node.frame.size.width = value; case .height: node.frame.size.height = value
        case .rotation: node.rotation = value; case .opacity: node.style.opacity = value / 100
        case .strokeWidth: node.style.strokeWidth = value; case .cornerRadius: node.style.cornerRadius = value
        case .fontSize: node.fontSize = value
        }
    }
}

struct InspectorNumberEdit {
    let token = UUID()
    let documentID: UUID
    let pageID: UUID
    let nodeID: UUID
    let property: InspectorNumberProperty
    let initialNode: DesignNode
    var initialValue: Double { property.value(in: initialNode) }
}

extension EditorSession {
    func setInspectorNumber(_ property: InspectorNumberProperty, nodeID: UUID, value: Double) {
        guard let value = property.normalized(value), let node = document.node(id: nodeID),
              property.canEdit(node), editable(nodeID) else { return }
        update(nodeID) { property.write(value, to: &$0) }
    }

    @discardableResult func beginInspectorEdit(_ property: InspectorNumberProperty, nodeID: UUID) -> UUID? {
        finishInput?()
        guard selection == [nodeID], let node = document.node(id: nodeID),
              SceneGeometry.traversal(in: page).contains(where: { $0.id == nodeID }),
              property.canEdit(node), editable(nodeID) else { return nil }
        let edit = InspectorNumberEdit(documentID: document.id, pageID: pageID, nodeID: nodeID,
                                       property: property, initialNode: node)
        inspectorEdit = edit
        history.begin(document: document)
        return edit.token
    }

    func scrubInspectorNumber(_ token: UUID, translation: Double, modifiers: NSEvent.ModifierFlags = []) {
        guard translation.isFinite, let edit = validInspectorEdit(token) else { return }
        if translation == 0 {
            // Restore the exact stored scalar, including unnormalized rotations,
            // valid zero sizes and opacity precision lost in percent conversion.
            document.updateNode(id: edit.nodeID) { edit.property.restore(from: edit.initialNode, to: &$0) }
            return
        }
        let step = modifiers.contains(.option) ? 0.1 : modifiers.contains(.shift) ? 10.0 : 1.0
        updateInspectorNumber(token, value: edit.initialValue + translation * step)
    }

    private func validInspectorEdit(_ token: UUID) -> InspectorNumberEdit? {
        guard let edit = inspectorEdit, edit.token == token else { return nil }
        guard edit.documentID == document.id, edit.pageID == pageID, selection == [edit.nodeID],
              let node = document.node(id: edit.nodeID), editable(edit.nodeID), edit.property.canEdit(node) else {
            finishInspectorEdit(token)
            return nil
        }
        return edit
    }

    func updateInspectorNumber(_ token: UUID, value: Double) {
        guard let edit = validInspectorEdit(token), let value = edit.property.normalized(value) else { return }
        document.updateNode(id: edit.nodeID) { edit.property.write(value, to: &$0) }
    }

    func finishInspectorEdit(_ token: UUID, cancel: Bool = false) {
        guard let edit = inspectorEdit, edit.token == token else { return }
        inspectorEdit = nil
        finishInspectorText = nil
        if cancel {
            if let original = history.cancel(), original.id == document.id { document = original }
        } else { history.commit(document: document) }
    }

    /// Pure menu validation, including a changed value in an unfinished scrub.
    var canUndoInspectorEdit: Bool {
        guard inspectorEdit != nil else { return false }
        var candidate = history
        candidate.commit(document: document)
        return candidate.canUndo
    }

    func finishInspectorInput() {
        // The text callback may write the final field-editor value before commit.
        let finishText = finishInspectorText
        finishInspectorText = nil
        finishText?()
        if let edit = inspectorEdit { finishInspectorEdit(edit.token) }
    }
}

import AppKit
import OpenSketchCore

/// Exists only for an applied ordinary mouse move, never for creation or precision input.
struct ContainerDrag {
    let point: CGPoint
    let pageID: UUID
    let dropTargetID: UUID?
}

extension CanvasView {
    var dropTargetID: UUID? { containerDrag?.dropTargetID }

    func updateContainerDrag(to point: CGPoint, from origin: CGPoint, applied: Bool) {
        guard applied, hypot(point.x - origin.x, point.y - origin.y) * session.zoom >= 3,
              let original = session.gestureStart, session.document != original else {
            clearContainerDrag()
            return
        }
        containerDrag = ContainerDrag(point: point, pageID: session.pageID,
                                      dropTargetID: ContainerEditing.dropTarget(in: session.page, selection: session.selection, at: point))
    }

    func finishContainerDrop() {
        guard start != nil, creation == nil, resizing == nil, precision == nil,
              let drag = containerDrag, drag.pageID == session.pageID else { return }
        // Mouse-up can have a new cursor location for which no geometry was applied.
        session.applyContainerDrop(at: drag.point)
    }

    func clearContainerDrag() {
        containerDrag = nil
        needsDisplay = true
    }

    func drawContainerDrag(in context: CGContext) {
        guard let drag = containerDrag, drag.pageID == session.pageID else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(EditorPalette.accent.cgColor)
        context.setLineWidth(1.5 / session.zoom)
        if let id = drag.dropTargetID, let node = session.document.node(id: id),
           let transform = SceneGeometry.worldTransform(id: id, in: session.page) {
            strokeContainerOutline(CGRect(origin: .zero, size: node.frame.size), transform: transform, in: context)
        }
        // The normal selection is clipped with its old parent. Keep an outer outline
        // visible while the artwork is dragged beyond that clipping frame.
        for id in session.roots {
            guard let geometry = CanvasRenderer.selectionGeometry(id: id, page: session.page),
                  !geometry.clips.isEmpty else { continue }
            strokeContainerOutline(geometry.localBounds, transform: geometry.transform, in: context)
        }
    }

    private func strokeContainerOutline(_ rect: CGRect, transform: CGAffineTransform, in context: CGContext) {
        var transform = transform
        context.addPath(CGPath(rect: rect, transform: &transform))
        context.strokePath()
    }
}

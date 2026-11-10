import Foundation

/// Applies the persisted pinning rules when a frame changes size. The solver
/// operates on a value copy, so a failed validation cannot partially mutate a
/// document or its history.
public enum ResponsiveLayoutEngine {
    public static func applying(_ document: DesignDocument, frameID: UUID, newSize: CGSize) throws -> DesignDocument {
        guard newSize.width.isFinite, newSize.height.isFinite, newSize.width > 0, newSize.height > 0 else {
            throw LayerEditError.invalidGeometry
        }
        var result = document
        guard let oldFrame = result.node(id: frameID), oldFrame.kind == .frame else { throw LayerEditError.invalidSelection }
        guard result.updateNode(id: frameID, { $0.frame.size = newSize }) else { throw LayerEditError.invalidSelection }
        try solveChildren(of: frameID, oldSize: oldFrame.frame.size, newSize: newSize, in: &result)
        _ = try DocumentCodec.encode(result)
        return result
    }

    private static func solveChildren(of frameID: UUID, oldSize: CGSize, newSize: CGSize, in document: inout DesignDocument) throws {
        guard let frame = document.node(id: frameID) else { throw LayerEditError.invalidSelection }
        let parentSize = newSize
        let children = frame.children
        for child in children {
            guard let constraints = child.constraints else {
                if child.kind == .frame || child.kind == .group { try solveChildren(of: child.id, oldSize: child.frame.size, newSize: child.frame.size, in: &document) }
                continue
            }
            var origin = child.frame.origin
            var size = child.frame.size
            if constraints.pinLeft && constraints.pinRight && !constraints.fixedWidth {
                let rightInset = oldSize.width - child.frame.maxX
                size.width = max(0.1, parentSize.width - origin.x - rightInset)
            } else if constraints.pinRight && !constraints.pinLeft {
                let rightInset = oldSize.width - child.frame.maxX
                origin.x = parentSize.width - rightInset - size.width
            }
            if constraints.pinTop && constraints.pinBottom && !constraints.fixedHeight {
                let bottomInset = oldSize.height - child.frame.maxY
                size.height = max(0.1, parentSize.height - origin.y - bottomInset)
            } else if constraints.pinBottom && !constraints.pinTop {
                let bottomInset = oldSize.height - child.frame.maxY
                origin.y = parentSize.height - bottomInset - size.height
            }
            _ = document.updateNode(id: child.id) { node in node.frame.origin = origin; node.frame.size = size }
            if child.kind == .frame || child.kind == .group { try solveChildren(of: child.id, oldSize: child.frame.size, newSize: size, in: &document) }
        }
    }
}

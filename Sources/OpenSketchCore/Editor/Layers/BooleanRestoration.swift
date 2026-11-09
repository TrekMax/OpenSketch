import Foundation

public enum BooleanRestoration {
    public static func canRestore(_ document: DesignDocument, pageID: UUID,
                                  selection: Set<UUID>) -> Bool {
        guard selection.count == 1, let id = selection.first,
              let node = document.node(id: id), node.kind == .path,
              node.booleanSource != nil,
              document.pageContaining(nodeID: id) == pageID else { return false }
        return true
    }

    public static func restore(_ document: DesignDocument, pageID: UUID,
                               selection: Set<UUID>) throws -> LayerEditResult {
        guard canRestore(document, pageID: pageID, selection: selection),
              let id = selection.first, let result = document.node(id: id),
              let source = result.booleanSource,
              let pageIndex = document.pages.firstIndex(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        let parentID = document.parentID(of: id)
        var candidate = document
        var siblings = parentID.flatMap { candidate.node(id: $0)?.children } ?? candidate.pages[pageIndex].nodes
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { throw LayerEditError.invalidSelection }
        let local = SceneGeometry.localTransform(for: result)
        let restored = source.operands.map { original -> DesignNode in
            var operand = original
            let center = CGPoint(x: operand.frame.midX, y: operand.frame.midY).applying(local)
            operand.frame.origin = CGPoint(x: center.x - operand.frame.width / 2,
                                           y: center.y - operand.frame.height / 2)
            operand.rotation += result.rotation
            return operand
        }
        siblings.remove(at: index)
        siblings.insert(contentsOf: restored, at: index)
        if let parentID { candidate.updateNode(id: parentID) { $0.children = siblings } }
        else { candidate.pages[pageIndex].nodes = siblings }
        _ = try DocumentCodec.encode(candidate)
        return LayerEditResult(document: candidate, selection: Set(restored.map(\.id)))
    }
}

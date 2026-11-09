import Foundation
import CoreGraphics

public enum BooleanLayerEditing {
    public static func canApply(_ operation: BooleanOperation, to document: DesignDocument,
                                pageID: UUID, selection: Set<UUID>) -> Bool {
        (try? prepare(operation, document: document, pageID: pageID, selection: selection)) != nil
    }

    public static func apply(_ operation: BooleanOperation, to document: DesignDocument,
                             pageID: UUID, selection: Set<UUID>) throws -> LayerEditResult {
        let prepared = try prepare(operation, document: document, pageID: pageID, selection: selection)
        let combinedWorld = try BooleanEditing.combine(prepared.paths, operation: operation)
        guard let parentTransform = prepared.parentTransform else { throw LayerEditError.invalidGeometry }
        var localTransform = parentTransform.inverted()
        guard let localPath = SceneGeometry.cgPath(for: combinedWorld).copy(using: &localTransform) else {
            throw LayerEditError.invalidGeometry
        }
        let localVector = try BooleanEditing.vectorPath(from: localPath)
        let geometry = try PathEditing.normalized(localVector)
        var result = DesignNode(name: "布尔结果", kind: .path, frame: geometry.frame,
                                style: prepared.nodes[0].style, path: geometry.path)
        result.style.cornerRadius = 0
        result.booleanSource = BooleanSource(operation: operation, operands: prepared.nodes)

        var candidate = document
        guard let pageIndex = candidate.pages.firstIndex(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        var siblings = prepared.parentID.flatMap { candidate.node(id: $0)?.children } ?? candidate.pages[pageIndex].nodes
        guard let last = siblings.lastIndex(where: { selection.contains($0.id) }) else {
            throw LayerEditError.invalidSelection
        }
        let insertionIndex = siblings[..<last].filter { !selection.contains($0.id) }.count
        siblings.removeAll { selection.contains($0.id) }
        siblings.insert(result, at: insertionIndex)
        if let parentID = prepared.parentID { candidate.updateNode(id: parentID) { $0.children = siblings } }
        else { candidate.pages[pageIndex].nodes = siblings }
        _ = try DocumentCodec.encode(candidate)
        return LayerEditResult(document: candidate, selection: [result.id])
    }

    private struct Preparation {
        var nodes: [DesignNode]
        var paths: [VectorPath]
        var parentID: UUID?
        var parentTransform: CGAffineTransform?
    }

    private static func prepare(_ operation: BooleanOperation, document: DesignDocument,
                                pageID: UUID, selection: Set<UUID>) throws -> Preparation {
        guard selection.count >= 2, let page = document.pages.first(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        let nodes = SceneGeometry.traversal(in: page).filter { selection.contains($0.id) }
        guard nodes.count == selection.count else { throw LayerEditError.invalidSelection }
        let parentID = document.parentID(of: nodes[0].id)
        guard nodes.allSatisfy({ document.parentID(of: $0.id) == parentID }) else {
            throw LayerEditError.differentParents
        }
        var parentTransform = CGAffineTransform.identity
        if let parentID, let found = SceneGeometry.worldTransform(id: parentID, in: page) {
            parentTransform = found
        }
        let paths = try nodes.map { node -> VectorPath in
            guard node.isVisible, !node.isLocked, node.style.fill != nil else { throw LayerEditError.invalidSelection }
            let rect = CGRect(origin: .zero, size: node.frame.size)
            let local: CGPath
            switch node.kind {
            case .rectangle:
                let radius = min(node.style.cornerRadius, min(rect.width, rect.height) / 2)
                local = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            case .ellipse: local = CGPath(ellipseIn: rect, transform: nil)
            case .path:
                guard BooleanEditing.isClosed(node.path) else { throw BooleanEditingError.openPath }
                local = SceneGeometry.cgPath(for: node.path)
            default: throw LayerEditError.invalidSelection
            }
            var transform = SceneGeometry.localTransform(for: node).concatenating(parentTransform)
            guard let world = local.copy(using: &transform) else { throw LayerEditError.invalidGeometry }
            return try BooleanEditing.vectorPath(from: world)
        }
        return Preparation(nodes: nodes, paths: paths, parentID: parentID, parentTransform: parentTransform)
    }
}

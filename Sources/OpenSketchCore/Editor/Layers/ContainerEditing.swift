import Foundation
import CoreGraphics

public enum ContainerEditing {
    private struct Entry {
        let node: DesignNode
        let ancestors: [UUID]
        let clippingAncestors: [UUID]
        let nearestFrameID: UUID?
        let world: CGAffineTransform
        let isEditable: Bool
        let hasValidGeometry: Bool
    }

    /// One bottom-to-top scene traversal shared by target lookup and value editing.
    private struct SceneIndex {
        var entries: [Entry] = []
        var byID: [UUID: Entry] = [:]
        var isValid = true

        init(page: DesignPage) {
            visit(page.nodes, ancestors: [], clippingAncestors: [], nearestFrameID: nil,
                  world: .identity, editable: true, validGeometry: true)
        }

        private mutating func visit(_ nodes: [DesignNode], ancestors: [UUID], clippingAncestors: [UUID],
                                    nearestFrameID: UUID?, world: CGAffineTransform,
                                    editable: Bool, validGeometry: Bool) {
            guard !nodes.isEmpty else { return }
            guard ancestors.count < DocumentCodec.maximumDepth else { isValid = false; return }
            for node in nodes {
                let transform = SceneGeometry.localTransform(for: node).concatenating(world)
                let entry = Entry(node: node, ancestors: ancestors, clippingAncestors: clippingAncestors,
                                  nearestFrameID: nearestFrameID, world: transform,
                                  isEditable: editable && node.isVisible && !node.isLocked,
                                  hasValidGeometry: validGeometry && ContainerEditing.validGeometry(node) &&
                                      ContainerEditing.validTransform(transform))
                guard byID.updateValue(entry, forKey: node.id) == nil else { isValid = false; continue }
                entries.append(entry)
                visit(node.children, ancestors: ancestors + [node.id],
                      clippingAncestors: clippingAncestors + (node.kind == .frame && node.clipsContent ? [node.id] : []),
                      nearestFrameID: node.kind == .frame ? node.id : nearestFrameID,
                      world: transform, editable: entry.isEditable, validGeometry: entry.hasValidGeometry)
            }
        }

        func roots(for selection: Set<UUID>) throws -> [Entry] {
            guard isValid, selection.isSubset(of: Set(byID.keys)) else { throw LayerEditError.invalidSelection }
            let roots = entries.filter { selection.contains($0.node.id) && selection.isDisjoint(with: $0.ancestors) }
            guard roots.allSatisfy(\.isEditable) else { throw LayerEditError.lockedOrHidden }
            guard roots.allSatisfy(\.hasValidGeometry) else { throw LayerEditError.invalidGeometry }
            return roots
        }
    }

    /// Finds the deepest eligible frame in the topmost containing subtree, ignoring ordinary overlays.
    /// This read-only path never encodes the document or allocates node identities.
    public static func dropTarget(in page: DesignPage, selection: Set<UUID>, at point: CGPoint) -> UUID? {
        guard !selection.isEmpty, validPoint(point) else { return nil }
        let scene = SceneIndex(page: page)
        guard let roots = try? scene.roots(for: selection), !roots.contains(where: { $0.node.kind == .frame }) else {
            return nil
        }
        let rootIDs = Set(roots.map { $0.node.id })
        for entry in scene.entries.reversed() where entry.node.kind == .frame && entry.isEditable && entry.hasValidGeometry {
            guard !rootIDs.contains(entry.node.id), rootIDs.isDisjoint(with: entry.ancestors),
                  contains(point, in: entry) else { continue }
            let unclipped = entry.clippingAncestors.allSatisfy { id in
                guard let ancestor = scene.byID[id] else { return false }
                return contains(point, in: ancestor)
            }
            if unclipped { return entry.node.id }
        }
        return nil
    }

    /// Returns an atomic value edit, retaining IDs, sizes, subtrees and world geometry.
    public static func reparenting(_ document: DesignDocument, pageID: UUID,
                                  selection: Set<UUID>, to targetID: UUID?) throws -> DesignDocument {
        guard !selection.isEmpty else { return document }
        guard let pageIndex = document.pages.firstIndex(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        let scene = SceneIndex(page: document.pages[pageIndex])
        let roots = try scene.roots(for: selection)
        let rootIDs = Set(roots.map { $0.node.id })
        var targetWorld = CGAffineTransform.identity
        if let targetID {
            guard let target = scene.byID[targetID], target.node.kind == .frame,
                  !rootIDs.contains(targetID), rootIDs.isDisjoint(with: target.ancestors) else {
                throw LayerEditError.invalidSelection
            }
            guard target.isEditable else { throw LayerEditError.lockedOrHidden }
            guard target.hasValidGeometry else { throw LayerEditError.invalidGeometry }
            targetWorld = target.world
        }
        guard !roots.contains(where: { $0.node.kind == .frame }) else {
            return try validated(document)
        }

        // Prepare every conversion before removing anything from the candidate value.
        var moved: [DesignNode] = []
        for root in roots where root.nearestFrameID != targetID {
            let local = root.world.concatenating(targetWorld.inverted())
            guard validTransform(local) else { throw LayerEditError.invalidGeometry }
            var node = root.node
            let center = CGPoint(x: node.frame.width / 2, y: node.frame.height / 2).applying(local)
            node.frame.origin = CGPoint(x: center.x - node.frame.width / 2, y: center.y - node.frame.height / 2)
            node.rotation = atan2(local.b, local.a) * 180 / .pi
            guard validGeometry(node) else { throw LayerEditError.invalidGeometry }
            moved.append(node)
        }
        guard !moved.isEmpty else { return try validated(document) }
        var candidate = document
        for node in moved { candidate.removeNode(id: node.id) }
        for node in moved { try candidate.insertNode(node, into: pageID, parentID: targetID) }
        return try validated(candidate)
    }

    private static func contains(_ point: CGPoint, in entry: Entry) -> Bool {
        let local = point.applying(entry.world.inverted())
        return local.x.isFinite && local.y.isFinite &&
            CGRect(origin: .zero, size: entry.node.frame.size).contains(local)
    }

    private static func validPoint(_ point: CGPoint) -> Bool {
        [point.x, point.y].allSatisfy { $0.isFinite && (-1e9...1e9).contains($0) }
    }

    private static func validGeometry(_ node: DesignNode) -> Bool {
        validPoint(node.frame.origin) &&
            [node.frame.size.width, node.frame.size.height].allSatisfy { $0.isFinite && (0...1e7).contains($0) } &&
            node.rotation.isFinite && (-1e9...1e9).contains(node.rotation)
    }

    private static func validTransform(_ transform: CGAffineTransform) -> Bool {
        [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite) &&
            (transform.a * transform.d - transform.b * transform.c) != 0
    }

    private static func validated(_ document: DesignDocument) throws -> DesignDocument {
        do { _ = try DocumentCodec.encode(document) }
        catch let error as DocumentCodecError {
            switch error {
            case .invalidContent(let field) where ["point", "nodeSize", "rotation"].contains(field):
                throw LayerEditError.invalidGeometry
            default: throw error
            }
        }
        return document
    }
}

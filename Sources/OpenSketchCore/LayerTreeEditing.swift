import Foundation
import CoreGraphics

/// Positions use the sidebar's front-to-back display order.
public enum LayerDropDestination: Equatable, Sendable {
    case above(UUID), below(UUID), inside(UUID), pageEnd
}

public enum LayerTreeEditing {
    private struct Entry {
        let node: DesignNode
        let ancestors: [UUID]
        let world: CGAffineTransform
        let editable: Bool
        var parentID: UUID? { ancestors.last }
    }
    private struct Move {
        let pageIndex: Int
        let parentID: UUID?
        let nodes: [DesignNode]
        let ids: Set<UUID>
    }

    /// Source eligibility is independent of any particular destination's coordinate limits.
    public static func canDrag(_ document: DesignDocument, pageID: UUID, selection: Set<UUID>) -> Bool {
        (try? prepare(document, pageID: pageID, selection: selection, to: nil)) != nil
    }

    /// Hover validation is read-only and does not encode a document or allocate identities.
    public static func canMove(_ document: DesignDocument, pageID: UUID, selection: Set<UUID>,
                               to destination: LayerDropDestination) -> Bool {
        (try? prepare(document, pageID: pageID, selection: selection, to: destination)) != nil
    }

    public static func move(_ document: DesignDocument, pageID: UUID, selection: Set<UUID>,
                            to destination: LayerDropDestination) throws -> LayerEditResult {
        _ = try DocumentCodec.encode(document)
        let move = try prepare(document, pageID: pageID, selection: selection, to: destination)
        var candidate = document
        func removing(_ nodes: [DesignNode]) -> [DesignNode] {
            nodes.compactMap { node in
                guard !move.ids.contains(node.id) else { return nil }
                var copy = node
                if !copy.children.isEmpty { copy.children = removing(copy.children) }
                return copy
            }
        }
        candidate.pages[move.pageIndex].nodes = removing(candidate.pages[move.pageIndex].nodes)
        var siblings = move.parentID.flatMap { candidate.node(id: $0)?.children }
            ?? candidate.pages[move.pageIndex].nodes
        let insertion: Int
        switch destination {
        case .above(let anchor), .below(let anchor):
            guard let index = siblings.firstIndex(where: { $0.id == anchor }) else { throw LayerEditError.invalidSelection }
            insertion = index + (destination == .above(anchor) ? 1 : 0)
        case .inside: insertion = siblings.count
        case .pageEnd: insertion = 0
        }
        siblings.insert(contentsOf: move.nodes, at: insertion)
        if let parentID = move.parentID { candidate.updateNode(id: parentID) { $0.children = siblings } }
        else { candidate.pages[move.pageIndex].nodes = siblings }
        _ = try DocumentCodec.encode(candidate)
        return LayerEditResult(document: candidate, selection: move.ids)
    }

    private static func prepare(_ document: DesignDocument, pageID: UUID, selection: Set<UUID>,
                                to destination: LayerDropDestination?) throws -> Move {
        guard !selection.isEmpty, let pageIndex = document.pages.firstIndex(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        var entries: [Entry] = [], byID: [UUID: Entry] = [:]
        func visit(_ nodes: [DesignNode], ancestors: [UUID], world: CGAffineTransform, editable: Bool) throws {
            guard nodes.isEmpty || ancestors.count < DocumentCodec.maximumDepth else { throw DocumentCodecError.limitExceeded("nodeDepth") }
            for node in nodes {
                guard entries.count < DocumentCodec.maximumNodeCount else { throw DocumentCodecError.limitExceeded("nodeCount") }
                let transform = SceneGeometry.localTransform(for: node).concatenating(world)
                let entry = Entry(node: node, ancestors: ancestors, world: transform,
                                  editable: editable && node.isVisible && !node.isLocked)
                guard byID.updateValue(entry, forKey: node.id) == nil else { throw LayerEditError.invalidSelection }
                entries.append(entry)
                try visit(node.children, ancestors: ancestors + [node.id], world: transform, editable: entry.editable)
            }
        }
        try visit(document.pages[pageIndex].nodes, ancestors: [], world: .identity, editable: true)
        guard selection.isSubset(of: Set(byID.keys)) else { throw LayerEditError.invalidSelection }
        let roots = entries.filter { selection.contains($0.node.id) && selection.isDisjoint(with: $0.ancestors) }
        let rootIDs = Set(roots.map { $0.node.id })
        guard roots.allSatisfy(\.editable) else { throw LayerEditError.lockedOrHidden }
        for root in roots {
            try validateGeometry(root.node)
            try validateTransform(root.world)
        }
        guard let destination else {
            return Move(pageIndex: pageIndex, parentID: nil, nodes: roots.map(\.node), ids: rootIDs)
        }
        let parentID: UUID?
        switch destination {
        case .above(let anchor), .below(let anchor), .inside(let anchor):
            guard let entry = byID[anchor], !rootIDs.contains(anchor), rootIDs.isDisjoint(with: entry.ancestors) else {
                throw LayerEditError.invalidSelection
            }
            if destination == .inside(anchor) {
                guard entry.node.kind == .frame || entry.node.kind == .group else { throw LayerEditError.invalidSelection }
                parentID = anchor
            } else { parentID = entry.parentID }
        case .pageEnd: parentID = nil
        }
        let parent = parentID.flatMap { byID[$0] }
        if let parent {
            guard parent.editable else { throw LayerEditError.lockedOrHidden }
            try validateGeometry(parent.node)
        }
        let targetWorld = parent?.world ?? .identity
        try validateTransform(targetWorld)
        func height(_ node: DesignNode) -> Int { 1 + (node.children.map(height).max() ?? 0) }
        let parentDepth = parent.map { $0.ancestors.count + 1 } ?? 0
        let moved = try roots.map { entry in
            guard parentDepth + height(entry.node) <= DocumentCodec.maximumDepth else { throw DocumentCodecError.limitExceeded("nodeDepth") }
            // Reordering within a parent must not introduce floating point changes.
            guard entry.parentID != parentID else { return entry.node }
            let local = entry.world.concatenating(targetWorld.inverted())
            try validateTransform(local)
            var node = entry.node
            let center = CGPoint(x: node.frame.width / 2, y: node.frame.height / 2).applying(local)
            node.frame.origin = CGPoint(x: center.x - node.frame.width / 2, y: center.y - node.frame.height / 2)
            node.rotation = atan2(local.b, local.a) * 180 / .pi
            try validateGeometry(node)
            return node
        }
        return Move(pageIndex: pageIndex, parentID: parentID, nodes: moved, ids: rootIDs)
    }

    private static func validateGeometry(_ node: DesignNode) throws {
        guard [node.frame.origin.x, node.frame.origin.y].allSatisfy({ $0.isFinite && (-1e9...1e9).contains($0) }),
              [node.frame.size.width, node.frame.size.height].allSatisfy({ $0.isFinite && (0...1e7).contains($0) }),
              node.rotation.isFinite, (-1e9...1e9).contains(node.rotation) else { throw LayerEditError.invalidGeometry }
    }
    private static func validateTransform(_ transform: CGAffineTransform) throws {
        guard [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite),
              transform.a * transform.d - transform.b * transform.c != 0 else { throw LayerEditError.invalidGeometry }
    }
}

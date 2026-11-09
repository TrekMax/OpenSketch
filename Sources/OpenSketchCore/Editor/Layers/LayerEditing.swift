import Foundation
import CoreGraphics

public enum LayerOrder: String, CaseIterable, Sendable {
    case forward, backward, front, back
}

public enum LayerAlignment: String, CaseIterable, Sendable {
    case left, horizontalCenter, right, top, verticalCenter, bottom
}

public enum LayerAxis: String, CaseIterable, Sendable {
    case horizontal, vertical
}

public enum LayerCommand: Equatable, Sendable {
    case group, ungroup
    case order(LayerOrder)
    case align(LayerAlignment)
    case distribute(LayerAxis)
    case boolean(BooleanOperation)
}

public struct LayerEditResult: Equatable, Sendable {
    public var document: DesignDocument
    public var selection: Set<UUID>

    public init(document: DesignDocument, selection: Set<UUID>) {
        self.document = document
        self.selection = selection
    }
}

public enum LayerEditError: Error, Equatable {
    case invalidSelection, differentParents, lockedOrHidden, styledGroup, invalidGeometry
}

public enum LayerEditing {
    private struct Entry {
        let node: DesignNode
        let ancestors: [UUID]
        let parentTransform: CGAffineTransform
        let worldTransform: CGAffineTransform
        let isEditable: Bool
        var parentID: UUID? { ancestors.last }
    }

    private struct Preparation {
        let pageIndex: Int
        let roots: [Entry]
        let groupBounds: CGRect?
    }

    /// Checks selection, editability and operation geometry without allocating IDs or encoding.
    /// `apply` remains authoritative for document-format and encoded-size limits.
    public static func canApply(_ command: LayerCommand, to document: DesignDocument,
                                pageID: UUID, selection: Set<UUID>) -> Bool {
        do {
            let prepared = try prepare(command, document: document, pageID: pageID, selection: selection, validateDocument: false)
            // Group preparation validates its geometry and topology without allocating an identity.
            if command != .group {
                _ = try perform(command, document: document, prepared: prepared, updateDocument: false)
            }
            return true
        } catch {
            return false
        }
    }

    public static func apply(_ command: LayerCommand, to document: DesignDocument,
                             pageID: UUID, selection: Set<UUID>) throws -> LayerEditResult {
        let prepared = try prepare(command, document: document, pageID: pageID, selection: selection)
        let result = try perform(command, document: document, prepared: prepared)
        try validate(result.document)
        return result
    }

    private static func validate(_ document: DesignDocument) throws {
        do { _ = try DocumentCodec.encode(document) }
        catch let error as DocumentCodecError {
            switch error {
            case .invalidContent(let field) where ["point", "nodeSize", "rotation"].contains(field):
                throw LayerEditError.invalidGeometry
            default: throw error
            }
        }
    }

    private static func prepare(_ command: LayerCommand, document: DesignDocument,
                                pageID: UUID, selection: Set<UUID>, validateDocument: Bool = true) throws -> Preparation {
        guard !selection.isEmpty, let pageIndex = document.pages.firstIndex(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        if validateDocument { try validate(document) }
        var entries: [Entry] = []
        func visit(_ nodes: [DesignNode], ancestors: [UUID], transform: CGAffineTransform, editable: Bool) {
            for node in nodes {
                let world = SceneGeometry.localTransform(for: node).concatenating(transform)
                let canEdit = editable && node.isVisible && !node.isLocked
                entries.append(Entry(node: node, ancestors: ancestors, parentTransform: transform,
                                     worldTransform: world, isEditable: canEdit))
                visit(node.children, ancestors: ancestors + [node.id], transform: world, editable: canEdit)
            }
        }
        visit(document.pages[pageIndex].nodes, ancestors: [], transform: .identity, editable: true)
        guard selection.isSubset(of: Set(entries.map { $0.node.id })) else {
            throw LayerEditError.invalidSelection
        }
        let roots = entries.filter { selection.contains($0.node.id) && selection.isDisjoint(with: $0.ancestors) }
        guard roots.allSatisfy(\.isEditable) else { throw LayerEditError.lockedOrHidden }
        let requiredIDs = Set(roots.flatMap { $0.ancestors + [$0.node.id] })
        for entry in entries where requiredIDs.contains(entry.node.id) {
            try validateFrame(entry.node.frame)
            try validateRotation(entry.node.rotation)
            guard [entry.worldTransform.a, entry.worldTransform.b, entry.worldTransform.c,
                   entry.worldTransform.d, entry.worldTransform.tx, entry.worldTransform.ty].allSatisfy(\.isFinite) else {
                throw LayerEditError.invalidGeometry
            }
        }
        switch command {
        case .group, .ungroup, .order:
            guard roots.allSatisfy({ $0.parentID == roots[0].parentID }) else {
                throw LayerEditError.differentParents
            }
        default: break
        }
        switch command {
        case .group, .align:
            guard roots.count >= 2 else { throw LayerEditError.invalidSelection }
        case .distribute:
            guard roots.count >= 3 else { throw LayerEditError.invalidSelection }
        case .ungroup:
            guard roots.allSatisfy({ $0.node.kind == .group }) else { throw LayerEditError.invalidSelection }
            guard roots.allSatisfy({ $0.node.style.fill == nil && $0.node.style.stroke == nil &&
                $0.node.style.opacity == 1 }) else { throw LayerEditError.styledGroup }
        case .order: break
        case .boolean: break
        }
        var groupBounds: CGRect?
        if command == .group {
            let bounds = try union(roots.map { try geometricBounds($0.node, transform: SceneGeometry.localTransform(for: $0.node)) })
            try validateFrame(bounds)
            for root in roots {
                var local = root.node.frame
                local.origin.x -= bounds.minX; local.origin.y -= bounds.minY
                try validateFrame(local)
            }
            let selectedIDs = Set(roots.map { $0.node.id })
            guard !entries.contains(where: { entry in
                entry.ancestors.count + 2 > DocumentCodec.maximumDepth &&
                    (!selectedIDs.isDisjoint(with: entry.ancestors) || selectedIDs.contains(entry.node.id))
            }) else { throw DocumentCodecError.limitExceeded("nodeDepth") }
            let totalCount = document.pages.reduce(0) { $0 + SceneGeometry.traversal(in: $1).count }
            guard totalCount < DocumentCodec.maximumNodeCount else { throw DocumentCodecError.limitExceeded("nodeCount") }
            groupBounds = bounds
        }
        return Preparation(pageIndex: pageIndex, roots: roots, groupBounds: groupBounds)
    }

    private static func perform(_ command: LayerCommand, document: DesignDocument,
                                prepared: Preparation, updateDocument: Bool = true) throws -> LayerEditResult {
        var candidate = document
        let roots = prepared.roots
        let selectedIDs = Set(roots.map { $0.node.id })
        var resultSelection = selectedIDs
        var translatedFrames: [UUID: CGRect] = [:]
        switch command {
        case .group:
            guard let bounds = prepared.groupBounds else { throw LayerEditError.invalidGeometry }
            let children = roots.map { entry in
                var child = entry.node
                child.frame.origin.x -= bounds.minX; child.frame.origin.y -= bounds.minY
                return child
            }
            let group = DesignNode(name: "编组", kind: .group, frame: bounds, children: children)
            var siblings = siblings(for: roots[0], in: document.pages[prepared.pageIndex])
            guard let lastIndex = siblings.lastIndex(where: { selectedIDs.contains($0.id) }) else {
                throw LayerEditError.invalidSelection
            }
            let insertionIndex = siblings[..<lastIndex].filter { !selectedIDs.contains($0.id) }.count
            siblings.removeAll { selectedIDs.contains($0.id) }
            siblings.insert(group, at: insertionIndex)
            replaceSiblings(siblings, parentID: roots[0].parentID, pageIndex: prepared.pageIndex, in: &candidate)
            resultSelection = [group.id]
        case .ungroup:
            var ungrouped: [DesignNode] = []
            var childIDs = Set<UUID>()
            for node in siblings(for: roots[0], in: document.pages[prepared.pageIndex]) {
                guard selectedIDs.contains(node.id) else { ungrouped.append(node); continue }
                let transform = SceneGeometry.localTransform(for: node)
                for original in node.children {
                    var child = original
                    let center = CGPoint(x: child.frame.midX, y: child.frame.midY).applying(transform)
                    child.frame.origin = CGPoint(x: center.x - child.frame.width / 2,
                                                 y: center.y - child.frame.height / 2)
                    child.rotation += node.rotation
                    try validateFrame(child.frame)
                    try validateRotation(child.rotation)
                    ungrouped.append(child)
                    childIDs.insert(child.id)
                }
            }
            if updateDocument {
                replaceSiblings(ungrouped, parentID: roots[0].parentID, pageIndex: prepared.pageIndex, in: &candidate)
            }
            resultSelection = childIDs
        case .order(let order):
            guard updateDocument else { break }
            var nodes = siblings(for: roots[0], in: document.pages[prepared.pageIndex])
            switch order {
            case .front: nodes = nodes.filter { !selectedIDs.contains($0.id) } + nodes.filter { selectedIDs.contains($0.id) }
            case .back: nodes = nodes.filter { selectedIDs.contains($0.id) } + nodes.filter { !selectedIDs.contains($0.id) }
            case .forward:
                if nodes.count > 1 {
                    for index in (0..<(nodes.count - 1)).reversed() where selectedIDs.contains(nodes[index].id) &&
                        !selectedIDs.contains(nodes[index + 1].id) {
                        nodes.swapAt(index, index + 1)
                    }
                }
            case .backward:
                for index in nodes.indices.dropFirst() where selectedIDs.contains(nodes[index].id) &&
                    !selectedIDs.contains(nodes[index - 1].id) {
                    nodes.swapAt(index, index - 1)
                }
            }
            replaceSiblings(nodes, parentID: roots[0].parentID, pageIndex: prepared.pageIndex, in: &candidate)
        case .align(let alignment):
            let bounds = try roots.map { try geometricBounds($0.node, transform: $0.worldTransform) }
            let target = try union(bounds)
            for (entry, rect) in zip(roots, bounds) {
                let delta: CGPoint = switch alignment {
                case .left: CGPoint(x: target.minX - rect.minX, y: 0)
                case .horizontalCenter: CGPoint(x: target.midX - rect.midX, y: 0)
                case .right: CGPoint(x: target.maxX - rect.maxX, y: 0)
                case .top: CGPoint(x: 0, y: target.minY - rect.minY)
                case .verticalCenter: CGPoint(x: 0, y: target.midY - rect.midY)
                case .bottom: CGPoint(x: 0, y: target.maxY - rect.maxY)
                }
                translatedFrames[entry.node.id] = try translatedFrame(entry, by: delta)
            }
        case .distribute(let axis):
            let spatial = try roots.enumerated().map { index, entry in
                (index: index, entry: entry, bounds: try geometricBounds(entry.node, transform: entry.worldTransform))
            }.sorted { first, second in
                let a = axis == .horizontal ? first.bounds.minX : first.bounds.minY
                let b = axis == .horizontal ? second.bounds.minX : second.bounds.minY
                return a == b ? first.index < second.index : a < b
            }
            guard let first = spatial.first, let last = spatial.last else { throw LayerEditError.invalidSelection }
            let start = axis == .horizontal ? first.bounds.minX : first.bounds.minY
            let end = axis == .horizontal ? last.bounds.maxX : last.bounds.maxY
            let totalSize = spatial.reduce(CGFloat.zero) { $0 + (axis == .horizontal ? $1.bounds.width : $1.bounds.height) }
            let gap = (end - start - totalSize) / CGFloat(spatial.count - 1)
            var cursor = start
            for (index, item) in spatial.enumerated() {
                if index > 0 && index < spatial.count - 1 {
                    let current = axis == .horizontal ? item.bounds.minX : item.bounds.minY
                    let delta = axis == .horizontal ? CGPoint(x: cursor - current, y: 0) : CGPoint(x: 0, y: cursor - current)
                    translatedFrames[item.entry.node.id] = try translatedFrame(item.entry, by: delta)
                }
                cursor += (axis == .horizontal ? item.bounds.width : item.bounds.height) + gap
            }
        case .boolean:
            throw LayerEditError.invalidSelection
        }
        if updateDocument && !translatedFrames.isEmpty {
            func update(_ nodes: inout [DesignNode]) {
                for index in nodes.indices {
                    if let frame = translatedFrames[nodes[index].id], frame != nodes[index].frame {
                        nodes[index].frame = frame
                    }
                    if !nodes[index].children.isEmpty { update(&nodes[index].children) }
                }
            }
            update(&candidate.pages[prepared.pageIndex].nodes)
        }
        return LayerEditResult(document: candidate, selection: resultSelection)
    }

    private static func siblings(for entry: Entry, in page: DesignPage) -> [DesignNode] {
        guard let parentID = entry.parentID else { return page.nodes }
        return SceneGeometry.traversal(in: page).first { $0.id == parentID }?.children ?? []
    }

    private static func replaceSiblings(_ nodes: [DesignNode], parentID: UUID?, pageIndex: Int,
                                        in document: inout DesignDocument) {
        if let parentID { document.updateNode(id: parentID) { $0.children = nodes } }
        else { document.pages[pageIndex].nodes = nodes }
    }

    private static func geometricBounds(_ node: DesignNode, transform: CGAffineTransform) throws -> CGRect {
        let bounds = CGRect(origin: .zero, size: node.frame.size).applying(transform)
        guard [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY, bounds.width, bounds.height].allSatisfy(\.isFinite) else {
            throw LayerEditError.invalidGeometry
        }
        return bounds
    }

    private static func union(_ bounds: [CGRect]) throws -> CGRect {
        guard let first = bounds.first else { throw LayerEditError.invalidSelection }
        let result = bounds.dropFirst().reduce(first) { $0.union($1) }
        guard [result.minX, result.minY, result.maxX, result.maxY].allSatisfy(\.isFinite) else {
            throw LayerEditError.invalidGeometry
        }
        return result
    }

    private static func validateFrame(_ frame: CGRect) throws {
        guard [frame.origin.x, frame.origin.y].allSatisfy({ $0.isFinite && (-1e9...1e9).contains($0) }),
              [frame.size.width, frame.size.height].allSatisfy({ $0.isFinite && (0...1e7).contains($0) }) else {
            throw LayerEditError.invalidGeometry
        }
    }

    private static func validateRotation(_ rotation: Double) throws {
        guard rotation.isFinite, (-1e9...1e9).contains(rotation) else { throw LayerEditError.invalidGeometry }
    }

    private static func translatedFrame(_ entry: Entry, by delta: CGPoint) throws -> CGRect {
        guard delta.x.isFinite, delta.y.isFinite else { throw LayerEditError.invalidGeometry }
        guard delta != .zero else { return entry.node.frame }
        let inverse = entry.parentTransform.inverted()
        let local = CGPoint(x: inverse.a * delta.x + inverse.c * delta.y,
                            y: inverse.b * delta.x + inverse.d * delta.y)
        var frame = entry.node.frame
        frame.origin.x += local.x; frame.origin.y += local.y
        try validateFrame(frame)
        return frame
    }
}

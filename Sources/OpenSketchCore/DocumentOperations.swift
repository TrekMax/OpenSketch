import Foundation

public enum DocumentOperationError: Error, Equatable {
    case pageNotFound, parentNotFound, invalidParent, invalidIndex, duplicateID
}

extension DesignDocument {
    public func node(id: UUID) -> DesignNode? {
        for page in pages {
            if let found = Self.find(id: id, in: page.nodes) { return found }
        }
        return nil
    }

    public func pageContaining(nodeID: UUID) -> UUID? {
        pages.first { Self.find(id: nodeID, in: $0.nodes) != nil }?.id
    }

    /// Returns nil for a root node or a missing node.
    public func parentID(of nodeID: UUID) -> UUID? {
        func findParent(in nodes: [DesignNode]) -> UUID? {
            for node in nodes {
                if node.children.contains(where: { $0.id == nodeID }) { return node.id }
                if let found = findParent(in: node.children) { return found }
            }
            return nil
        }
        for page in pages {
            if let found = findParent(in: page.nodes) { return found }
        }
        return nil
    }

    @discardableResult
    public mutating func updateNode(id: UUID, _ update: (inout DesignNode) -> Void) -> Bool {
        for index in pages.indices {
            if Self.update(id: id, in: &pages[index].nodes, update) { return true }
        }
        return false
    }

    /// Inserts at the given bottom-to-top index (nil appends). Failure leaves self unchanged.
    public mutating func insertNode(_ node: DesignNode, into pageID: UUID,
                                    parentID: UUID? = nil, at index: Int? = nil) throws {
        guard let pageIndex = pages.firstIndex(where: { $0.id == pageID }) else {
            throw DocumentOperationError.pageNotFound
        }
        var ids = Set([id] + pages.map(\.id))
        func collect(_ nodes: [DesignNode]) {
            for node in nodes { ids.insert(node.id); collect(node.children) }
        }
        for page in pages { collect(page.nodes) }
        func check(_ node: DesignNode) throws {
            guard ids.insert(node.id).inserted else { throw DocumentOperationError.duplicateID }
            for child in node.children { try check(child) }
        }
        try check(node)
        if let parentID {
            guard let parent = Self.find(id: parentID, in: pages[pageIndex].nodes) else {
                throw DocumentOperationError.parentNotFound
            }
            guard parent.kind == .frame || parent.kind == .group else { throw DocumentOperationError.invalidParent }
            let insertionIndex = index ?? parent.children.count
            guard (0...parent.children.count).contains(insertionIndex) else { throw DocumentOperationError.invalidIndex }
            Self.update(id: parentID, in: &pages[pageIndex].nodes) { $0.children.insert(node, at: insertionIndex) }
        } else {
            let insertionIndex = index ?? pages[pageIndex].nodes.count
            guard (0...pages[pageIndex].nodes.count).contains(insertionIndex) else { throw DocumentOperationError.invalidIndex }
            pages[pageIndex].nodes.insert(node, at: insertionIndex)
        }
    }

    @discardableResult
    public mutating func removeNode(id: UUID) -> DesignNode? {
        func remove(in nodes: inout [DesignNode]) -> DesignNode? {
            for index in nodes.indices {
                if nodes[index].id == id { return nodes.remove(at: index) }
                if let removed = remove(in: &nodes[index].children) { return removed }
            }
            return nil
        }
        for index in pages.indices {
            if let removed = remove(in: &pages[index].nodes) { return removed }
        }
        return nil
    }

    private static func find(id: UUID, in nodes: [DesignNode]) -> DesignNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id: id, in: node.children) { return found }
        }
        return nil
    }

    @discardableResult
    private static func update(id: UUID, in nodes: inout [DesignNode],
                               _ update: (inout DesignNode) -> Void) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id { update(&nodes[index]); return true }
            if Self.update(id: id, in: &nodes[index].children, update) { return true }
        }
        return false
    }
}

extension DesignNode {
    /// Copies all editable values, assigning fresh UUIDs to the whole subtree.
    public func cloned() -> DesignNode {
        var copy = self
        copy.id = UUID()
        copy.children = children.map { $0.cloned() }
        return copy
    }
}

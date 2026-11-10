import Foundation

public enum DesignSystemEditingError: Error, Equatable, Sendable {
    case nodeNotFound
    case definitionNotFound
    case styleNotFound
    case invalidDefinition
}

public extension DesignDocument {
    @discardableResult
    mutating func makeComponentDefinition(from nodeID: UUID, name: String) throws -> ComponentDefinition {
        guard let node = node(id: nodeID), !name.isEmpty else { throw DesignSystemEditingError.nodeNotFound }
        let definition = ComponentDefinition(name: name, root: node.cloned())
        componentDefinitions.append(definition)
        return definition
    }

    mutating func makeComponentInstance(definitionID: UUID, in pageID: UUID, at origin: CGPoint? = nil) throws -> DesignNode {
        guard let definition = componentDefinitions.first(where: { $0.id == definitionID }) else {
            throw DesignSystemEditingError.definitionNotFound
        }
        var instance = definition.root.cloned()
        instance.componentDefinitionID = definition.id
        instance.name = "\(definition.name) Instance"
        if let origin { instance.frame.origin = origin }
        try insertNode(instance, into: pageID)
        return instance
    }

    @discardableResult
    mutating func makeSharedStyle(from nodeID: UUID, name: String) throws -> SharedStyle {
        guard let node = node(id: nodeID), !name.isEmpty else { throw DesignSystemEditingError.nodeNotFound }
        let shared = SharedStyle(name: name, style: node.style)
        sharedStyles.append(shared)
        return shared
    }

    mutating func applySharedStyle(_ styleID: UUID, to nodeID: UUID) throws {
        guard let style = sharedStyles.first(where: { $0.id == styleID }) else { throw DesignSystemEditingError.styleNotFound }
        guard updateNode(id: nodeID, { node in node.style = style.style; node.sharedStyleID = style.id }) else {
            throw DesignSystemEditingError.nodeNotFound
        }
    }
}

import Foundation

public enum PluginOperationExecutionError: Error, Equatable, Sendable {
    case notApproved
    case missingCapability(PluginCapability)
    case invalidParameter(String)
    case nodeNotFound(UUID)
    case unsupportedOperation(PluginOperationKind)
}

public struct PluginOperationExecutionResult: Equatable, Sendable {
    public var document: DesignDocument
    public var auditEvents: [PluginAuditEvent]

    public init(document: DesignDocument, auditEvents: [PluginAuditEvent]) {
        self.document = document; self.auditEvents = auditEvents
    }
}

/// Applies a complete plan to a candidate document and publishes it only after
/// every operation succeeds. Callers can therefore use the original document
/// as the rollback value without creating a partially-applied history entry.
public enum PluginOperationExecutor {
    public static func execute(_ plan: PluginOperationPlan, on document: DesignDocument,
                               plugin: PluginManifest, approved: Bool) throws -> PluginOperationExecutionResult {
        guard approved else { throw PluginOperationExecutionError.notApproved }
        guard plugin.apiVersion == 1 else { throw PluginPermissionError.unsupportedAPIVersion }
        var candidate = document
        var events: [PluginAuditEvent] = []
        do {
            for operation in plan.operations {
                try requireCapability(for: operation.kind, plugin: plugin)
                try apply(operation, to: &candidate)
                events.append(PluginAuditEvent(pluginID: plugin.id, operation: operation.kind, approved: true))
            }
        } catch {
            events.append(contentsOf: plan.operations.dropFirst(events.count).map {
                PluginAuditEvent(pluginID: plugin.id, operation: $0.kind, approved: false)
            })
            throw error
        }
        return PluginOperationExecutionResult(document: candidate, auditEvents: events)
    }

    private static func requireCapability(for kind: PluginOperationKind, plugin: PluginManifest) throws {
        let required: PluginCapability = switch kind {
        case .queryDocument: .readDocument
        case .export: .export
        default: .writeDocument
        }
        guard plugin.capabilities.contains(required) else { throw PluginOperationExecutionError.missingCapability(required) }
    }

    private static func apply(_ operation: PluginOperation, to document: inout DesignDocument) throws {
        switch operation.kind {
        case .queryDocument:
            return
        case .renameNode:
            guard operation.nodeIDs.count == 1, let name = operation.parameters["name"], !name.isEmpty else {
                throw PluginOperationExecutionError.invalidParameter("name")
            }
            guard document.updateNode(id: operation.nodeIDs[0], { $0.name = name }) else {
                throw PluginOperationExecutionError.nodeNotFound(operation.nodeIDs[0])
            }
        case .moveNode:
            let dx = try number("dx", in: operation.parameters)
            let dy = try number("dy", in: operation.parameters)
            guard !operation.nodeIDs.isEmpty else { throw PluginOperationExecutionError.invalidParameter("nodeIDs") }
            for id in operation.nodeIDs {
                guard document.updateNode(id: id, { $0.frame.origin.x += dx; $0.frame.origin.y += dy }) else {
                    throw PluginOperationExecutionError.nodeNotFound(id)
                }
            }
        case .updateNode:
            guard operation.nodeIDs.count == 1 else { throw PluginOperationExecutionError.invalidParameter("nodeIDs") }
            let id = operation.nodeIDs[0]
            guard document.node(id: id) != nil else { throw PluginOperationExecutionError.nodeNotFound(id) }
            let parameters = operation.parameters
            guard document.updateNode(id: id, { node in
                if let name = parameters["name"] { node.name = name }
                if let x = Double(parameters["x"] ?? "") { node.frame.origin.x = x }
                if let y = Double(parameters["y"] ?? "") { node.frame.origin.y = y }
                if let width = Double(parameters["width"] ?? "") { node.frame.size.width = width }
                if let height = Double(parameters["height"] ?? "") { node.frame.size.height = height }
            }) else { throw PluginOperationExecutionError.nodeNotFound(id) }
        case .deleteNode:
            guard !operation.nodeIDs.isEmpty else { throw PluginOperationExecutionError.invalidParameter("nodeIDs") }
            for id in operation.nodeIDs {
                guard document.removeNode(id: id) != nil else { throw PluginOperationExecutionError.nodeNotFound(id) }
            }
        case .createNode:
            guard let kind = NodeKind(rawValue: operation.parameters["kind"] ?? "") else {
                throw PluginOperationExecutionError.invalidParameter("kind")
            }
            let name = operation.parameters["name"] ?? kind.rawValue
            let x = try number("x", in: operation.parameters, default: 0)
            let y = try number("y", in: operation.parameters, default: 0)
            let width = try number("width", in: operation.parameters, default: 100)
            let height = try number("height", in: operation.parameters, default: 100)
            guard let defaultPageID = document.pages.first?.id else { throw PluginOperationExecutionError.invalidParameter("pageID") }
            let pageID = try uuid("pageID", in: operation.parameters, default: defaultPageID)
            let parentID = try optionalUUID("parentID", in: operation.parameters)
            try document.insertNode(DesignNode(name: name, kind: kind, frame: CGRect(x: x, y: y, width: width, height: height)), into: pageID, parentID: parentID)
        case .groupNodes:
            guard let pageID = operation.parameters["pageID"].flatMap(UUID.init(uuidString:)) ?? document.pages.first?.id else {
                throw PluginOperationExecutionError.invalidParameter("pageID")
            }
            do { document = try LayerEditing.apply(.group, to: document, pageID: pageID, selection: Set(operation.nodeIDs)).document }
            catch { throw PluginOperationExecutionError.invalidParameter("groupNodes") }
        case .export:
            return
        }
    }

    private static func number(_ key: String, in parameters: [String: String], default fallback: Double? = nil) throws -> Double {
        guard let raw = parameters[key] ?? fallback.map({ String(describing: $0) }), let value = Double(raw), value.isFinite else {
            throw PluginOperationExecutionError.invalidParameter(key)
        }
        return value
    }

    private static func uuid(_ key: String, in parameters: [String: String], default fallback: UUID? = nil) throws -> UUID {
        guard let value = parameters[key].flatMap(UUID.init(uuidString:)) ?? fallback else { throw PluginOperationExecutionError.invalidParameter(key) }
        return value
    }

    private static func optionalUUID(_ key: String, in parameters: [String: String]) throws -> UUID? {
        guard let raw = parameters[key] else { return nil }
        guard let value = UUID(uuidString: raw) else { throw PluginOperationExecutionError.invalidParameter(key) }
        return value
    }
}

import Foundation
import Testing
@testable import OpenSketchCore

struct PluginOperationExecutorTests {
    @Test func approvedPlanCommitsAsOneCandidateAndAuditsEachOperation() throws {
        let node = DesignNode(name: "Old", kind: .rectangle)
        let document = DesignDocument(pages: [DesignPage(nodes: [node])])
        let plugin = PluginManifest(id: "org.example.ai", name: "AI", kind: .operation, capabilities: [.readDocument, .writeDocument, .aiOperation])
        let plan = PluginOperationPlan(source: "ai", operations: [
            PluginOperation(kind: .renameNode, nodeIDs: [node.id], parameters: ["name": "New"]),
            PluginOperation(kind: .moveNode, nodeIDs: [node.id], parameters: ["dx": "8", "dy": "4"])
        ])
        let result = try PluginOperationExecutor.execute(plan, on: document, plugin: plugin, approved: true)
        #expect(result.document.node(id: node.id)?.name == "New")
        #expect(result.document.node(id: node.id)?.frame.origin == CGPoint(x: 8, y: 4))
        #expect(result.auditEvents.count == 2)
    }

    @Test func rejectedPlanLeavesOriginalDocumentUntouched() throws {
        let node = DesignNode(name: "Old", kind: .rectangle)
        let document = DesignDocument(pages: [DesignPage(nodes: [node])])
        let plugin = PluginManifest(id: "org.example.readonly", name: "Read Only", kind: .operation, capabilities: [.readDocument])
        let plan = PluginOperationPlan(source: "ai", operations: [PluginOperation(kind: .renameNode, nodeIDs: [node.id], parameters: ["name": "New"])])
        #expect(throws: PluginOperationExecutionError.notApproved) { try PluginOperationExecutor.execute(plan, on: document, plugin: plugin, approved: false) }
        #expect(document.node(id: node.id)?.name == "Old")
        #expect(throws: PluginOperationExecutionError.missingCapability(.writeDocument)) { try PluginOperationExecutor.execute(plan, on: document, plugin: plugin, approved: true) }
    }

    @Test func approvedPlanCanCreateNodesAtomically() throws {
        let page = DesignPage()
        let document = DesignDocument(pages: [page])
        let plugin = PluginManifest(id: "org.example.ai", name: "AI", kind: .operation, capabilities: [.readDocument, .writeDocument, .aiOperation])
        let plan = PluginOperationPlan(source: "mcp", operations: [
            PluginOperation(kind: .createNode, parameters: ["kind": "rectangle", "name": "Card", "pageID": page.id.uuidString]),
            PluginOperation(kind: .createNode, parameters: ["kind": "text", "name": "Title", "pageID": page.id.uuidString])
        ])
        let result = try PluginOperationExecutor.execute(plan, on: document, plugin: plugin, approved: true)
        #expect(result.document.pages[0].nodes.count == 2)
    }
}

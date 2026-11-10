import Foundation
import Testing
@testable import OpenSketchCore

struct M3OperationContractTests {
    @Test func operationPlanRoundTripsForMCPAndAIAdapters() throws {
        let id = UUID()
        let plan = PluginOperationPlan(source: "mcp.local", operations: [
            PluginOperation(kind: .moveNode, nodeIDs: [id], parameters: ["dx": "12", "dy": "4"]),
            PluginOperation(kind: .export, parameters: ["format": "svg"])
        ])
        #expect(try JSONDecoder().decode(PluginOperationPlan.self, from: JSONEncoder().encode(plan)) == plan)
    }

    @Test func auditEventsRecordApprovalDecisions() throws {
        let event = PluginAuditEvent(pluginID: "org.opensketch.ai", operation: .updateNode, approved: false)
        #expect(try JSONDecoder().decode(PluginAuditEvent.self, from: JSONEncoder().encode(event)) == event)
    }
}

import Foundation
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct PluginExportTests {
    @Test func builtInExecutorUsesThePluginContractForSVG() throws {
        let page = DesignPage(nodes: [DesignNode(kind: .rectangle)])
        let document = DesignDocument(pages: [page])
        let request = PluginExportRequest(snapshot: PluginDocumentSnapshot(document: document, pageID: page.id), outputExtension: "svg")
        let result = try BuiltInPluginExecutor.export(request, format: .svg, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        #expect(result.data?.count ?? 0 > 0)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func builtInExecutorRejectsMismatchedOutputExtension() throws {
        let page = DesignPage()
        let request = PluginExportRequest(snapshot: PluginDocumentSnapshot(document: DesignDocument(pages: [page]), pageID: page.id), outputExtension: "pdf")
        #expect(throws: (any Error).self) {
            try BuiltInPluginExecutor.export(request, format: .svg, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        }
    }
}

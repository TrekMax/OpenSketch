import Foundation
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct JPEGExportTests {
    @Test func jpegBuiltInPluginProducesJpegData() throws {
        let page = DesignPage(nodes: [DesignNode(kind: .rectangle)])
        let document = DesignDocument(pages: [page])
        let request = PluginExportRequest(snapshot: PluginDocumentSnapshot(document: document, pageID: page.id), outputExtension: "jpg")
        let result = try BuiltInPluginExecutor.export(request, format: .jpg, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        #expect(result.data?.prefix(2) == Data([0xFF, 0xD8]))
    }
}

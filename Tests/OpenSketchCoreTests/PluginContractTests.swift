import Foundation
import Testing
@testable import OpenSketchCore

struct PluginContractTests {
    @Test func builtInFormatsDeclareStableCapabilities() throws {
        let manifests = BuiltInPluginRegistry.manifests
        #expect(manifests.map(\.id) == [
            "org.opensketch.format.document",
            "org.opensketch.export.svg",
            "org.opensketch.export.png"
        ])
        #expect(manifests[1].capabilities == [.readDocument, .export])
        let data = try JSONEncoder().encode(manifests)
        #expect(try JSONDecoder().decode([PluginManifest].self, from: data) == manifests)
    }

    @Test func snapshotAndExportResultPreserveDocumentIdentityAndDiagnostics() throws {
        let document = DesignDocument.blank()
        let pageID = document.pages[0].id
        let snapshot = PluginDocumentSnapshot(document: document, pageID: pageID)
        let result = PluginExportResult(diagnostics: [PluginDiagnostic(severity: .warning, message: "unsupported filter")])
        #expect(try JSONDecoder().decode(PluginDocumentSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
        #expect(try JSONDecoder().decode(PluginExportResult.self, from: JSONEncoder().encode(result)) == result)
    }
}

import Foundation
import Testing
@testable import OpenSketchCore

struct PluginContractTests {
    @Test func builtInFormatsDeclareStableCapabilities() throws {
        let manifests = BuiltInPluginRegistry.manifests
        #expect(manifests.map(\.id) == [
            "org.opensketch.format.document",
            "org.opensketch.export.svg",
            "org.opensketch.export.png",
            "org.opensketch.export.jpg",
            "org.opensketch.export.pdf",
            "org.opensketch.export.html",
            "org.opensketch.export.assets",
            "org.opensketch.preview.local"
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

    @Test func pluginPackageManifestDefinesTheOpskpluginFormat() throws {
        let plugin = PluginManifest(id: "org.example.demo", name: "Demo", kind: .exporter,
                                    capabilities: [.readDocument, .export])
        let package = PluginPackageManifest(plugin: plugin, entrypoint: "Contents/DemoPlugin")
        try package.validate()
        let decoded = try JSONDecoder().decode(PluginPackageManifest.self, from: JSONEncoder().encode(package))
        #expect(decoded == package)
        #expect(PluginPackageManifest.packageExtension == "opskplugin")
        #expect(PluginPackageLayout.manifestPath == "plugin.json")
    }

    @Test func pluginPackageManifestRejectsInvalidIdentity() {
        let plugin = PluginManifest(id: "bad id", name: "Bad", kind: .exporter)
        let package = PluginPackageManifest(plugin: plugin, entrypoint: "Contents/Main")
        #expect(throws: PluginPackageError.invalidManifest) { try package.validate() }
    }
}

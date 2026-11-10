import Foundation
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct M3ExportTests {
    @Test func htmlExportContainsOfflineSVGRuntime() throws {
        let data = try M3PackageExporter.html(page: DesignPage(nodes: [DesignNode(kind: .rectangle)]), bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("<!doctype html>")); #expect(text.contains("atob")); #expect(text.contains("OpenSketch Preview"))
    }

    @Test func assetPackageContainsLayerManifest() throws {
        let page = DesignPage(nodes: [DesignNode(name: "Card", kind: .rectangle)])
        let data = try M3PackageExporter.assets(page: page)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? String == "org.opensketch.asset-package")
        #expect((object["layers"] as? [[String: Any]])?.first?["name"] as? String == "Card")
    }
}

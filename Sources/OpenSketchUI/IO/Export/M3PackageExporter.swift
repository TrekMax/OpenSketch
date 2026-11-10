import Foundation
import OpenSketchCore

@MainActor enum M3PackageExporter {
    static func html(page: DesignPage, bounds: CGRect) throws -> Data {
        let svg = try SVGExporter.data(page: page, bounds: bounds)
        let encoded = svg.base64EncodedString()
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OpenSketch Preview</title><style>html,body{margin:0;height:100%;background:#f5f5f5}svg{display:block;width:100%;height:100%}</style></head><body><div id="preview"></div><script>const svg=atob('\(encoded)');document.getElementById('preview').innerHTML=svg;</script></body></html>
        """
        return Data(html.utf8)
    }

    static func assets(page: DesignPage) throws -> Data {
        let payload: [String: Any] = [
            "format": "org.opensketch.asset-package",
            "version": 1,
            "page": page.name,
            "width": page.size.width,
            "height": page.size.height,
            "layers": SceneGeometry.traversal(in: page).map { ["id": $0.id.uuidString, "name": $0.name, "kind": $0.kind.rawValue] }
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}

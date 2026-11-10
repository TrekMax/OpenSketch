import Foundation
import OpenSketchCore

/// Captures geometry and validated output settings before a destination panel runs.
@MainActor struct PreparedExport {
    let snapshot: ExportSnapshot
    let options: ExportOptions
    let dimensions: CGSize
    var filename: String { Exporter.filename(name: snapshot.name, format: options.format, scale: options.scale) }

    func data() throws -> Data {
        let document = DesignDocument(name: snapshot.page.name, pages: [snapshot.page])
        let request = PluginExportRequest(snapshot: PluginDocumentSnapshot(document: document, pageID: snapshot.page.id), outputExtension: options.format.rawValue)
        let result = try BuiltInPluginExecutor.export(request, format: options.format, bounds: snapshot.bounds, scale: options.scale)
        guard let data = result.data else { throw EditorError.invalid("插件没有返回导出数据。") }
        return data
    }
}

extension EditorSession {
    /// Preview is read-only; input is finished by the controller only when exporting.
    func prepareExport(format: ExportFormat? = nil) throws -> PreparedExport {
        var options = exportOptions
        if let format { options.format = format }
        options.scope = options.resolvedScope(selection: selection)
        if options.format != .png { options.scale = 1 }
        let snapshot = try ExportSnapshot.make(page: page, selection: selection, scope: options.scope)
        let pixels = try Exporter.pixelSize(bounds: snapshot.bounds, scale: options.scale)
        let dimensions = options.format == .png ? pixels : snapshot.bounds.size
        return PreparedExport(snapshot: snapshot, options: options, dimensions: dimensions)
    }
}

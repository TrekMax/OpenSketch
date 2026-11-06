import Foundation

/// Captures geometry and validated output settings before a destination panel runs.
@MainActor struct PreparedExport {
    let snapshot: ExportSnapshot
    let options: ExportOptions
    let dimensions: CGSize
    var filename: String { Exporter.filename(name: snapshot.name, format: options.format, scale: options.scale) }

    func data() throws -> Data {
        switch options.format {
        case .png: try Exporter.png(page: snapshot.page, bounds: snapshot.bounds, scale: options.scale)
        case .pdf: try Exporter.pdf(page: snapshot.page, bounds: snapshot.bounds)
        }
    }
}

extension EditorSession {
    /// Preview is read-only; input is finished by the controller only when exporting.
    func prepareExport(format: ExportFormat? = nil) throws -> PreparedExport {
        var options = exportOptions
        if let format { options.format = format }
        options.scope = options.resolvedScope(selection: selection)
        if options.format == .pdf { options.scale = 1 }
        let snapshot = try ExportSnapshot.make(page: page, selection: selection, scope: options.scope)
        let pixels = try Exporter.pixelSize(bounds: snapshot.bounds, scale: options.scale)
        let dimensions = options.format == .pdf ? snapshot.bounds.size : pixels
        return PreparedExport(snapshot: snapshot, options: options, dimensions: dimensions)
    }
}

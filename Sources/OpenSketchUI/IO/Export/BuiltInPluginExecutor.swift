import Foundation
import OpenSketchCore

/// Host-side adapter for built-in format plugins. It is intentionally kept
/// behind the same manifest/snapshot contract used by future external plugins.
@MainActor enum BuiltInPluginExecutor {
    static func export(_ request: PluginExportRequest, format: ExportFormat,
                       bounds: CGRect, scale: Double) throws -> PluginExportResult {
        let expectedExtension = format.rawValue
        guard request.outputExtension == expectedExtension else {
            throw EditorError.invalid("插件输出格式与任务扩展名不匹配。")
        }
        let data: Data
        switch format {
        case .png: data = try Exporter.png(page: request.snapshot.document.pages.first { $0.id == request.snapshot.pageID } ?? request.snapshot.document.pages[0], bounds: bounds, scale: scale)
        case .pdf: data = try Exporter.pdf(page: request.snapshot.document.pages.first { $0.id == request.snapshot.pageID } ?? request.snapshot.document.pages[0], bounds: bounds)
        case .svg: data = try SVGExporter.data(page: request.snapshot.document.pages.first { $0.id == request.snapshot.pageID } ?? request.snapshot.document.pages[0], bounds: bounds)
        }
        return PluginExportResult(data: data)
    }
}

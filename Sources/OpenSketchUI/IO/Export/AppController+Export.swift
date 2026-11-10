import AppKit
import UniformTypeIdentifiers

extension AppController {
    @objc func exportPNG(_ sender: Any?) { export(pdf: false) }
    @objc func exportPDF(_ sender: Any?) { export(pdf: true) }

    /// Retains the file-menu entry point while sharing all panel export semantics.
    func export(pdf: Bool, chooseDestination: (() -> URL?)? = nil) {
        export(documentID: workspace.currentID, format: pdf ? .pdf : .png,
               chooseDestination: chooseDestination.map { choose in { _ in choose() } })
    }

    func export(documentID: UUID, format: ExportFormat? = nil,
                chooseDestination: ((PreparedExport) -> URL?)? = nil) {
        guard let document = workspace.documents.first(where: { $0.id == documentID }) else { return }
        let session = document.session
        let pluginID = "org.opensketch.export.\((format ?? session.exportOptions.format).rawValue)"
        // Finish the initiating document, including native field editors, before capture.
        if document.id == workspace.currentID { finishDocumentInput() }
        else { session.finishInput?() }
        do {
            try pluginManagerModel.requireEnabled(pluginID)
            let prepared = try session.prepareExport(format: format)
            let destination = chooseDestination ?? { prepared in
                let panel = NSSavePanel()
                let contentType: UTType
                switch prepared.options.format {
                case .pdf: contentType = .pdf
                case .svg: contentType = .svg
                case .html: contentType = .html
                case .assets: contentType = .json
        case .png: contentType = .png
        case .jpg: contentType = .jpeg
                }
                panel.allowedContentTypes = [contentType]
                panel.nameFieldStringValue = prepared.filename
                return panel.runModal() == .OK ? panel.url : nil
            }
            guard let url = destination(prepared) else { return }
            try pluginManagerModel.requireEnabled(pluginID)
            try prepared.data().write(to: url, options: .atomic)
            pluginManagerModel.recordExport(pluginID: pluginID)
            session.setMessage(.format("已导出 %@", [.value(url.lastPathComponent)]))
        } catch {
            pluginManagerModel.recordExport(pluginID: pluginID, error: L10n.errorDescription(error))
            self.error(error)
        }
    }
}

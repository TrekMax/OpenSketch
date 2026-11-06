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
        // Finish the initiating document, including native field editors, before capture.
        if document.id == workspace.currentID { finishDocumentInput() }
        else { session.finishInput?() }
        do {
            let prepared = try session.prepareExport(format: format)
            let destination = chooseDestination ?? { prepared in
                let panel = NSSavePanel()
                panel.allowedContentTypes = [prepared.options.format == .pdf ? .pdf : .png]
                panel.nameFieldStringValue = prepared.filename
                return panel.runModal() == .OK ? panel.url : nil
            }
            guard let url = destination(prepared) else { return }
            try prepared.data().write(to: url, options: .atomic)
            session.message = "已导出 \(url.lastPathComponent)"
        } catch { self.error(error) }
    }
}

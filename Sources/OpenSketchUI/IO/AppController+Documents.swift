import AppKit
import UniformTypeIdentifiers
import OpenSketchCore

extension AppController {
    /// Finish both canvas input and native inspector field editing before changing identity.
    func finishDocumentInput() {
        session.finishInput?()
        window?.makeFirstResponder(nil)
    }

    @discardableResult func selectDocument(_ id: UUID) -> Bool {
        guard workspace.documents.contains(where: { $0.id == id }) else { return false }
        if workspace.currentID != id { finishDocumentInput() }
        return workspace.select(id)
    }

    @objc func newDocument(_ sender: Any?) {
        finishDocumentInput()
        workspace.newDocument()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func openExample(_ sender: Any?) {
        finishDocumentInput()
        let document = workspace.newDocument()
        document.session.needsInitialFit = true
        document.session.change { $0 = EditorSession.exampleDocument() }
        document.session.reconcilePage()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func openDocument(_ sender: Any?) {
        finishDocumentInput()
        let panel = NSOpenPanel()
        panel.prompt = L10n.text("打开")
        panel.allowedContentTypes = [Self.documentType]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        openURLs(panel.urls)
    }

    @discardableResult func openURL(_ url: URL) -> Bool {
        do {
            finishDocumentInput()
            try workspace.open(url)
            window?.makeKeyAndOrderFront(nil)
            return true
        } catch { self.error(error); return false }
    }

    @discardableResult func openURLs(_ urls: [URL]) -> Bool {
        var succeeded = true
        for url in urls {
            if !openURL(url) { succeeded = false }
        }
        return succeeded
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let succeeded = openURLs(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: succeeded ? .success : .failure)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        workspace.activatePlaceholder()
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func decisionForClosing(_ document: EditorDocument) -> DocumentCloseDecision {
        if let closeDecision { return closeDecision(document) }
        let alert = NSAlert()
        alert.messageText = L10n.format("保存对“%@”的更改？", document.title)
        alert.informativeText = L10n.text("未保存的更改将丢失。")
        alert.addButton(withTitle: L10n.text("保存"))
        alert.addButton(withTitle: L10n.text("取消"))
        alert.addButton(withTitle: L10n.text("不保存"))
        return switch alert.runModal() {
        case .alertFirstButtonReturn: .save
        case .alertThirdButtonReturn: .discard
        default: .cancel
        }
    }

    @discardableResult func closeDocuments(_ ids: Set<UUID>) -> Bool {
        finishDocumentInput()
        let closed = workspace.close(ids, decide: decisionForClosing, save: { saveDocument($0, forcePanel: false) })
        if closed && workspace.isPlaceholder { window?.orderOut(nil) }
        return closed
    }

    @objc func closeCurrentDocument(_ sender: Any?) { closeFocusedWindow(NSApp.keyWindow) }

    func closeFocusedWindow(_ focusedWindow: NSWindow?) {
        if let settingsController, focusedWindow === settingsController.window {
            settingsController.close()
            return
        }
        closeDocuments([workspace.currentID])
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeDocuments(Set(workspace.documents.map(\.id)))
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        closeDocuments(Set(workspace.documents.map(\.id))) ? .terminateNow : .terminateCancel
    }

    @objc func save(_ sender: Any?) { _ = saveDocument(forcePanel: false) }
    @objc func saveAs(_ sender: Any?) { _ = saveDocument(forcePanel: true) }

    @discardableResult func saveDocument(forcePanel: Bool, chooseDestination: ((EditorDocument) -> URL?)? = nil) -> Bool {
        saveDocument(workspace.current, forcePanel: forcePanel, chooseDestination: chooseDestination)
    }

    @discardableResult func saveDocument(_ document: EditorDocument, forcePanel: Bool, chooseDestination: ((EditorDocument) -> URL?)? = nil) -> Bool {
        if document.id == workspace.currentID { finishDocumentInput() }
        else { document.session.finishInput?() }
        var url = document.session.url
        if forcePanel || url == nil {
            let destination = chooseDestination ?? { target in
                let panel = NSSavePanel()
                panel.prompt = L10n.text("保存")
                panel.nameFieldStringValue = target.session.url?.lastPathComponent ?? "\(target.title).opensketch"
                panel.allowedContentTypes = [Self.documentType]
                return panel.runModal() == .OK ? panel.url : nil
            }
            url = destination(document)
        }
        guard let url else { return false }
        do {
            try writeDocument(document, to: url)
            return true
        } catch { self.error(error); return false }
    }

    func writeDocument(_ document: EditorDocument, to url: URL) throws {
        if let other = workspace.document(matching: url, excluding: document.id) {
            throw EditorError.documentAlreadyOpen(other.title)
        }
        try DocumentCodec.save(document.session.document, to: url)
        document.session.url = url
        document.session.history.markSaved(document: document.session.document)
    }
}

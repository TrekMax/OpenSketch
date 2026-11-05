import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenSketchCore

@MainActor public final class AppController: NSResponder, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let session = EditorSession()
    var window: NSWindow!
    public override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); makeMenus()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "未命名 — openSketch"; window.delegate = self; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorRootView(session: session)); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        observeDocument()
    }
    func observeDocument() {
        withObservationTracking { window?.isDocumentEdited = session.isDirty; window?.title = "\(session.url?.deletingPathExtension().lastPathComponent ?? "未命名") — openSketch" } onChange: { [weak self] in Task { @MainActor in self?.observeDocument() } }
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    public func windowShouldClose(_ sender: NSWindow) -> Bool { mayDiscard() }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { mayDiscard() ? .terminateNow : .terminateCancel }
    public func application(_ sender: NSApplication, openFiles filenames: [String]) { if let path = filenames.first { openURL(URL(fileURLWithPath: path)) }; sender.reply(toOpenOrPrint: .success) }
    func error(_ error: Error) { let alert = NSAlert(error: error); alert.runModal() }
    func mayDiscard() -> Bool {
        session.finishInput?(); guard session.isDirty else { return true }
        let alert = NSAlert(); alert.messageText = "保存对文档的更改？"; alert.informativeText = "未保存的更改将丢失。"; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "不保存")
        switch alert.runModal() { case .alertFirstButtonReturn: return saveDocument(forcePanel: false); case .alertThirdButtonReturn: return true; default: return false }
    }
    @objc func newDocument(_ sender: Any?) { if mayDiscard() { session.replace(.blank()); window.makeKeyAndOrderFront(nil) } }
    @objc func openDocument(_ sender: Any?) { session.finishInput?(); let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "opensketch") ?? .package]; panel.canChooseDirectories = true; if panel.runModal() == .OK, let url = panel.url { openURL(url) } }
    func openURL(_ url: URL) { do { let doc = try DocumentCodec.load(from: url); if mayDiscard() { session.replace(doc, url: url); window?.makeKeyAndOrderFront(nil) } } catch { self.error(error) } }
    @objc func save(_ sender: Any?) { _ = saveDocument(forcePanel: false) }
    @objc func saveAs(_ sender: Any?) { _ = saveDocument(forcePanel: true) }
    func saveDocument(forcePanel: Bool) -> Bool {
        session.finishInput?(); var url = session.url
        if forcePanel || url == nil { let panel = NSSavePanel(); panel.nameFieldStringValue = "未命名.opensketch"; panel.allowedContentTypes = [UTType(filenameExtension: "opensketch") ?? .package]; guard panel.runModal() == .OK else { return false }; url = panel.url }
        guard let url else { return false }; do { try DocumentCodec.save(session.document, to: url); session.url = url; session.history.markSaved(document: session.document); return true } catch { self.error(error); return false }
    }
    @objc func undo(_ sender: Any?) { session.undo() }
    @objc func redo(_ sender: Any?) { session.redo() }
    @objc func cut(_ sender: Any?) { session.finishInput?(); session.copy(); session.deleteSelection() }
    public override func selectAll(_ sender: Any?) { session.selection = Set(SceneGeometry.traversal(in: session.page).filter { session.editable($0.id) }.map(\.id)) }
    @objc func copy(_ sender: Any?) { session.finishInput?(); session.copy() }
    @objc func paste(_ sender: Any?) { session.finishInput?(); session.paste() }
    @objc func duplicate(_ sender: Any?) { session.finishInput?(); session.duplicate() }
    @objc func delete(_ sender: Any?) { session.deleteSelection() }
    @objc func fit(_ sender: Any?) { session.fitCanvas?() }
    @objc func actualSize(_ sender: Any?) { session.finishInput?(); session.zoom = 1 }
    @objc func exportPNG(_ sender: Any?) { export(pdf: false) }
    @objc func exportPDF(_ sender: Any?) { export(pdf: true) }
    func export(pdf: Bool) {
        session.finishInput?(); let panel = NSSavePanel(); panel.allowedContentTypes = [pdf ? .pdf : .png]; panel.nameFieldStringValue = pdf ? "设计.pdf" : "设计.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var page = session.page; var bounds = CanvasRenderer.bounds(page: page)
        if let frame = session.selected, frame.kind == .frame {
            var isolated = frame; isolated.frame.origin = .zero; isolated.rotation = 0; isolated.clipsContent = true
            page.nodes = [isolated]; bounds = CGRect(origin: .zero, size: frame.frame.size)
        }
        do { let data = try pdf ? Exporter.pdf(page: page, bounds: bounds) : Exporter.png(page: page, bounds: bounds); try data.write(to: url, options: .atomic); session.message = "已导出 \(url.lastPathComponent)" } catch { self.error(error) }
    }
    @objc func inspectSketch(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "sketch") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let meta = try SketchFileInspector.inspect(url); let alert = NSAlert(); alert.messageText = "Sketch 仅元数据检查"; alert.informativeText = "文件版本：\(meta.version)\n应用版本：\(meta.appVersion)\n构建：\(meta.build)\n兼容版本：\(meta.compatibilityVersion)\n\n仅查看 meta.json；不支持可编辑导入或无损往返。当前文档未改变。"; alert.runModal() } catch { self.error(error) }
    }
    func makeMenus() {
        let bar = NSMenu(); NSApp.mainMenu = bar
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let m = NSMenu(title: title); item.submenu = m; bar.addItem(item); return m }
        func add(_ m: NSMenu, _ title: String, _ action: Selector, _ key: String = "", shift: Bool = false, responder: Bool = false) { let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = responder ? nil : self; item.keyEquivalentModifierMask = shift ? [.command,.shift] : [.command]; m.addItem(item) }
        let app = menu("openSketch"); add(app,"退出 openSketch",#selector(NSApplication.terminate(_:)),"q",responder:true)
        let file = menu("文件"); add(file,"新建",#selector(newDocument(_:)),"n"); add(file,"打开…",#selector(openDocument(_:)),"o"); add(file,"保存",#selector(save(_:)),"s"); add(file,"另存为…",#selector(saveAs(_:)),"s",shift:true); file.addItem(.separator()); add(file,"导出 PNG…",#selector(exportPNG(_:))); add(file,"导出 PDF…",#selector(exportPDF(_:))); add(file,"检查 Sketch 元数据…",#selector(inspectSketch(_:))); add(file,"关闭窗口",#selector(NSWindow.performClose(_:)),"w",responder:true)
        let edit = menu("编辑"); add(edit,"撤销",#selector(undo(_:)),"z",responder:true); add(edit,"重做",#selector(redo(_:)),"z",shift:true,responder:true); add(edit,"剪切",#selector(NSText.cut(_:)),"x",responder:true); add(edit,"拷贝",#selector(copy(_:)),"c",responder:true); add(edit,"粘贴",#selector(paste(_:)),"v",responder:true); add(edit,"全选",#selector(NSText.selectAll(_:)),"a",responder:true); add(edit,"复制图层",#selector(duplicate(_:)),"d"); add(edit,"删除图层",#selector(delete(_:)))
        let view = menu("视图"); add(view,"适合窗口",#selector(fit(_:)),"1"); add(view,"实际大小 100%",#selector(actualSize(_:)),"0")
        NSApp.nextResponder = self
    }
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action { case #selector(undo(_:)): session.history.canUndo; case #selector(redo(_:)): session.history.canRedo; case #selector(copy(_:)), #selector(duplicate(_:)), #selector(delete(_:)): !session.roots.isEmpty; default: true }
    }
}

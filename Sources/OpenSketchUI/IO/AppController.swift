import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenSketchCore

@MainActor public final class AppController: NSResponder, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate {
    let workspace = DocumentWorkspace()
    var session: EditorSession { workspace.current.session }
    let appearance = AppAppearance()
    var settingsController: SettingsWindowController?
    var applicationMenu: NSMenu?
    static let documentType = UTType(filenameExtension: "opensketch", conformingTo: .package) ?? .package
    var window: NSWindow!
    var documentTabsHost: NSHostingView<DocumentTabsView>?
    var closeDecision: ((EditorDocument) -> DocumentCloseDecision)?
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage), name: .applicationLanguageDidChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); appearance.apply(); makeMenus()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = L10n.text("未命名 — OpenSketch"); window.delegate = self; window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = EditorPalette.panel
        window.toolbarStyle = .unifiedCompact
        let toolbar = NSToolbar(identifier: "editor.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.contentView = NSHostingView(rootView: EditorRootView(workspace: workspace, appearance: appearance, exportDocument: { [weak self] id in self?.export(documentID: id) })); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        observeDocument()
    }
    func observeDocument() {
        withObservationTracking { window?.isDocumentEdited = session.isDirty; window?.title = "\(workspace.current.title) — OpenSketch" } onChange: { [weak self] in Task { @MainActor in self?.observeDocument() } }
    }
    func error(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.text("操作失败")
        alert.informativeText = L10n.errorDescription(error)
        alert.addButton(withTitle: L10n.text("好"))
        alert.runModal()
    }
    var activeTextEditor: NSTextView? { (NSApp.keyWindow ?? window)?.firstResponder as? NSTextView }
    @objc func undo(_ sender: Any?) { if let editor = activeTextEditor { editor.undoManager?.undo() } else { session.undo() } }
    @objc func redo(_ sender: Any?) { if let editor = activeTextEditor { editor.undoManager?.redo() } else { session.redo() } }
    @objc func cut(_ sender: Any?) { session.finishInput?(); session.copy(); session.deleteSelection() }
    public override func selectAll(_ sender: Any?) { session.finishInput?(); session.selection = Set(SceneGeometry.traversal(in: session.page).filter { session.editable($0.id) }.map(\.id)) }
    @objc func copy(_ sender: Any?) { session.finishInput?(); session.copy() }
    @objc func paste(_ sender: Any?) { session.finishInput?(); session.paste() }
    @objc func duplicate(_ sender: Any?) { session.finishInput?(); session.duplicate() }
    @objc func delete(_ sender: Any?) { session.deleteSelection() }
    @objc func fit(_ sender: Any?) { session.fitCanvas?() }
    @objc func actualSize(_ sender: Any?) { session.setZoom(1) }
    @objc func zoomIn(_ sender: Any?) { session.zoomCanvas?(1.25) }
    @objc func zoomOut(_ sender: Any?) { session.zoomCanvas?(0.8) }
    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = AppearanceMode(rawValue: rawValue) else { return }
        appearance.mode = mode
    }
    @objc func inspectSketch(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "sketch") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let meta = try SketchFileInspector.inspect(url); let alert = NSAlert(); alert.messageText = L10n.text("Sketch 仅元数据检查"); alert.informativeText = L10n.format("文件版本：%d\n应用版本：%@\n构建：%d\n兼容版本：%d\n\n仅查看 meta.json；不支持可编辑导入或无损往返。当前文档未改变。", meta.version, meta.appVersion, meta.build, meta.compatibilityVersion); alert.runModal() } catch { self.error(error) }
    }
    func makeMenus() {
        let bar = NSMenu(); NSApp.mainMenu = bar; applicationMenu = bar
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let m = NSMenu(title: title); item.submenu = m; bar.addItem(item); return m }
        func add(_ m: NSMenu, _ title: String, _ action: Selector, _ key: String = "", shift: Bool = false, responder: Bool = false) { let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = responder ? nil : self; item.keyEquivalentModifierMask = shift ? [.command,.shift] : [.command]; m.addItem(item) }
        let app = menu("OpenSketch"); add(app,L10n.text("设置…"),#selector(showSettings(_:)),","); app.addItem(.separator()); add(app,L10n.text("退出 OpenSketch"),#selector(NSApplication.terminate(_:)),"q",responder:true)
        let file = menu(L10n.text("文件")); add(file,L10n.text("打开示例设计"),#selector(openExample(_:))); add(file,L10n.text("新建"),#selector(newDocument(_:)),"n"); add(file,L10n.text("打开…"),#selector(openDocument(_:)),"o"); add(file,L10n.text("保存"),#selector(save(_:)),"s"); add(file,L10n.text("另存为…"),#selector(saveAs(_:)),"s",shift:true); file.addItem(.separator()); add(file,L10n.text("导出 PNG…"),#selector(exportPNG(_:))); add(file,L10n.text("导出 PDF…"),#selector(exportPDF(_:))); add(file,L10n.text("检查 Sketch 元数据…"),#selector(inspectSketch(_:))); add(file,L10n.text("关闭标签页"),#selector(closeCurrentDocument(_:)),"w")
        let edit = menu(L10n.text("编辑")); add(edit,L10n.text("撤销"),#selector(undo(_:)),"z"); add(edit,L10n.text("重做"),#selector(redo(_:)),"z",shift:true); add(edit,L10n.text("剪切"),#selector(NSText.cut(_:)),"x",responder:true); add(edit,L10n.text("拷贝"),#selector(copy(_:)),"c",responder:true); add(edit,L10n.text("粘贴"),#selector(paste(_:)),"v",responder:true); add(edit,L10n.text("全选"),#selector(NSText.selectAll(_:)),"a",responder:true); add(edit,L10n.text("复制图层"),#selector(duplicate(_:)),"d"); add(edit,L10n.text("删除图层"),#selector(delete(_:)))
        let layers = NSMenuItem(title: L10n.text("图层"), action: nil, keyEquivalent: "")
        layers.submenu = makeLayerMenu()
        bar.addItem(layers)
        let view = menu(L10n.text("视图")); add(view,L10n.text("适合窗口"),#selector(fit(_:)),"1"); add(view,L10n.text("实际大小 100%"),#selector(actualSize(_:)),"0")
        view.addItem(.separator())
        let appearanceItem = NSMenuItem(title: L10n.text("外观"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: L10n.text("外观"))
        for mode in AppearanceMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(changeAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        view.addItem(appearanceItem)
        NSApp.nextResponder = self
    }
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        validateMenuItem(menuItem, focusedWindow: NSApp.keyWindow)
    }

    func validateMenuItem(_ menuItem: NSMenuItem, focusedWindow: NSWindow?) -> Bool {
        if isSettingsWindow(focusedWindow), let action = menuItem.action,
           [#selector(undo(_:)), #selector(redo(_:)), #selector(cut(_:)),
            #selector(copy(_:)), #selector(paste(_:)), #selector(duplicate(_:)),
            #selector(delete(_:)), #selector(selectAll(_:)), #selector(performLayerCommand(_:))].contains(action) {
            return false
        }
        if menuItem.action == #selector(performLayerCommand(_:)) {
            guard activeTextEditor == nil, let command = menuItem.representedObject as? LayerCommand else { return false }
            return session.canPerform(command)
        }
        if menuItem.action == #selector(changeAppearance(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == appearance.mode.rawValue ? .on : .off
            return true
        }
        return switch menuItem.action { case #selector(undo(_:)): activeTextEditor.map { $0.undoManager?.canUndo ?? false } ?? session.canUndo; case #selector(redo(_:)): activeTextEditor.map { $0.undoManager?.canRedo ?? false } ?? session.history.canRedo; case #selector(copy(_:)), #selector(duplicate(_:)), #selector(delete(_:)): !session.roots.isEmpty; default: true }
    }

    var documentTabsWidth: CGFloat { min(620, max(160, (window?.frame.width ?? 1280) - 630)) }

    func makeDocumentTabs() -> DocumentTabsView {
        DocumentTabsView(workspace: workspace, width: documentTabsWidth, select: { [weak self] id in
            self?.selectDocument(id)
        }, close: { [weak self] id in
            self?.closeDocuments([id])
        })
    }

    public func windowDidResize(_ notification: Notification) {
        documentTabsHost?.rootView = makeDocumentTabs()
        documentTabsHost?.setFrameSize(CGSize(width: documentTabsWidth, height: 32))
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("document.new"), .init("document.tabs"), .flexibleSpace, .init("view.zoomSlider"), .init("view.zoomIn"), .init("view.zoomOut")]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        switch identifier.rawValue {
        case "document.new":
            item.label = L10n.text("新建文档"); item.toolTip = L10n.text("新建文档（⌘N）")
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.text("新建文档"))
            item.action = #selector(newDocument(_:))
        case "document.tabs":
            item.label = L10n.text("文档标签页")
            let host = NSHostingView(rootView: makeDocumentTabs())
            host.frame = CGRect(x: 0, y: 0, width: documentTabsWidth, height: 32)
            documentTabsHost = host
            item.view = host
        case "view.zoomSlider":
            item.label = L10n.text("缩放"); item.toolTip = L10n.text("画布缩放")
            let host = NSHostingView(rootView: ZoomControlView(workspace: workspace))
            host.frame = CGRect(x: 0, y: 0, width: 176, height: 32)
            item.view = host
        case "view.zoomIn":
            item.label = L10n.text("放大"); item.toolTip = L10n.text("放大画布")
            item.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: L10n.text("放大"))
            item.action = #selector(zoomIn(_:))
        case "view.zoomOut":
            item.label = L10n.text("缩小"); item.toolTip = L10n.text("缩小画布")
            item.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: L10n.text("缩小"))
            item.action = #selector(zoomOut(_:))
        default: return nil
        }
        if item.view == nil {
            let button: NSButton
            if let image = item.image {
                button = NSButton(image: image, target: self, action: item.action)
            } else {
                button = NSButton(title: item.label, target: self, action: item.action)
            }
            button.bezelStyle = .texturedRounded
            button.toolTip = item.toolTip
            button.setAccessibilityLabel(item.label)
            button.setAccessibilityIdentifier(identifier.rawValue)
            item.view = button
        }
        return item
    }
}

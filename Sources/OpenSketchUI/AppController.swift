import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OpenSketchCore

@MainActor public final class AppController: NSResponder, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate {
    let workspace = DocumentWorkspace()
    var session: EditorSession { workspace.current.session }
    let appearance = AppAppearance()
    static let documentType = UTType(filenameExtension: "opensketch", conformingTo: .package) ?? .package
    var window: NSWindow!
    var documentTabsHost: NSHostingView<DocumentTabsView>?
    var closeDecision: ((EditorDocument) -> DocumentCloseDecision)?
    public override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); appearance.apply(); makeMenus()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = "未命名 — openSketch"; window.delegate = self; window.isReleasedWhenClosed = false
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
        window.contentView = NSHostingView(rootView: EditorRootView(workspace: workspace, appearance: appearance)); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        observeDocument()
    }
    func observeDocument() {
        withObservationTracking { window?.isDocumentEdited = session.isDirty; window?.title = "\(workspace.current.title) — openSketch" } onChange: { [weak self] in Task { @MainActor in self?.observeDocument() } }
    }
    func error(_ error: Error) { let alert = NSAlert(error: error); alert.runModal() }
    var activeTextEditor: NSTextView? { (NSApp.keyWindow ?? window)?.firstResponder as? NSTextView }
    @objc func undo(_ sender: Any?) { if let editor = activeTextEditor { editor.undoManager?.undo() } else { session.undo() } }
    @objc func redo(_ sender: Any?) { if let editor = activeTextEditor { editor.undoManager?.redo() } else { session.redo() } }
    @objc func cut(_ sender: Any?) { session.finishInput?(); session.copy(); session.deleteSelection() }
    public override func selectAll(_ sender: Any?) { session.selection = Set(SceneGeometry.traversal(in: session.page).filter { session.editable($0.id) }.map(\.id)) }
    @objc func copy(_ sender: Any?) { session.finishInput?(); session.copy() }
    @objc func paste(_ sender: Any?) { session.finishInput?(); session.paste() }
    @objc func duplicate(_ sender: Any?) { session.finishInput?(); session.duplicate() }
    @objc func delete(_ sender: Any?) { session.deleteSelection() }
    @objc func fit(_ sender: Any?) { session.fitCanvas?() }
    @objc func actualSize(_ sender: Any?) { session.finishInput?(); session.zoom = 1 }
    @objc func zoomIn(_ sender: Any?) { session.zoomCanvas?(1.25) }
    @objc func zoomOut(_ sender: Any?) { session.zoomCanvas?(0.8) }
    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = AppearanceMode(rawValue: rawValue) else { return }
        appearance.mode = mode
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
        let file = menu("文件"); add(file,"打开示例设计",#selector(openExample(_:))); add(file,"新建",#selector(newDocument(_:)),"n"); add(file,"打开…",#selector(openDocument(_:)),"o"); add(file,"保存",#selector(save(_:)),"s"); add(file,"另存为…",#selector(saveAs(_:)),"s",shift:true); file.addItem(.separator()); add(file,"导出 PNG…",#selector(exportPNG(_:))); add(file,"导出 PDF…",#selector(exportPDF(_:))); add(file,"检查 Sketch 元数据…",#selector(inspectSketch(_:))); add(file,"关闭标签页",#selector(closeCurrentDocument(_:)),"w")
        let edit = menu("编辑"); add(edit,"撤销",#selector(undo(_:)),"z"); add(edit,"重做",#selector(redo(_:)),"z",shift:true); add(edit,"剪切",#selector(NSText.cut(_:)),"x",responder:true); add(edit,"拷贝",#selector(copy(_:)),"c",responder:true); add(edit,"粘贴",#selector(paste(_:)),"v",responder:true); add(edit,"全选",#selector(NSText.selectAll(_:)),"a",responder:true); add(edit,"复制图层",#selector(duplicate(_:)),"d"); add(edit,"删除图层",#selector(delete(_:)))
        let view = menu("视图"); add(view,"适合窗口",#selector(fit(_:)),"1"); add(view,"实际大小 100%",#selector(actualSize(_:)),"0")
        view.addItem(.separator())
        let appearanceItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "外观")
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
        if menuItem.action == #selector(changeAppearance(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == appearance.mode.rawValue ? .on : .off
            return true
        }
        return switch menuItem.action { case #selector(undo(_:)): activeTextEditor.map { $0.undoManager?.canUndo ?? false } ?? session.history.canUndo; case #selector(redo(_:)): activeTextEditor.map { $0.undoManager?.canRedo ?? false } ?? session.history.canRedo; case #selector(copy(_:)), #selector(duplicate(_:)), #selector(delete(_:)): !session.roots.isEmpty; default: true }
    }

    var documentTabsWidth: CGFloat { min(620, max(160, (window?.frame.width ?? 1280) - 520)) }

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
        [.init("document.new"), .init("document.tabs"), .flexibleSpace, .init("view.fit"), .init("view.actualSize"), .init("view.zoomIn"), .init("view.zoomOut")]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        switch identifier.rawValue {
        case "document.new":
            item.label = "新建文档"; item.toolTip = "新建文档（⌘N）"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建文档")
            item.action = #selector(newDocument(_:))
        case "document.tabs":
            item.label = "文档标签页"
            let host = NSHostingView(rootView: makeDocumentTabs())
            host.frame = CGRect(x: 0, y: 0, width: documentTabsWidth, height: 32)
            documentTabsHost = host
            item.view = host
        case "view.fit":
            item.label = "适合"; item.toolTip = "画布适合窗口（⌘1）"
            item.action = #selector(fit(_:))
        case "view.actualSize":
            item.label = "100%"; item.toolTip = "实际大小（⌘0）"
            item.action = #selector(actualSize(_:))
        case "view.zoomIn":
            item.label = "放大"; item.toolTip = "放大画布"
            item.image = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大")
            item.action = #selector(zoomIn(_:))
        case "view.zoomOut":
            item.label = "缩小"; item.toolTip = "缩小画布"
            item.image = NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小")
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

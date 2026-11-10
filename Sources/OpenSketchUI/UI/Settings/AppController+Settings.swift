import AppKit

extension AppController {
    func isSettingsWindow(_ window: NSWindow?) -> Bool {
        guard let settingsController else { return false }
        return window === settingsController.window
    }

    @objc func showSettings(_ sender: Any?) {
        if window != nil { finishDocumentInput() }
        if settingsController == nil { settingsController = SettingsWindowController(appearance: appearance) }
        settingsController?.showWindow(sender)
    }

    @objc func refreshLanguage() {
        if NSApp.mainMenu === applicationMenu { makeMenus() }
        window?.title = "\(workspace.current.title) — OpenSketch"
        for item in window?.toolbar?.items ?? [] {
            let keys: (String, String)? = switch item.itemIdentifier.rawValue {
            case "document.new": ("新建文档", "新建文档（⌘N）")
            case "document.tabs": ("文档标签页", "文档标签页")
            case "view.zoomSlider": ("缩放", "画布缩放")
            case "view.zoomIn": ("放大", "放大画布")
            case "view.zoomOut": ("缩小", "缩小画布")
            case "plugin.manager": ("插件管理器", "打开插件管理器")
            default: nil
            }
            guard let keys else { continue }
            item.label = L10n.text(keys.0)
            item.toolTip = L10n.text(keys.1)
            item.view?.setAccessibilityLabel(item.label)
            if let button = item.view as? NSButton {
                button.setAccessibilityLabel(item.label)
                button.toolTip = item.toolTip
            }
        }
    }
}

import AppKit

extension AppController {
    func refreshPluginManagerLanguage() {
        pluginManagerController?.window?.title = L10n.text("插件管理器")
    }
}

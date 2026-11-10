import AppKit
import Testing
@testable import OpenSketchUI

@MainActor struct PluginManagerTests {
    @Test func toolbarIncludesPluginManagerAndWindowIsReusable() throws {
        _ = NSApplication.shared
        let controller = AppController()
        let identifiers = controller.toolbarDefaultItemIdentifiers(NSToolbar(identifier: "test"))
        #expect(identifiers.contains(NSToolbarItem.Identifier("plugin.manager")))
        controller.showPluginManager(nil)
        let first = try #require(controller.pluginManagerController?.window)
        defer { first.close() }
        controller.showPluginManager(nil)
        #expect(controller.pluginManagerController?.window === first)
        #expect(first.identifier?.rawValue == "plugins.window")
    }

    @Test func applicationMenuIncludesPluginManager() throws {
        _ = NSApplication.shared
        let controller = AppController()
        controller.makeMenus()
        let appMenu = try #require(controller.applicationMenu?.items.first?.submenu)
        let item = try #require(appMenu.items.first(where: { $0.action == #selector(AppController.showPluginManager(_:)) }))
        #expect(item.title == L10n.text("插件管理器"))
    }
}

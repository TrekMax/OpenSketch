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
}

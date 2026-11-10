import AppKit
import SwiftUI
import OpenSketchCore

@MainActor final class PluginManagerWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 500),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("plugins.window")
        window.contentView = NSHostingView(rootView: PluginManagerView(model: PluginManagerModel()))
        super.init(window: window)
        window.title = L10n.text("插件管理器")
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

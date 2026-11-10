import AppKit
import SwiftUI
import OpenSketchCore

@MainActor final class PluginManagerWindowController: NSWindowController {
    init(model: PluginManagerModel) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 620),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("plugins.window")
        window.contentView = NSHostingView(rootView: PluginManagerView(model: model))
        super.init(window: window)
        window.title = L10n.text("插件管理器")
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

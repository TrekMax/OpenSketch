import AppKit
import SwiftUI

@MainActor final class SettingsWindowController: NSWindowController {
    let appearance: AppAppearance

    init(appearance: AppAppearance) {
        self.appearance = appearance
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 680, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("settings.window")
        window.contentMinSize = CGSize(width: 640, height: 360)
        window.contentView = NSHostingView(rootView: ApplicationSettingsView(appearance: appearance, language: .shared))
        super.init(window: window)
        refreshTitle()
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshTitle), name: .applicationLanguageDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    @objc private func refreshTitle() { window?.title = L10n.text("设置") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

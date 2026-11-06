import AppKit
import OpenSketchCore

extension AppController {
    func makeLayerMenu() -> NSMenu {
        let menu = LayerMenu(title: "图层", allowsShortcut: { [weak self] in
            self?.activeTextEditor == nil
        })
        func add(_ command: LayerCommand, to menu: NSMenu, key: String = "", shift: Bool = false) {
            let item = NSMenuItem(title: command.title, action: #selector(performLayerCommand(_:)), keyEquivalent: key)
            item.target = self
            item.representedObject = command
            item.identifier = NSUserInterfaceItemIdentifier(command.identifier)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            menu.addItem(item)
        }
        add(.group, to: menu, key: "g")
        add(.ungroup, to: menu, key: "g", shift: true)
        menu.addItem(.separator())
        add(.order(.forward), to: menu, key: "]")
        add(.order(.backward), to: menu, key: "[")
        add(.order(.front), to: menu, key: "]", shift: true)
        add(.order(.back), to: menu, key: "[", shift: true)
        menu.addItem(.separator())
        for (title, commands) in [("对齐", LayerCommand.alignment), ("等距分布", LayerCommand.distribution)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            for command in commands { add(command, to: submenu) }
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    @objc func performLayerCommand(_ sender: NSMenuItem) {
        guard activeTextEditor == nil, let command = sender.representedObject as? LayerCommand,
              session.canPerform(command) else { return }
        session.perform(command)
    }
}

/// AppKit can consume a disabled item's key equivalent. Yield before matching
/// whenever a native text editor owns focus, so text shortcuts keep their meaning.
@MainActor private final class LayerMenu: NSMenu {
    nonisolated let allowsShortcut: @MainActor @Sendable () -> Bool

    init(title: String, allowsShortcut: @escaping @MainActor @Sendable () -> Bool) {
        self.allowsShortcut = allowsShortcut
        super.init(title: title)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    nonisolated override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit routes key events on the main thread, but imports this override
        // as nonisolated. Check only the Sendable UI query at that boundary;
        // neither this menu nor its NSEvent crosses actor isolation.
        let query = allowsShortcut
        guard MainActor.assumeIsolated({ query() }) else { return false }
        return super.performKeyEquivalent(with: event)
    }
}

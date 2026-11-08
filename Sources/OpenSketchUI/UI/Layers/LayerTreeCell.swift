import AppKit
import OpenSketchCore

/// Noneditable names let the outline receive mouse-down/drag; only the active editor owns text events.
@MainActor private final class LayerTreeName: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class LayerTreeCell: NSTableCellView {
    static let iconCenterX: CGFloat = 9 // 2-point leading inset plus half the 14-point icon.
    private weak var session: EditorSession?
    private var nodeID: UUID?
    private let icon = NSImageView()
    private let name = LayerTreeName(labelWithString: "")
    private let nameHost = NSView()
    private let visibility = NSButton()
    private let lock = NSButton()
    private var renameField: NativeSidebarRenameField?
    private var renameID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView = icon
        for view in [icon, nameHost, visibility, lock] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameHost.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            nameHost.trailingAnchor.constraint(equalTo: visibility.leadingAnchor, constant: -8),
            nameHost.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameHost.heightAnchor.constraint(equalToConstant: 22),
            visibility.widthAnchor.constraint(equalToConstant: 18),
            visibility.trailingAnchor.constraint(equalTo: lock.leadingAnchor, constant: -5),
            visibility.centerYAnchor.constraint(equalTo: centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: 18),
            lock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            lock.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.cell)
        name.alignment = .left
        name.usesSingleLineMode = true
        name.font = .systemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for button in [visibility, lock] {
            button.isBordered = false; button.imagePosition = .imageOnly
            button.target = self; button.setButtonType(.momentaryChange)
        }
        visibility.action = #selector(toggleVisibility)
        lock.action = #selector(toggleLock)
        installName(name)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private func installName(_ view: NSView) {
        textField = view as? NSTextField
        nameHost.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        nameHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: nameHost.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: nameHost.trailingAnchor),
            view.centerYAnchor.constraint(equalTo: nameHost.centerYAnchor)
        ])
    }
    func configure(item: LayerTreeItem, session: EditorSession) {
        guard let node = item.node else { return }
        self.session = session; nodeID = node.id
        name.stringValue = node.name.isEmpty ? node.kind.layerTitle : node.name
        name.setAccessibilityIdentifier("layer.\(node.id)")
        icon.image = NSImage(systemSymbolName: node.kind.layerSymbol, accessibilityDescription: nil)
        visibility.image = NSImage(systemSymbolName: node.isVisible ? "eye" : "eye.slash", accessibilityDescription: nil)
        visibility.setAccessibilityLabel(node.isVisible ? L10n.text("隐藏图层") : L10n.text("显示图层"))
        visibility.setAccessibilityIdentifier("layer.visibility.\(node.id)")
        lock.image = NSImage(systemSymbolName: node.isLocked ? "lock.fill" : "lock.open", accessibilityDescription: nil)
        lock.setAccessibilityLabel(node.isLocked ? L10n.text("解锁图层") : L10n.text("锁定图层"))
        lock.setAccessibilityIdentifier("layer.lock.\(node.id)")
        let edit = session.sidebarRename.flatMap { $0.request.target == .layer(pageID: session.pageID, nodeID: node.id) ? $0 : nil }
        if edit?.request.id != renameID {
            renameField?.finish()
            renameID = edit?.request.id
            renameField = edit.map { NativeSidebarRenameField(session: session, request: $0.request) }
            installName(renameField ?? name)
        }
        setAccessibilityChildren([renameField ?? name, visibility, lock])
        renameField?.refreshLanguage()
        updateColors()
    }
    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateColors() } }
    private func updateColors() {
        let color: NSColor = backgroundStyle == .emphasized ? .white : .labelColor
        name.textColor = color; icon.contentTintColor = color
        visibility.contentTintColor = color; lock.contentTintColor = color
    }
    @objc private func toggleVisibility() {
        guard let session, let nodeID else { return }
        session.change { $0.updateNode(id: nodeID) { $0.isVisible.toggle() } }
    }
    @objc private func toggleLock() {
        guard let session, let nodeID else { return }
        session.change { $0.updateNode(id: nodeID) { $0.isLocked.toggle() } }
    }
}

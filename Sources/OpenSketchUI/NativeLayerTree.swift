import AppKit
import SwiftUI
import OpenSketchCore

/// AppKit owns row hit testing, selection, drag tracking and insertion feedback.
struct NativeLayerTree: NSViewRepresentable {
    @Bindable var session: EditorSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) {
        // Read observable values here so native views receive document/selection edits.
        _ = session.page; _ = session.selection; _ = session.sidebarRename?.request.id
        context.coordinator.update()
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.session.finishSidebarRename()
        coordinator.endDrag()
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let pasteboardType = NSPasteboard.PasteboardType("org.opensketch.layer-tree-drag")
        let session: EditorSession
        private(set) var roots: [LayerTreeItem] = []
        private(set) var items: [UUID: LayerTreeItem] = [:]
        private let footer = LayerTreeItem(node: nil)
        private weak var tree: NativeLayerOutline?
        private var page: DesignPage?
        private var collapsed: Set<UUID> = []
        private var synchronizing = false
        private var dragID: UUID?
        private var draggedRows: Set<UUID> = []

        init(session: EditorSession) { self.session = session }

        func makeScrollView() -> NSScrollView {
            let tree = NativeLayerOutline()
            self.tree = tree
            tree.autoresizingMask = [.width]
            tree.headerView = nil
            tree.style = .plain
            tree.backgroundColor = .clear
            tree.rowHeight = 32
            tree.intercellSpacing = NSSize(width: 0, height: 4)
            tree.indentationPerLevel = 14
            // Expanding a deeper level must not push trailing controls outside the sidebar.
            tree.autoresizesOutlineColumn = false
            tree.allowsMultipleSelection = true
            tree.allowsEmptySelection = true
            tree.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer"))
            column.width = 196
            column.resizingMask = .autoresizingMask
            column.minWidth = 60
            tree.addTableColumn(column)
            tree.outlineTableColumn = column
            tree.dataSource = self
            tree.delegate = self
            tree.target = self
            tree.doubleAction = #selector(renameClicked(_:))
            tree.menuForItem = { [weak self] in self?.menu(for: $0) }
            tree.deleteSelection = { [weak session] in session?.deleteSelection() }
            tree.renameSelection = { [weak self] in
                guard let self, self.session.selection.count == 1, let id = self.session.selection.first else { return }
                self.rename(id)
            }
            tree.registerForDraggedTypes([Self.pasteboardType])
            tree.setDraggingSourceOperationMask(.move, forLocal: true)
            tree.setDraggingSourceOperationMask([], forLocal: false)
            tree.setAccessibilityIdentifier("layer.tree")
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.documentView = tree
            update()
            return scroll
        }

        func update() {
            guard let tree else { return }
            synchronizing = true
            defer { synchronizing = false }
            if page != session.page {
                let previous = items
                var next: [UUID: LayerTreeItem] = [:]
                func build(_ nodes: [DesignNode]) -> [LayerTreeItem] {
                    nodes.reversed().map { node in
                        let item = previous[node.id] ?? LayerTreeItem(node: node)
                        item.node = node
                        item.children = build(node.children)
                        next[node.id] = item
                        return item
                    }
                }
                roots = build(session.page.nodes)
                items = next
                collapsed.formIntersection(session.document.pages.flatMap { SceneGeometry.traversal(in: $0).map(\.id) })
                page = session.page
                tree.reloadData()
                func expand(_ nodes: [LayerTreeItem]) {
                    for item in nodes where !collapsed.contains(item.id!) {
                        if item.isContainer { tree.expandItem(item); expand(item.children) }
                    }
                }
                expand(roots)
                tree.needsDisplay = true
            }
            let selected = IndexSet((0..<tree.numberOfRows).filter {
                guard let id = (tree.item(atRow: $0) as? LayerTreeItem)?.id else { return false }
                return session.selection.contains(id)
            })
            if tree.selectedRowIndexes != selected { tree.selectRowIndexes(selected, byExtendingSelection: false) }
            // Do not reload on selection or draft typing: native tracking and the field editor stay alive.
            for row in 0..<tree.numberOfRows {
                guard let item = tree.item(atRow: row) as? LayerTreeItem,
                      let cell = tree.view(atColumn: 0, row: row, makeIfNecessary: false) as? LayerTreeCell else { continue }
                cell.configure(item: item, session: session)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? LayerTreeItem)?.children.count ?? roots.count + 1
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let item = item as? LayerTreeItem { return item.children[index] }
            return index < roots.count ? roots[index] : footer
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? LayerTreeItem)?.isContainer == true
        }
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? LayerTreeItem)?.id != nil
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? LayerTreeItem else { return nil }
            let identifier = NSUserInterfaceItemIdentifier(item.id == nil ? "footer" : "layerCell")
            if item.id == nil {
                let label = NSTextField(labelWithString: "↳  移到页面根层级")
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
                label.setAccessibilityIdentifier("layer.drop.pageEnd")
                return label
            }
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? LayerTreeCell ?? LayerTreeCell()
            cell.identifier = identifier
            cell.configure(item: item, session: session)
            return cell
        }
        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { LayerTreeSelectionRow() }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let tree else { return }
            let selected = Set(tree.selectedRowIndexes.compactMap { (tree.item(atRow: $0) as? LayerTreeItem)?.id })
            session.finishInput?()
            session.selection = selected
        }
        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            if !synchronizing { session.finishSidebarRename() }
            return true
        }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !synchronizing, let id = (notification.userInfo?["NSObject"] as? LayerTreeItem)?.id else { return }
            collapsed.insert(id)
            tree?.needsDisplay = true
        }
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !synchronizing, let id = (notification.userInfo?["NSObject"] as? LayerTreeItem)?.id else { return }
            collapsed.remove(id)
            tree?.needsDisplay = true
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let id = (item as? LayerTreeItem)?.id, session.sidebarRename == nil,
                  LayerTreeEditing.canDrag(session.document, pageID: session.pageID, selection: session.contextMenuSelection(for: id)) else { return nil }
            let writer = NSPasteboardItem()
            writer.setString(id.uuidString, forType: Self.pasteboardType)
            return writer
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                         willBeginAt screenPoint: NSPoint, forItems items: [Any]) { _ = beginDrag(items) }
        /// Called once after AppKit has collected every row's writer; multi-selection is captured once.
        @discardableResult func beginDrag(_ items: [Any]) -> Bool {
            endDrag()
            let ids = items.compactMap { ($0 as? LayerTreeItem)?.id }
            guard ids.count == items.count, let id = ids.first,
                  let request = session.beginSidebarLayerDrag(id) else { return false }
            dragID = request.id
            draggedRows = Set(ids)
            return true
        }
        func dragToken(source: NSOutlineView?, pasteboard: NSPasteboard) -> UUID? {
            guard let tree, source === tree, let dragID,
                  session.sidebarLayerDrag?.id == dragID,
                  let writers = pasteboard.pasteboardItems else { return nil }
            let ids = writers.compactMap { $0.string(forType: Self.pasteboardType).flatMap(UUID.init(uuidString:)) }
            guard ids.count == writers.count, ids.count == draggedRows.count, Set(ids) == draggedRows else { return nil }
            return dragID
        }
        func destination(item: LayerTreeItem?, childIndex: Int) -> LayerDropDestination? {
            if item === footer { return .pageEnd }
            let parentID = item?.id
            if let item, !item.isContainer { return nil }
            if childIndex == NSOutlineViewDropOnItemIndex {
                return parentID.map { .inside($0) } ?? .pageEnd
            }
            let siblings = item?.children ?? roots
            // The root footer is also a native row; dropping after it means page end.
            guard childIndex >= 0, childIndex <= siblings.count + (item == nil ? 1 : 0) else { return nil }
            let index = min(childIndex, siblings.count)
            let moving = session.sidebarLayerDrag?.selection ?? []
            // AppKit's index is before removal. A selected neighbor cannot be an anchor.
            if let next = siblings.dropFirst(index).first(where: { !moving.contains($0.id!) })?.id { return .above(next) }
            if let previous = siblings.prefix(index).last(where: { !moving.contains($0.id!) })?.id { return .below(previous) }
            return parentID.map { .inside($0) } ?? .pageEnd
        }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let token = dragToken(source: info.draggingSource as? NSOutlineView, pasteboard: info.draggingPasteboard),
                  let destination = destination(item: item as? LayerTreeItem, childIndex: index),
                  session.canDropSidebarLayers(token, to: destination) else { return [] }
            return .move
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let destination = destination(item: item as? LayerTreeItem, childIndex: index) else { return false }
            return accept(source: info.draggingSource as? NSOutlineView, pasteboard: info.draggingPasteboard, destination: destination)
        }
        func accept(source: NSOutlineView?, pasteboard: NSPasteboard, destination: LayerDropDestination) -> Bool {
            guard let token = dragToken(source: source, pasteboard: pasteboard),
                  session.canDropSidebarLayers(token, to: destination) else { return false }
            let moved = session.commitSidebarLayerDrop(token, to: destination)
            if moved {
                if case .inside(let id) = destination { collapsed.remove(id) }
                update()
            }
            return moved
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) { endDrag() }
        func endDrag() {
            if session.sidebarLayerDrag?.id == dragID { session.sidebarLayerDrag = nil }
            dragID = nil
            draggedRows = []
        }

        private func rename(_ id: UUID) {
            session.startSidebarRename(.layer(pageID: session.pageID, nodeID: id))
            update()
        }
        @objc private func renameClicked(_ sender: NSOutlineView) {
            guard let id = (sender.item(atRow: sender.clickedRow) as? LayerTreeItem)?.id else { return }
            rename(id)
        }
        private func menu(for item: LayerTreeItem) -> NSMenu? {
            guard let id = item.id else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            func add(_ title: String, identifier: String, enabled: Bool = true, to target: NSMenu = menu, action: @escaping () -> Void) {
                let entry = LayerTreeMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
                entry.target = self; entry.perform = action; entry.isEnabled = enabled
                entry.setAccessibilityIdentifier(identifier)
                target.addItem(entry)
            }
            add("重命名", identifier: "layer.rename") { [weak self] in self?.rename(id) }
            add("复制图层", identifier: "layer.duplicate", enabled: session.canEditContextLayers(for: id)) { [weak session] in session?.duplicateContextLayers(for: id) }
            add("删除", identifier: "layer.delete", enabled: session.canEditContextLayers(for: id)) { [weak session] in session?.deleteContextLayers(for: id) }
            let selected = session.contextMenuSelection(for: id)
            func commands(_ commands: [LayerCommand], into target: NSMenu) {
                for command in commands {
                    add(command.title, identifier: command.identifier, enabled: session.canPerform(command, selection: selected), to: target) { [weak session] in
                        session?.selection = selected; session?.perform(command)
                    }
                }
            }
            menu.addItem(.separator()); commands([.group, .ungroup], into: menu)
            menu.addItem(.separator()); commands(LayerCommand.ordering, into: menu)
            for (title, list) in [("对齐", LayerCommand.alignment), ("等距分布", LayerCommand.distribution)] {
                let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: title); submenu.autoenablesItems = false
                commands(list, into: submenu); entry.submenu = submenu; menu.addItem(entry)
            }
            return menu
        }
        @objc private func runMenuAction(_ sender: LayerTreeMenuItem) { sender.perform?() }
    }
}

@MainActor final class LayerTreeItem: NSObject {
    var node: DesignNode?
    var children: [LayerTreeItem] = []
    var id: UUID? { node?.id }
    var isContainer: Bool { node?.kind == .group || node?.kind == .frame || !children.isEmpty }
    init(node: DesignNode?) { self.node = node }
}

@MainActor final class NativeLayerOutline: NSOutlineView {
    var menuForItem: ((LayerTreeItem) -> NSMenu?)?
    var renameSelection: (() -> Void)?
    var deleteSelection: (() -> Void)?
    override func drawBackground(inClipRect clipRect: NSRect) {
        super.drawBackground(inClipRect: clipRect)
        let visibleRows = rows(in: clipRect)
        guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return }
        let guides = NSBezierPath()
        guides.lineWidth = 1
        for row in visibleRows.location..<min(NSMaxRange(visibleRows), numberOfRows) {
            guard let item = item(atRow: row) as? LayerTreeItem, item.id != nil else { continue }
            let rowRect = rect(ofRow: row)
            var ancestor = parent(forItem: item)
            while let parent = ancestor {
                let parentRow = self.row(forItem: parent)
                guard parentRow >= 0 else { break }
                // Align with the ancestor icon, spanning the complete child row and inter-row gap.
                let x = frameOfCell(atColumn: 0, row: parentRow).minX + LayerTreeCell.iconCenterX
                guides.move(to: NSPoint(x: x, y: rowRect.minY - intercellSpacing.height / 2))
                guides.line(to: NSPoint(x: x, y: rowRect.maxY + intercellSpacing.height / 2))
                ancestor = self.parent(forItem: parent)
            }
        }
        NSColor.separatorColor.setStroke()
        guides.stroke()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let item = item(atRow: row) as? LayerTreeItem else { return nil }
        return menuForItem?(item)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection?()
        } else if event.keyCode == 36 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            renameSelection?()
        } else { super.keyDown(with: event) }
    }
}

@MainActor private final class LayerTreeMenuItem: NSMenuItem {
    var perform: (() -> Void)?
}

@MainActor private final class LayerTreeSelectionRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (dark ? NSColor.white.withAlphaComponent(0.12) : EditorPalette.accent).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0), xRadius: 5, yRadius: 5).fill()
    }
}

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
        visibility.setAccessibilityLabel(node.isVisible ? "隐藏图层" : "显示图层")
        visibility.setAccessibilityIdentifier("layer.visibility.\(node.id)")
        lock.image = NSImage(systemSymbolName: node.isLocked ? "lock.fill" : "lock.open", accessibilityDescription: nil)
        lock.setAccessibilityLabel(node.isLocked ? "解锁图层" : "锁定图层")
        lock.setAccessibilityIdentifier("layer.lock.\(node.id)")
        let edit = session.sidebarRename.flatMap { $0.request.target == .layer(pageID: session.pageID, nodeID: node.id) ? $0 : nil }
        if edit?.request.id != renameID {
            renameField?.finish()
            renameID = edit?.request.id
            renameField = edit.map { NativeSidebarRenameField(session: session, request: $0.request) }
            installName(renameField ?? name)
        }
        setAccessibilityChildren([renameField ?? name, visibility, lock])
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

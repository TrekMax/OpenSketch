import AppKit
import OpenSketchCore

extension NativeLayerTree {
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
                if tree.item(atRow: row) as? LayerTreeItem === footer,
                   let label = tree.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTextField {
                    label.stringValue = L10n.text("↳  移到页面根层级")
                }
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
                let label = NSTextField(labelWithString: L10n.text("↳  移到页面根层级"))
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
            add(L10n.text("重命名"), identifier: "layer.rename") { [weak self] in self?.rename(id) }
            add(L10n.text("复制图层"), identifier: "layer.duplicate", enabled: session.canEditContextLayers(for: id)) { [weak session] in session?.duplicateContextLayers(for: id) }
            add(L10n.text("删除"), identifier: "layer.delete", enabled: session.canEditContextLayers(for: id)) { [weak session] in session?.deleteContextLayers(for: id) }
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
            for (title, list) in [(L10n.text("对齐"), LayerCommand.alignment), (L10n.text("等距分布"), LayerCommand.distribution)] {
                let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: title); submenu.autoenablesItems = false
                commands(list, into: submenu); entry.submenu = submenu; menu.addItem(entry)
            }
            return menu
        }
        @objc private func runMenuAction(_ sender: LayerTreeMenuItem) { sender.perform?() }
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

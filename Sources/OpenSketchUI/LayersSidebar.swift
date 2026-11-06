import SwiftUI
import OpenSketchCore

struct LayersSidebar: View {
    @Bindable var session: EditorSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var collapsed: Set<UUID> = []
    @State private var dropTarget: LayerDropDestination?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("页面").font(.headline); Spacer(); Button { session.addPage() } label: { Image(systemName: "plus") }.accessibilityLabel("添加页面").accessibilityIdentifier("page.add") }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(session.document.pages) { page in
                            pageRow(page).id(page.id)
                        }
                    }
                }
                .frame(height: min(140, CGFloat(session.document.pages.count) * 28))
                .accessibilityIdentifier("page.list")
                .onChange(of: session.pageID) { _, id in proxy.scrollTo(id) }
            }
            EditorDivider(); Text("图层").font(.headline)
            ScrollView {
                VStack(spacing: 4) {
                    let rows = LayerTreeRow.rows(in: session.page, collapsed: collapsed)
                    let marker = LayerTreeRow.belowInsertionMarker(for: dropTarget, in: rows)
                    ForEach(rows) { row in
                        layerRow(row, belowMarker: marker)
                    }
                    Label("移到页面根层级", systemImage: "arrow.turn.up.left")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                        .background(dropTarget == .pageEnd ? EditorPalette.selection(colorScheme) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .help("拖到此处移出画板或编组，并放到图层列表底部")
                        .accessibilityIdentifier("layer.drop.pageEnd")
                        .onDrop(of: [SidebarLayerDrag.typeIdentifier], delegate: dropDelegate(node: nil))
                }
            }
            if session.page.nodes.isEmpty { Text("暂无图层\n在画布上绘制第一个对象").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(12)
        .onDisappear { session.finishSidebarRename(); session.sidebarLayerDrag = nil; dropTarget = nil }
        .onChange(of: session.sidebarLayerDrag?.id) { _, _ in dropTarget = nil }
    }
    private func pageRow(_ page: DesignPage) -> some View {
        let selected = session.selectedPageIDs.contains(page.id)
        return Group {
            if let edit = session.sidebarRename, edit.request.target == .page(page.id) {
                SidebarRenameField(session: session, request: edit.request)
                    .id(edit.request.id).frame(height: 22).padding(.horizontal, 7)
            } else {
                Button {
                    session.selectPage(page.id, extending: (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift))
                } label: {
                    Text(page.name).lineLimit(1)
                        .fontWeight(session.pageID == page.id ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7).frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("page.row.\(page.id)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(session.pageID == page.id ? "当前页面" : (selected ? "已选中" : "未选中"))
            }
        }
        .frame(height: 28)
        .foregroundStyle(selected ? EditorPalette.selectionForeground(colorScheme) : .primary)
        .background(selected ? EditorPalette.selection(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contextMenu {
            Button("重命名") { session.startSidebarRename(.page(page.id)) }
                .accessibilityIdentifier("page.rename")
        }
    }

    private func layerRow(_ row: LayerTreeRow, belowMarker: (rowID: UUID, depth: Int)?) -> some View {
        let node = row.node
        let selected = session.selection.contains(node.id)
        return HStack(spacing: 4) {
            HStack(spacing: 4) {
                if node.kind == .group || node.kind == .frame || !node.children.isEmpty {
                    Button {
                        session.finishInput?()
                        if collapsed.contains(node.id) { collapsed.remove(node.id) }
                        else { collapsed.insert(node.id) }
                    } label: {
                        Image(systemName: collapsed.contains(node.id) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    }
                    .accessibilityLabel(collapsed.contains(node.id) ? "展开图层" : "折叠图层")
                    .accessibilityIdentifier("layer.expand.\(node.id)")
                    .accessibilityValue(collapsed.contains(node.id) ? "已折叠" : "已展开")
                } else { Color.clear.frame(width: 10, height: 10).accessibilityHidden(true).allowsHitTesting(false) }
                Image(systemName: node.kind.layerSymbol).frame(width: 14).accessibilityHidden(true).allowsHitTesting(false)
                if let edit = session.sidebarRename,
                   edit.request.target == .layer(pageID: session.pageID, nodeID: node.id) {
                    SidebarRenameField(session: session, request: edit.request)
                        .id(edit.request.id).frame(height: 18)
                } else {
                    Button { session.selectLayer(node.id, event: NSApp.currentEvent, fallbackModifiers: NSEvent.modifierFlags) } label: {
                        Text(node.name.isEmpty ? node.kind.layerTitle : node.name).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("layer.\(node.id)")
                    .accessibilityValue("层级 \(row.depth + 1)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.padding(.leading, CGFloat(row.depth) * 14)
            Button { session.change { $0.updateNode(id: node.id) { $0.isVisible.toggle() } } } label: {
                Image(systemName: node.isVisible ? "eye" : "eye.slash")
            }.accessibilityLabel(node.isVisible ? "隐藏图层" : "显示图层").accessibilityIdentifier("layer.visibility.\(node.id)")
            Button { session.change { $0.updateNode(id: node.id) { $0.isLocked.toggle() } } } label: {
                Image(systemName: node.isLocked ? "lock.fill" : "lock.open")
            }.accessibilityLabel(node.isLocked ? "解锁图层" : "锁定图层").accessibilityIdentifier("layer.lock.\(node.id)")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(selected && colorScheme == .light ? .white : .primary)
        .tint(selected && colorScheme == .light ? .white : .primary)
        .frame(height: LayerTreeDropDelegate.rowHeight - 14)
        .padding(7)
        .background {
            // Fill row padding, indentation and icon gaps without intercepting
            // the name editor or the independent disclosure/visibility/lock buttons.
            Button { session.selectLayer(node.id, event: NSApp.currentEvent, fallbackModifiers: NSEvent.modifierFlags) } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .background(selected ? EditorPalette.layerSelection(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            if dropTarget == .inside(node.id) {
                RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: EditorPalette.accent), lineWidth: 2).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) { insertionLine(visible: dropTarget == .above(node.id), depth: row.depth) }
        .overlay(alignment: .bottom) {
            insertionLine(visible: belowMarker?.rowID == node.id, depth: belowMarker?.depth ?? row.depth)
        }
        .modifier(LayerTreeDragSource(session: session, node: node))
        .onDrop(of: [SidebarLayerDrag.typeIdentifier], delegate: dropDelegate(node: node))
        .accessibilityElement(children: .contain)
        .contextMenu {
            LayerCommandsMenu(session: session, rowID: node.id) {
                session.startSidebarRename(.layer(pageID: session.pageID, nodeID: node.id))
            }
        }
    }

    private func dropDelegate(node: DesignNode?) -> LayerTreeDropDelegate {
        LayerTreeDropDelegate(session: session, node: node, target: $dropTarget) { collapsed.remove($0) }
    }

    @ViewBuilder private func insertionLine(visible: Bool, depth: Int) -> some View {
        if visible {
            Rectangle().fill(Color(nsColor: EditorPalette.accent)).frame(height: 2)
                .padding(.leading, CGFloat(depth) * 14).allowsHitTesting(false)
        }
    }
}

/// UI display order reverses each sibling list, keeping parents before descendants.
struct LayerTreeRow: Identifiable {
    let node: DesignNode
    let depth: Int
    var id: UUID { node.id }

    static func belowInsertionMarker(for destination: LayerDropDestination?, in rows: [Self]) -> (rowID: UUID, depth: Int)? {
        guard case .below(let id) = destination, let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        let depth = rows[index].depth
        var last = index
        while last + 1 < rows.count && rows[last + 1].depth > depth { last += 1 }
        return (rows[last].id, depth)
    }

    static func rows(in page: DesignPage, collapsed: Set<UUID> = []) -> [Self] {
        var result: [Self] = []
        func visit(_ nodes: [DesignNode], depth: Int) {
            for node in nodes.reversed() {
                result.append(Self(node: node, depth: depth))
                if !collapsed.contains(node.id) { visit(node.children, depth: depth + 1) }
            }
        }
        visit(page.nodes, depth: 0)
        return result
    }
}

private extension NodeKind {
    var layerSymbol: String {
        switch self {
        case .group: "folder"
        case .frame: "rectangle.dashed"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .path: "point.topleft.down.curvedto.point.bottomright.up"
        }
    }
    var layerTitle: String {
        switch self {
        case .group: "编组"
        case .frame: "画板"
        case .rectangle: "矩形"
        case .ellipse: "椭圆"
        case .text: "文字"
        case .path: "路径"
        }
    }
}

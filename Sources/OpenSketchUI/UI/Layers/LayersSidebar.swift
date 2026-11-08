import SwiftUI
import OpenSketchCore

struct LayersSidebar: View {
    @Bindable var session: EditorSession
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(L10n.text("页面")).font(.headline); Spacer(); Button { session.addPage() } label: { Image(systemName: "plus") }.accessibilityLabel(L10n.text("添加页面")).accessibilityIdentifier("page.add") }
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
            EditorDivider(); Text(L10n.text("图层")).font(.headline)
            NativeLayerTree(session: session)
            if session.page.nodes.isEmpty { Text(L10n.text("暂无图层\n在画布上绘制第一个对象")).font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(12)
        .onDisappear { session.finishSidebarRename(); session.sidebarLayerDrag = nil }
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
                .accessibilityValue(session.pageID == page.id ? L10n.text("当前页面") : (selected ? L10n.text("已选中") : L10n.text("未选中")))
            }
        }
        .frame(height: 28)
        .foregroundStyle(selected ? EditorPalette.selectionForeground(colorScheme) : .primary)
        .background(selected ? EditorPalette.selection(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contextMenu {
            Button(L10n.text("重命名")) { session.startSidebarRename(.page(page.id)) }
                .accessibilityIdentifier("page.rename")
        }
    }

}

extension NodeKind {
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
    @MainActor var layerTitle: String {
        switch self {
        case .group: L10n.text("编组")
        case .frame: L10n.text("画板")
        case .rectangle: L10n.text("矩形")
        case .ellipse: L10n.text("椭圆")
        case .text: L10n.text("文字")
        case .path: L10n.text("路径")
        }
    }
}

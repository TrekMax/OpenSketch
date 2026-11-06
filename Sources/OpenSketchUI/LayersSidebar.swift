import SwiftUI
import OpenSketchCore

struct LayersSidebar: View {
    @Bindable var session: EditorSession
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("页面").font(.headline); Spacer(); Button { session.addPage() } label: { Image(systemName: "plus") }.accessibilityLabel("添加页面").accessibilityIdentifier("page.add") }
            Picker("当前页面", selection: Binding(get: { session.pageID }, set: { session.finishInput?(); session.pageID = $0; session.selection = [] })) { ForEach(session.document.pages) { Text($0.name).tag($0.id) } }.labelsHidden().accessibilityIdentifier("page.selector")
            Divider(); Text("图层").font(.headline)
            ScrollView { VStack(spacing: 4) { ForEach(Array(SceneGeometry.traversal(in: session.page).reversed())) { node in
                HStack(spacing: 4) {
                    Button { session.finishInput?(); if NSEvent.modifierFlags.contains(.shift) { session.selection.insert(node.id) } else { session.selection = [node.id] } } label: { Text(node.name.isEmpty ? node.kind.rawValue : node.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, session.document.parentID(of: node.id) == nil ? 0 : 12) }.buttonStyle(.plain).accessibilityIdentifier("layer.\(node.id)")
                    Button { session.change { $0.updateNode(id: node.id) { $0.isVisible.toggle() } } } label: { Image(systemName: node.isVisible ? "eye" : "eye.slash") }.accessibilityLabel(node.isVisible ? "隐藏图层" : "显示图层").accessibilityIdentifier("layer.visibility.\(node.id)")
                    Button { session.change { $0.updateNode(id: node.id) { $0.isLocked.toggle() } } } label: { Image(systemName: node.isLocked ? "lock.fill" : "lock.open") }.accessibilityLabel(node.isLocked ? "解锁图层" : "锁定图层").accessibilityIdentifier("layer.lock.\(node.id)")
                }.buttonStyle(.borderless).padding(7).background(session.selection.contains(node.id) ? EditorPalette.selection(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 5))
            } } }
            if session.page.nodes.isEmpty { Text("暂无图层\n在画布上绘制第一个对象").font(.caption).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            HStack { Button("复制图层") { session.duplicate() }.disabled(session.roots.isEmpty).accessibilityIdentifier("layer.duplicate"); Button("删除") { session.deleteSelection() }.disabled(session.roots.isEmpty).accessibilityIdentifier("layer.delete") }
        }.padding(12)
    }
}

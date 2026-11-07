import SwiftUI
import OpenSketchCore

struct EditorRootView: View {
    @Bindable var workspace: DocumentWorkspace
    @Bindable var appearance: AppAppearance
    var exportDocument: ((UUID) -> Void)? = nil
    var body: some View {
        let document = workspace.current
        DocumentEditorView(session: document.session, appearance: appearance, export: exportDocument.map { action in { action(document.id) } })
            .id(document.id)
    }
}

private struct DocumentEditorView: View {
    @Bindable var session: EditorSession
    @Bindable var appearance: AppAppearance
    var export: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    Button { session.finishInput?(); session.tool = tool } label: {
                        Label(tool.title, systemImage: tool.symbol)
                            .foregroundStyle(session.tool == tool ? EditorPalette.selectionForeground(colorScheme) : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(session.tool == tool ? EditorPalette.selection(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("tool.\(tool.rawValue)")
                    .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
                }
                Spacer()
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!session.canUndo).accessibilityLabel("撤销").accessibilityIdentifier("action.undo")
                Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!session.history.canRedo).accessibilityLabel("重做").accessibilityIdentifier("action.redo")
            }
            .padding(.horizontal, 12)
            .font(.system(size: 12))
            .frame(height: 42)
            EditorDivider()
            HStack(spacing: 0) { LayersSidebar(session: session).frame(width: 220); EditorDivider(); CanvasHost(session: session).frame(maxWidth: .infinity, maxHeight: .infinity); EditorDivider(); InspectorView(session: session, export: export).frame(width: 260) }
            EditorDivider()
            HStack {
                Text(session.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Picker("外观", selection: $appearance.mode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }
                .frame(width: 150)
                .accessibilityIdentifier("view.appearance")
                Toggle("吸附", isOn: Binding(get: { session.snapping }, set: { session.finishInput?(); session.snapping = $0 })).accessibilityIdentifier("view.snapping")
                Toggle("网格", isOn: $session.grid).accessibilityIdentifier("view.grid")
                Text("\(Int((session.zoom * 100).rounded()))%").monospacedDigit().frame(width: 48)
            }.padding(8)
        }
        .background(Color(nsColor: EditorPalette.panel))
        .tint(colorScheme == .light ? Color(nsColor: EditorPalette.accent) : .primary)
        .frame(minWidth: 980, minHeight: 620)
    }
}

import SwiftUI
import OpenSketchCore

struct EditorRootView: View {
    @Bindable var session: EditorSession
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("openSketch").font(.headline).padding(.trailing, 18)
                ForEach(EditorTool.allCases, id: \.self) { tool in
                    Button { session.finishInput?(); session.tool = tool } label: { Label(tool.title, systemImage: tool.symbol).padding(.horizontal, 5) }
                        .tint(session.tool == tool ? .purple : .secondary).buttonStyle(.bordered).accessibilityIdentifier("tool.\(tool.rawValue)")
                }
                Spacer(); Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!session.history.canUndo).accessibilityLabel("撤销").accessibilityIdentifier("action.undo")
                Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!session.history.canRedo).accessibilityLabel("重做").accessibilityIdentifier("action.redo")
            }.padding(12)
            Divider()
            HStack(spacing: 0) { LayersSidebar(session: session).frame(width: 220); Divider(); CanvasHost(session: session).frame(maxWidth: .infinity, maxHeight: .infinity); Divider(); InspectorView(session: session).frame(width: 260) }
            Divider()
            HStack { Text(session.message).font(.caption).foregroundStyle(.secondary).lineLimit(1); Spacer(); Toggle("网格", isOn: $session.grid).accessibilityIdentifier("view.grid"); Button("适合窗口") { session.fitCanvas?() }.accessibilityIdentifier("view.fit"); Button("100%") { session.finishInput?(); session.zoom = 1 }.accessibilityIdentifier("view.actualSize"); Text("\(Int(session.zoom*100))%").monospacedDigit().frame(width: 48) }.padding(8)
        }.tint(.purple).frame(minWidth: 980, minHeight: 620)
    }
}

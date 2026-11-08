import SwiftUI
import OpenSketchCore

struct InspectorView: View {
    @Bindable var session: EditorSession
    var export: (() -> Void)? = nil

    private func number(_ property: InspectorNumberProperty, node: DesignNode) -> some View {
        InspectorNumberField(session: session, nodeID: node.id, property: property)
            .frame(maxWidth: .infinity).frame(height: 26)
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).padding(.top, 10)
    }
    private func textBinding(_ node: DesignNode, _ keyPath: WritableKeyPath<DesignNode, String>) -> Binding<String> {
        Binding(get: { (session.document.node(id: node.id) ?? node)[keyPath: keyPath] },
                set: { value in session.update(node.id) { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                properties
                    .disabled(session.selected.map { !session.editable($0.id) } ?? false)
                EditorDivider()
                InspectorExportView(session: session, export: export)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .onDisappear { session.finishInspectorInput() }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let node = session.selected {
                TextField(L10n.text("图层名称"), text: textBinding(node, \.name))
                    .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .padding(.vertical, 4).accessibilityIdentifier("inspector.name")
            } else {
                Text(L10n.text("检查器")).font(.system(size: 12, weight: .semibold)).padding(.vertical, 4)
            }
            LayerActionsView(session: session)
            if let node = session.selected {
                HStack(spacing: 8) { number(.x, node: node); number(.y, node: node) }
                sectionTitle(L10n.text("布局"))
                HStack(spacing: 8) { number(.width, node: node); number(.height, node: node) }
                if node.kind == .group {
                    Text(L10n.text("编组尺寸只读")).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    number(.rotation, node: node)
                    Color.clear.frame(maxWidth: .infinity).frame(height: 26)
                }
                if node.kind == .frame {
                    Toggle(L10n.text("裁剪内容"), isOn: Binding(get: { node.clipsContent }, set: { value in session.update(node.id) { $0.clipsContent = value } }))
                        .accessibilityIdentifier("inspector.clip")
                }
                sectionTitle(L10n.text("样式"))
                HStack(spacing: 8) {
                    number(.opacity, node: node)
                    if node.kind != .group { number(.cornerRadius, node: node) }
                    else { Color.clear.frame(maxWidth: .infinity).frame(height: 26) }
                }
                if node.kind != .group {
                    paintSection(node: node, stroke: false)
                    paintSection(node: node, stroke: true)
                }
                if node.kind == .text {
                    sectionTitle(L10n.text("文字"))
                    TextField(L10n.text("文字内容"), text: textBinding(node, \.text), axis: .vertical)
                        .lineLimit(3...8).modifier(EditorFieldStyle(roundedInDark: true))
                        .accessibilityIdentifier("inspector.text")
                    TextField(L10n.text("字体名称"), text: textBinding(node, \.fontName))
                        .modifier(EditorFieldStyle(roundedInDark: true)).accessibilityIdentifier("inspector.font")
                    HStack(spacing: 8) {
                        number(.fontSize, node: node)
                        Picker(L10n.text("对齐"), selection: Binding(get: { node.textAlignment }, set: { value in session.update(node.id) { $0.textAlignment = value } })) {
                            Text(L10n.text("左")).tag(ParagraphAlignment.left)
                            Text(L10n.text("中")).tag(ParagraphAlignment.center)
                            Text(L10n.text("右")).tag(ParagraphAlignment.right)
                        }.labelsHidden().accessibilityLabel(L10n.text("文字对齐")).accessibilityIdentifier("inspector.alignment")
                    }
                }
                if !session.editable(node.id) {
                    Text(L10n.text("图层或祖先已锁定 / 隐藏")).foregroundStyle(.secondary)
                }
            } else {
                Text(session.selection.isEmpty ? L10n.text("选择图层以编辑属性") : L10n.format("已选择 %d 个图层", session.selection.count))
                    .foregroundStyle(.secondary).padding(.top, 8)
            }
        }
        .font(.system(size: 11)).controlSize(.small)
    }

    private func paintSection(node: DesignNode, stroke: Bool) -> some View {
        let title = stroke ? L10n.text("边框") : L10n.text("填充")
        let color = stroke ? node.style.stroke : node.style.fill
        let identifier = stroke ? "stroke" : "fill"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.medium).foregroundStyle(.secondary)
                Spacer()
                Toggle(title, isOn: Binding(get: { color != nil }, set: { enabled in
                    session.update(node.id) {
                        if stroke { $0.style.stroke = enabled ? .black : nil }
                        else { $0.style.fill = enabled ? .white : nil }
                    }
                }))
                .labelsHidden().toggleStyle(.switch)
                .accessibilityIdentifier("inspector.\(identifier)Enabled")
            }.padding(.top, 8)
            if let color {
                ColorPicker(stroke ? L10n.text("描边颜色") : L10n.text("填充颜色"), selection: Binding(get: { Color(nsColor: color.nsColor) }, set: { value in
                    session.update(node.id) {
                        if stroke { $0.style.stroke = RGBAColor(NSColor(value)) }
                        else { $0.style.fill = RGBAColor(NSColor(value)) }
                    }
                }))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(nsColor: EditorPalette.inspectorControl), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("inspector.\(identifier)")
            }
            if stroke { number(.strokeWidth, node: node) }
        }
    }
}

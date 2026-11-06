import SwiftUI
import OpenSketchCore

struct InspectorView: View {
    @Bindable var session: EditorSession

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
            VStack(alignment: .leading, spacing: 10) {
                if let node = session.selected {
                    TextField("图层名称", text: textBinding(node, \.name))
                        .textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.vertical, 4).accessibilityIdentifier("inspector.name")
                } else {
                    Text("检查器").font(.system(size: 12, weight: .semibold)).padding(.vertical, 4)
                }
                LayerActionsView(session: session)
                if let node = session.selected {
                    HStack(spacing: 8) { number(.x, node: node); number(.y, node: node) }
                    sectionTitle("布局")
                    HStack(spacing: 8) { number(.width, node: node); number(.height, node: node) }
                    if node.kind == .group {
                        Text("编组尺寸只读").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        number(.rotation, node: node)
                        Color.clear.frame(maxWidth: .infinity).frame(height: 26)
                    }
                    if node.kind == .frame {
                        Toggle("裁剪内容", isOn: Binding(get: { node.clipsContent }, set: { value in session.update(node.id) { $0.clipsContent = value } }))
                            .accessibilityIdentifier("inspector.clip")
                    }
                    sectionTitle("样式")
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
                        sectionTitle("文字")
                        TextField("文字内容", text: textBinding(node, \.text), axis: .vertical)
                            .lineLimit(3...8).modifier(EditorFieldStyle(roundedInDark: true))
                            .accessibilityIdentifier("inspector.text")
                        TextField("字体名称", text: textBinding(node, \.fontName))
                            .modifier(EditorFieldStyle(roundedInDark: true)).accessibilityIdentifier("inspector.font")
                        HStack(spacing: 8) {
                            number(.fontSize, node: node)
                            Picker("对齐", selection: Binding(get: { node.textAlignment }, set: { value in session.update(node.id) { $0.textAlignment = value } })) {
                                Text("左").tag(ParagraphAlignment.left)
                                Text("中").tag(ParagraphAlignment.center)
                                Text("右").tag(ParagraphAlignment.right)
                            }.labelsHidden().accessibilityLabel("文字对齐").accessibilityIdentifier("inspector.alignment")
                        }
                    }
                    if !session.editable(node.id) {
                        Text("图层或祖先已锁定 / 隐藏").foregroundStyle(.secondary)
                    }
                } else {
                    Text(session.selection.isEmpty ? "选择图层以编辑属性" : "已选择 \(session.selection.count) 个图层")
                        .foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .font(.system(size: 11)).controlSize(.small)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .disabled(session.selected.map { !session.editable($0.id) } ?? false)
        }
        .onDisappear { session.finishInspectorInput() }
    }

    private func paintSection(node: DesignNode, stroke: Bool) -> some View {
        let title = stroke ? "边框" : "填充"
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
                ColorPicker(stroke ? "描边颜色" : "填充颜色", selection: Binding(get: { Color(nsColor: color.nsColor) }, set: { value in
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

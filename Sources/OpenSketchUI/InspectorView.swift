import SwiftUI
import OpenSketchCore

struct InspectorView: View {
    @Bindable var session: EditorSession
    func number(_ title: String, _ id: String, node: DesignNode, get: @escaping (DesignNode)->Double, set: @escaping (inout DesignNode,Double)->Void) -> some View {
        HStack { Text(title).frame(width: 58, alignment: .leading); TextField(title, value: Binding(get: { get(session.document.node(id: node.id) ?? node) }, set: { value in guard value.isFinite else { return }; session.update(node.id) { set(&$0,value) } }), format: .number.precision(.fractionLength(0...2))).modifier(EditorFieldStyle(roundedInDark: true)).accessibilityIdentifier("inspector.\(id)") }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("检查器").font(.headline)
                LayerActionsView(session: session)
                EditorDivider()
                if let n = session.selected {
                    TextField("图层名称", text: Binding(get: { session.document.node(id: n.id)?.name ?? "" }, set: { value in session.update(n.id) { $0.name = value } })).modifier(EditorFieldStyle()).accessibilityIdentifier("inspector.name")
                    number("X", "x", node: n, get: { $0.frame.origin.x }, set: { $0.frame.origin.x = max(-1e9,min(1e9,$1)) })
                    number("Y", "y", node: n, get: { $0.frame.origin.y }, set: { $0.frame.origin.y = max(-1e9,min(1e9,$1)) })
                    if n.kind == .group {
                        LabeledContent("宽") { Text(n.frame.width, format: .number.precision(.fractionLength(0...2))) }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("宽")
                            .accessibilityValue(Text(n.frame.width, format: .number.precision(.fractionLength(0...2))))
                            .accessibilityIdentifier("inspector.width")
                        LabeledContent("高") { Text(n.frame.height, format: .number.precision(.fractionLength(0...2))) }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("高")
                            .accessibilityValue(Text(n.frame.height, format: .number.precision(.fractionLength(0...2))))
                            .accessibilityIdentifier("inspector.height")
                        Text("编组尺寸只读").font(.caption).foregroundStyle(.secondary)
                    } else {
                        number("宽", "width", node: n, get: { $0.frame.width }, set: { $0.frame.size.width = max(1,min(1e7,$1)) })
                        number("高", "height", node: n, get: { $0.frame.height }, set: { $0.frame.size.height = max(1,min(1e7,$1)) })
                    }
                    number("旋转", "rotation", node: n, get: { $0.rotation }, set: { $0.rotation = $1.truncatingRemainder(dividingBy: 360) })
                    EditorDivider()
                    if n.kind != .group {
                        Toggle("填充", isOn: Binding(get: { n.style.fill != nil }, set: { value in session.update(n.id) { $0.style.fill = value ? .white : nil } })).accessibilityIdentifier("inspector.fillEnabled")
                        if n.style.fill != nil { ColorPicker("填充颜色", selection: Binding(get: { Color(nsColor: n.style.fill!.nsColor) }, set: { color in session.update(n.id) { $0.style.fill = RGBAColor(NSColor(color)) } })).accessibilityIdentifier("inspector.fill") }
                        Toggle("描边", isOn: Binding(get: { n.style.stroke != nil }, set: { value in session.update(n.id) { $0.style.stroke = value ? .black : nil } })).accessibilityIdentifier("inspector.strokeEnabled")
                        if let stroke = n.style.stroke { ColorPicker("描边颜色", selection: Binding(get: { Color(nsColor: stroke.nsColor) }, set: { color in session.update(n.id) { $0.style.stroke = RGBAColor(NSColor(color)) } })).accessibilityIdentifier("inspector.stroke") }
                        number("线宽", "strokeWidth", node: n, get: { $0.style.strokeWidth }, set: { $0.style.strokeWidth = max(0,min(10000,$1)) })
                        number("圆角", "cornerRadius", node: n, get: { $0.style.cornerRadius }, set: { $0.style.cornerRadius = max(0,min(1e7,$1)) })
                    }
                    if n.kind == .frame { Toggle("裁剪内容", isOn: Binding(get: { n.clipsContent }, set: { value in session.update(n.id) { $0.clipsContent = value } })).accessibilityIdentifier("inspector.clip") }
                    if n.kind == .text {
                        EditorDivider(); Text("文字内容")
                        TextField("文字内容", text: Binding(get: { n.text }, set: { value in session.update(n.id) { $0.text = value } }), axis: .vertical).lineLimit(3...8).modifier(EditorFieldStyle()).accessibilityIdentifier("inspector.text")
                        TextField("字体名称", text: Binding(get: { n.fontName }, set: { value in session.update(n.id) { $0.fontName = value } })).modifier(EditorFieldStyle()).accessibilityIdentifier("inspector.font")
                        number("字号", "fontSize", node: n, get: { $0.fontSize }, set: { $0.fontSize = max(1,min(1000,$1)) })
                        Picker("对齐", selection: Binding(get: { n.textAlignment }, set: { value in session.update(n.id) { $0.textAlignment = value } })) { Text("左").tag(ParagraphAlignment.left); Text("中").tag(ParagraphAlignment.center); Text("右").tag(ParagraphAlignment.right) }.accessibilityIdentifier("inspector.alignment")
                    }
                    if !session.editable(n.id) { Text("图层或祖先已锁定 / 隐藏").foregroundStyle(.secondary) }
                } else { Text(session.selection.isEmpty ? "选择图层以编辑属性" : "已选择 \(session.selection.count) 个图层").foregroundStyle(.secondary) }
            }.padding(14).disabled(session.selected.map { !session.editable($0.id) } ?? false)
        }
    }
}

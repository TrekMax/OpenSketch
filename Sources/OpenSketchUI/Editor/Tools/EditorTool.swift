enum EditorTool: String, CaseIterable { case select, frame, rectangle, ellipse, pen, text
    @MainActor var title: String { switch self { case .select: L10n.text("选择"); case .frame: L10n.text("画板"); case .rectangle: L10n.text("矩形"); case .ellipse: L10n.text("椭圆"); case .pen: L10n.text("钢笔"); case .text: L10n.text("文字") } }
    var symbol: String { switch self { case .select: "cursorarrow"; case .frame: "rectangle.dashed"; case .rectangle: "rectangle"; case .ellipse: "circle"; case .pen: "pencil.tip"; case .text: "textformat" } }
}

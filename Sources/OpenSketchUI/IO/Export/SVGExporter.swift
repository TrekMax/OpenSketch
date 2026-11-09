import Foundation
import OpenSketchCore

@MainActor enum SVGExporter {
    static func data(page: DesignPage, bounds: CGRect) throws -> Data {
        guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else {
            throw EditorError.invalid("导出区域或倍率无效。")
        }
        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        output += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(bounds.width))\" height=\"\(number(bounds.height))\" viewBox=\"\(number(bounds.minX)) \(number(bounds.minY)) \(number(bounds.width)) \(number(bounds.height))\">\n"
        if let gradients = gradientDefinitions(page.nodes), !gradients.isEmpty {
            output += "<defs>\(gradients)</defs>\n"
        }
        output += nodes(page.nodes, parent: .identity)
        output += "</svg>\n"
        return Data(output.utf8)
    }

    private static func nodes(_ items: [DesignNode], parent: CGAffineTransform) -> String {
        items.filter(\.isVisible).map { node in
            let transform = SceneGeometry.localTransform(for: node).concatenating(parent)
            let matrix = "matrix(\(number(transform.a)) \(number(transform.b)) \(number(transform.c)) \(number(transform.d)) \(number(transform.tx)) \(number(transform.ty)))"
            let shape = shape(for: node)
            let style = style(for: node)
            let children = nodes(node.children, parent: transform)
            return "<g transform=\"\(matrix)\" opacity=\"\(number(node.style.opacity))\">\(shape.map { $0.replacingOccurrences(of: ">", with: " style=\"\(style)\">") } ?? "")\(children)</g>\n"
        }.joined()
    }

    private static func shape(for node: DesignNode) -> String? {
        let rect = CGRect(origin: .zero, size: node.frame.size)
        switch node.kind {
        case .rectangle, .frame, .group:
            return node.kind == .group ? nil : "<rect x=\"0\" y=\"0\" width=\"\(number(rect.width))\" height=\"\(number(rect.height))\" rx=\"\(number(min(node.style.cornerRadius, min(rect.width, rect.height) / 2)))\">"
        case .ellipse:
            return "<ellipse cx=\"\(number(rect.midX))\" cy=\"\(number(rect.midY))\" rx=\"\(number(rect.width / 2))\" ry=\"\(number(rect.height / 2))\">"
        case .path:
            return "<path d=\"\(path(node.path))\">"
        case .text:
            return "<text x=\"0\" y=\"\(number(node.fontSize))\" font-family=\"\(escape(node.fontName))\" font-size=\"\(number(node.fontSize))\">\(escape(node.text))</text>"
        }
    }

    private static func style(for node: DesignNode) -> String {
        var values = [String]()
        if let fill = node.style.fill { values.append("fill:\(color(fill))") }
        else if node.style.linearGradient != nil { values.append("fill:url(#gradient-\(node.id.uuidString))") }
        else { values.append("fill:none") }
        if let stroke = node.style.stroke {
            values.append("stroke:\(color(stroke))")
            values.append("stroke-width:\(number(node.style.strokeWidth))")
            values.append("stroke-linecap:\(node.style.strokeLineCap.rawValue)")
            values.append("stroke-linejoin:\(node.style.strokeLineJoin.rawValue)")
        } else { values.append("stroke:none") }
        return values.joined(separator: ";")
    }

    private static func gradientDefinitions(_ nodes: [DesignNode]) -> String? {
        let all = SceneGeometry.traversal(in: DesignPage(nodes: nodes)).compactMap { node -> String? in
            guard let gradient = node.style.linearGradient, gradient.stops.count >= 2 else { return nil }
            let stops = gradient.stops.map { "<stop offset=\"\(number($0.position * 100))%\" stop-color=\"\(color($0.color))\"/>" }.joined()
            return "<linearGradient id=\"gradient-\(node.id.uuidString)\" x1=\"\(number(gradient.start.x * 100))%\" y1=\"\(number(gradient.start.y * 100))%\" x2=\"\(number(gradient.end.x * 100))%\" y2=\"\(number(gradient.end.y * 100))%\">\(stops)</linearGradient>"
        }
        return all.isEmpty ? nil : all.joined()
    }

    private static func path(_ path: VectorPath) -> String {
        path.commands.map { command in
            switch command {
            case .move(let p): "M \(number(p.x)) \(number(p.y))"
            case .line(let p): "L \(number(p.x)) \(number(p.y))"
            case .cubic(let c1, let c2, let p): "C \(number(c1.x)) \(number(c1.y)) \(number(c2.x)) \(number(c2.y)) \(number(p.x)) \(number(p.y))"
            case .close: "Z"
            }
        }.joined(separator: " ")
    }

    private static func color(_ color: RGBAColor) -> String { "#" + [color.red, color.green, color.blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined() }
    private static func number(_ value: CGFloat) -> String { String(format: "%.4g", Double(value)) }
    private static func number(_ value: Double) -> String { String(format: "%.4g", value) }
    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
}

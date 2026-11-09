import Foundation
import OpenSketchCore

/// Deliberately limited SVG importer for the first interoperability milestone.
/// It accepts rect, circle, ellipse, line, path (M/L/C/Z), and text elements.
@MainActor enum SVGImporter {
    static func document(data: Data, name: String) throws -> DesignDocument {
        let parser = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse(), !parser.nodes.isEmpty else { throw EditorError.invalid("SVG 文件无法解析或没有受支持的图形。") }
        let size = CGSize(width: parser.width ?? 1440, height: parser.height ?? 900)
        return DesignDocument(name: name, pages: [DesignPage(name: "页面 1", size: size, nodes: parser.nodes)])
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var nodes: [DesignNode] = []
        var width: CGFloat?
        var height: CGFloat?
        var viewBox: CGRect?
        private var text = ""
        private var groups: [[DesignNode]] = []
        private var styleContexts: [[String: String]] = [[:]]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String : String] = [:]) {
            if name == "svg" {
                width = number(attributes["width"]); height = number(attributes["height"])
                viewBox = rectangle(attributes["viewBox"])
                if width == nil { width = viewBox?.width }
                if height == nil { height = viewBox?.height }
            }
            if name == "g" {
                groups.append([])
                styleContexts.append(merged(attributes))
                return
            }
            guard var node = makeNode(name: name, attributes: attributes, inherited: styleContexts.last ?? [:]) else { return }
            apply(transform: attributes["transform"], to: &node)
            if groups.isEmpty { nodes.append(node) } else { groups[groups.count - 1].append(node) }
            if name == "text" { text = "" }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            if name == "g", let children = groups.popLast(), !children.isEmpty {
                _ = styleContexts.popLast()
                let group = DesignNode(name: "SVG Group", kind: .group, frame: CGRect(x: 0, y: 0, width: width ?? 1440, height: height ?? 900), children: children)
                if groups.isEmpty { nodes.append(group) } else { groups[groups.count - 1].append(group) }
                return
            }
            guard name == "text", let index = nodes.indices.last else { return }
            nodes[index].text = text
            text = ""
        }

        private func makeNode(name: String, attributes: [String: String], inherited: [String: String]) -> DesignNode? {
            let x = number(attributes["x"]) ?? 0, y = number(attributes["y"]) ?? 0
            var values = inherited; values.merge(merged(attributes)) { _, child in child }
            let fill = color(values["fill"])
            let stroke = color(values["stroke"])
            let style = NodeStyle(fill: fill, stroke: stroke, strokeWidth: number(values["stroke-width"]) ?? 1)
            switch name {
            case "rect":
                return DesignNode(name: "SVG Rectangle", kind: .rectangle, frame: CGRect(x: x, y: y, width: number(attributes["width"]) ?? 0, height: number(attributes["height"]) ?? 0), style: style, text: "")
            case "circle":
                let r = number(attributes["r"]) ?? 0
                return DesignNode(name: "SVG Circle", kind: .ellipse, frame: CGRect(x: (number(attributes["cx"]) ?? x) - r, y: (number(attributes["cy"]) ?? y) - r, width: r * 2, height: r * 2), style: style)
            case "ellipse":
                let rx = number(attributes["rx"]) ?? 0, ry = number(attributes["ry"]) ?? 0
                return DesignNode(name: "SVG Ellipse", kind: .ellipse, frame: CGRect(x: (number(attributes["cx"]) ?? x) - rx, y: (number(attributes["cy"]) ?? y) - ry, width: rx * 2, height: ry * 2), style: style)
            case "line":
                let x2 = number(attributes["x2"]) ?? x, y2 = number(attributes["y2"]) ?? y
                return try? PathEditing.makeNode(name: "SVG Line", points: [CGPoint(x: x, y: y), CGPoint(x: x2, y: y2)], style: style)
            case "path":
                guard let path = parsePath(attributes["d"] ?? "") else { return nil }
                let bounds = pathBounds(path)
                return DesignNode(name: "SVG Path", kind: .path, frame: bounds, style: style, path: path)
            case "text":
                return DesignNode(name: "SVG Text", kind: .text, frame: CGRect(x: x, y: y, width: 300, height: 60), style: style, fontSize: number(values["font-size"]) ?? 24)
            default: return nil
            }
        }

        private func apply(transform value: String?, to node: inout DesignNode) {
            guard let value else { return }
            let pattern = #"(translate|rotate|scale|matrix)\s*\(([^)]*)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let typeRange = Range(match.range(at: 1), in: value),
                      let valuesRange = Range(match.range(at: 2), in: value) else { continue }
                let type = String(value[typeRange])
                let values = String(value[valuesRange]).split { $0 == "," || $0 == " " }.compactMap { Double($0) }
                if type == "translate", let x = values.first {
                    node.frame.origin.x += x
                    if values.count > 1 { node.frame.origin.y += values[1] }
                } else if type == "rotate", let angle = values.first {
                    node.rotation += angle
                } else if type == "scale", let x = values.first {
                    let y = values.count > 1 ? values[1] : x
                    node.frame.origin.x *= x; node.frame.origin.y *= y
                    node.frame.size.width *= abs(x); node.frame.size.height *= abs(y)
                } else if type == "matrix", values.count == 6 {
                    node.frame.origin = node.frame.origin.applying(CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5]))
                    node.rotation += atan2(values[1], values[0]) * 180 / .pi
                }
            }
        }

        private func merged(_ attributes: [String: String]) -> [String: String] {
            var result = attributes
            for key in ["fill", "stroke", "stroke-width", "font-size"] where result[key] == nil {
                if let value = attributes[key] { result[key] = value }
            }
            for part in (attributes["style"] ?? "").split(separator: ";") {
                let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1].trimmingCharacters(in: .whitespaces) }
            }
            return result
        }

        private func parsePath(_ value: String) -> VectorPath? {
            let tokens = value.replacingOccurrences(of: ",", with: " ").split { $0 == " " || $0 == "\n" }.map(String.init)
            var index = 0, commands: [PathCommand] = [], command = ""
            func next() -> CGFloat? { guard index < tokens.count, let value = Double(tokens[index]) else { return nil }; index += 1; return CGFloat(value) }
            while index < tokens.count {
                if tokens[index].first?.isLetter == true { command = tokens[index]; index += 1 }
                switch command.uppercased() {
                case "M", "L":
                    guard let x = next(), let y = next() else { return nil }
                    commands.append(command.uppercased() == "M" ? .move(to: CGPoint(x: x, y: y)) : .line(to: CGPoint(x: x, y: y)))
                case "C":
                    guard let x1 = next(), let y1 = next(), let x2 = next(), let y2 = next(), let x = next(), let y = next() else { return nil }
                    commands.append(.cubic(control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2), to: CGPoint(x: x, y: y)))
                case "Z": commands.append(.close); command = ""
                default: return nil
                }
            }
            return commands.isEmpty ? nil : VectorPath(commands: commands)
        }

        private func pathBounds(_ path: VectorPath) -> CGRect {
            let points = path.commands.flatMap { command -> [CGPoint] in
                switch command { case .move(let p), .line(let p): [p]; case .cubic(let a, let b, let p): [a, b, p]; case .close: [] }
            }
            return points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -1, dy: -1)
        }

        private func number(_ value: String?) -> CGFloat? { value.flatMap { CGFloat(Double($0.filter { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0) } }
        private func rectangle(_ value: String?) -> CGRect? {
            guard let value else { return nil }
            let values = value.split { $0 == "," || $0 == " " }.compactMap { Double($0) }
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        private func color(_ value: String?) -> RGBAColor? {
            guard let value, value.hasPrefix("#"), value.count == 7 else { return value == "none" ? nil : .black }
            let raw = String(value.dropFirst())
            guard let rgb = Int(raw, radix: 16) else { return nil }
            return RGBAColor(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
        }
    }
}

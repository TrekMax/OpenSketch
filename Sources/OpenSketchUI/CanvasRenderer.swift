import AppKit
import OpenSketchCore

@MainActor enum CanvasRenderer {
    struct SelectionGeometry {
        let transform: CGAffineTransform
        let localBounds: CGRect
        let clips: [CGPath]
        var visibleBounds: CGRect { clips.reduce(localBounds.applying(transform)) { $0.intersection($1.boundingBoxOfPath) } }
    }
    static func localBounds(_ node: DesignNode) -> CGRect {
        let path = node.kind == .path ? SceneGeometry.cgPath(for: node.path) : CGPath(rect: CGRect(origin: .zero, size: node.frame.size), transform: nil)
        var bounds = path.boundingBoxOfPath
        if node.style.stroke != nil, node.style.strokeWidth > 0 { bounds = bounds.union(path.copy(strokingWithWidth: node.style.strokeWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10).boundingBoxOfPath) }
        return bounds
    }
    static func selectionGeometry(id: UUID, page: DesignPage) -> SelectionGeometry? {
        func visit(_ nodes: [DesignNode], parent: CGAffineTransform, clips: [CGPath]) -> SelectionGeometry? {
            for node in nodes where node.isVisible {
                var world = SceneGeometry.localTransform(for: node).concatenating(parent)
                if node.id == id { return SelectionGeometry(transform: world, localBounds: localBounds(node), clips: clips) }
                var nextClips = clips
                if node.kind == .frame && node.clipsContent { nextClips.append(CGPath(rect: CGRect(origin: .zero, size: node.frame.size), transform: &world)) }
                if let found = visit(node.children, parent: world, clips: nextClips) { return found }
            }
            return nil
        }
        return visit(page.nodes, parent: .identity, clips: [])
    }
    static func draw(page: DesignPage, in context: CGContext) { for node in page.nodes { draw(node, in: context) } }
    static func draw(_ node: DesignNode, in c: CGContext) {
        guard node.isVisible else { return }
        c.saveGState(); defer { c.restoreGState() }
        c.concatenate(SceneGeometry.localTransform(for: node)); c.setAlpha(node.style.opacity)
        c.beginTransparencyLayer(auxiliaryInfo: nil); defer { c.endTransparencyLayer() }
        let rect = CGRect(origin: .zero, size: node.frame.size)
        let path: CGPath = switch node.kind {
        case .ellipse: CGPath(ellipseIn: rect, transform: nil)
        case .path: SceneGeometry.cgPath(for: node.path)
        default: CGPath(roundedRect: rect, cornerWidth: min(node.style.cornerRadius, rect.width/2), cornerHeight: min(node.style.cornerRadius, rect.height/2), transform: nil)
        }
        if node.kind == .text { TextLayout.draw(node) }
        else {
            if let fill = node.style.fill { c.setFillColor(fill.nsColor.cgColor); c.addPath(path); c.fillPath() }
            if let stroke = node.style.stroke, node.style.strokeWidth > 0 { c.setStrokeColor(stroke.nsColor.cgColor); c.setLineWidth(node.style.strokeWidth); c.setLineCap(.butt); c.setLineJoin(.miter); c.setMiterLimit(10); c.addPath(path); c.strokePath() }
        }
        if node.kind == .frame && node.clipsContent { c.clip(to: rect) }
        for child in node.children { draw(child, in: c) }
    }
    static func bounds(page: DesignPage) -> CGRect {
        var result = CGRect.null
        func visit(_ nodes: [DesignNode], parent: CGAffineTransform, clip: CGRect?) {
            for n in nodes where n.isVisible {
                let world = SceneGeometry.localTransform(for: n).concatenating(parent)
                var b = localBounds(n).applying(world)
                if let clip { b = b.intersection(clip) }; result = result.union(b)
                let childClip = n.kind == .frame && n.clipsContent ? CGRect(origin: .zero, size: n.frame.size).applying(world).intersection(clip ?? .infinite) : clip
                visit(n.children, parent: world, clip: childClip)
            }
        }
        visit(page.nodes, parent: .identity, clip: nil)
        return result.isNull || result.isEmpty ? CGRect(origin: .zero, size: page.size) : result.integral
    }
}

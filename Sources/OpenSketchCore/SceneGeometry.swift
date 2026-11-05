import Foundation
import CoreGraphics

public enum SceneGeometry {
    /// Maps node-local coordinates (0...width, 0...height) into its parent.
    public static func localTransform(for node: DesignNode) -> CGAffineTransform {
        let radians = node.rotation * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        let cx = node.frame.width / 2, cy = node.frame.height / 2
        return CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine,
            tx: node.frame.origin.x + cx - cosine * cx + sine * cy,
            ty: node.frame.origin.y + cy - sine * cx - cosine * cy)
    }

    public static func worldTransform(id: UUID, in page: DesignPage) -> CGAffineTransform? {
        func find(in nodes: [DesignNode], parent: CGAffineTransform) -> CGAffineTransform? {
            for node in nodes {
                let world = localTransform(for: node).concatenating(parent)
                if node.id == id { return world }
                if let found = find(in: node.children, parent: world) { return found }
            }
            return nil
        }
        return find(in: page.nodes, parent: .identity)
    }

    /// Topmost subtree wins; its deepest eligible child wins over its parent.
    /// Hidden or locked ancestors block their entire subtrees. Only frames clip.
    public static func hitTest(_ point: CGPoint, in page: DesignPage) -> UUID? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        func hit(in nodes: [DesignNode], parentPoint: CGPoint) -> UUID? {
            for node in nodes.reversed() where node.isVisible && !node.isLocked {
                let local = parentPoint.applying(localTransform(for: node).inverted())
                let bounds = CGRect(origin: .zero, size: node.frame.size)
                if node.kind == .frame && node.clipsContent && !bounds.contains(local) { continue }
                if let child = hit(in: node.children, parentPoint: local) { return child }
                if node.kind != .path && !bounds.contains(local) { continue }
                let contains: Bool
                switch node.kind {
                case .ellipse:
                    guard bounds.width > 0, bounds.height > 0 else { continue }
                    let dx = (local.x - bounds.midX) / (bounds.width / 2)
                    let dy = (local.y - bounds.midY) / (bounds.height / 2)
                    contains = dx * dx + dy * dy <= 1
                case .rectangle:
                    let radius = min(node.style.cornerRadius, min(bounds.width, bounds.height) / 2)
                    contains = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius,
                                      transform: nil).contains(local)
                case .path:
                    let path = cgPath(for: node.path)
                    let fillHit = node.style.fill != nil && path.contains(local)
                    let strokeHit = node.style.stroke != nil && node.style.strokeWidth > 0 &&
                        path.copy(strokingWithWidth: node.style.strokeWidth, lineCap: .butt,
                                  lineJoin: .miter, miterLimit: 10).contains(local)
                    contains = fillHit || strokeHit
                default: contains = true
                }
                if contains { return node.id }
            }
            return nil
        }
        return hit(in: page.nodes, parentPoint: point)
    }

    /// Depth-first drawing order: parent, then children; each array is bottom-to-top.
    /// Includes invisible/locked nodes so callers can build complete layer lists.
    public static func traversal(in page: DesignPage) -> [DesignNode] {
        var result: [DesignNode] = []
        func visit(_ nodes: [DesignNode]) {
            for node in nodes { result.append(node); visit(node.children) }
        }
        visit(page.nodes)
        return result
    }

    public static func cgPath(for path: VectorPath) -> CGPath {
        let result = CGMutablePath()
        for command in path.commands {
            switch command {
            case .move(let point): result.move(to: point)
            case .line(let point): result.addLine(to: point)
            case .cubic(let first, let second, let point):
                result.addCurve(to: point, control1: first, control2: second)
            case .close: result.closeSubpath()
            }
        }
        return result
    }
}

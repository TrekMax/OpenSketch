import AppKit
import OpenSketchCore

enum ExportFormat: String, CaseIterable { case png, pdf }
enum ExportScope: String, CaseIterable { case selection, page }

struct ExportOptions: Equatable {
    var format: ExportFormat = .png
    var scope: ExportScope = .selection
    var scale: Double = 1

    func resolvedScope(selection: Set<UUID>) -> ExportScope {
        scope == .selection && selection.isEmpty ? .page : scope
    }
}

/// A value snapshot: exporting never changes the editable page or its selection.
@MainActor struct ExportSnapshot {
    let page: DesignPage
    let bounds: CGRect
    let name: String

    static func make(page: DesignPage, selection: Set<UUID>, scope: ExportScope) throws -> ExportSnapshot {
        if scope == .page {
            return ExportSnapshot(page: page, bounds: CanvasRenderer.bounds(page: page), name: page.name)
        }
        let allNodes = SceneGeometry.traversal(in: page)
        guard !selection.isEmpty, selection.isSubset(of: Set(allNodes.map(\.id))) else {
            throw EditorError.invalid("请选择当前页面中的有效图层。")
        }

        var roots: [DesignNode] = []
        func selectedRoots(_ nodes: [DesignNode], ancestorSelected: Bool, visible: Bool) {
            for node in nodes {
                let visible = visible && node.isVisible
                let selected = selection.contains(node.id)
                if selected && !ancestorSelected && visible { roots.append(node) }
                selectedRoots(node.children, ancestorSelected: ancestorSelected || selected, visible: visible)
            }
        }
        selectedRoots(page.nodes, ancestorSelected: false, visible: true)

        var source = page
        var artboardBounds: CGRect?
        // A single artboard is its own export surface, independent of page placement.
        if roots.count == 1, var artboard = roots.first, artboard.kind == .frame {
            artboard.frame.origin = .zero
            artboard.rotation = 0
            artboard.clipsContent = true
            artboardBounds = CGRect(origin: .zero, size: artboard.frame.size)
            source.nodes = [artboard]
        }

        var bounds = CGRect.null
        func prune(_ nodes: [DesignNode], parent: CGAffineTransform, clips: [CGPath], selected: Bool) -> [DesignNode] {
            nodes.compactMap { node in
                guard node.isVisible, node.style.opacity > 0 else { return nil }
                var world = SceneGeometry.localTransform(for: node).concatenating(parent)
                let included = selected || selection.contains(node.id)
                if included {
                    for path in paintedPaths(node) {
                        guard var visiblePath = path.copy(using: &world) else { continue }
                        for clip in clips { visiblePath = visiblePath.intersection(clip) }
                        let visibleBounds = visiblePath.boundingBoxOfPath
                        if !visibleBounds.isNull && !visibleBounds.isEmpty { bounds = bounds.union(visibleBounds) }
                    }
                }
                var childClips = clips
                if node.kind == .frame && node.clipsContent {
                    childClips.append(CGPath(rect: CGRect(origin: .zero, size: node.frame.size), transform: &world))
                }
                let children = prune(node.children, parent: world, clips: childClips, selected: included)
                guard included || !children.isEmpty else { return nil }
                var result = node
                if !included {
                    // Structural ancestors retain transforms, clip and group opacity only.
                    result.style.fill = nil
                    result.style.stroke = nil
                }
                result.children = included ? node.children : children
                return result
            }
        }
        var result = page
        result.nodes = prune(source.nodes, parent: .identity, clips: [], selected: false)
        guard !bounds.isNull, !bounds.isEmpty else { throw invisibleSelection() }
        return ExportSnapshot(page: result, bounds: artboardBounds ?? bounds, name: roots.count == 1 ? roots[0].name : L10n.text("选中图层"))
    }

    private static func invisibleSelection() -> EditorError {
        .invalid("所选图层没有可见内容，可能已隐藏或被完全裁剪。")
    }

    /// Bounds follow painted geometry; unpainted group frames are structural only.
    private static func paintedPaths(_ node: DesignNode) -> [CGPath] {
        let rect = CGRect(origin: .zero, size: node.frame.size)
        let radius = min(node.style.cornerRadius, min(rect.width, rect.height) / 2)
        let path: CGPath = switch node.kind {
        case .ellipse: CGPath(ellipseIn: rect, transform: nil)
        case .path: SceneGeometry.cgPath(for: node.path)
        // TextLayout draws into a rectangular text box without applying corner radius.
        case .text: CGPath(rect: rect, transform: nil)
        default: CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        var paths: [CGPath] = []
        if ((node.style.fill?.alpha ?? 0) > 0 || node.style.linearGradient != nil), node.kind != .text || !node.text.isEmpty { paths.append(path) }
        if node.kind != .text, let stroke = node.style.stroke, stroke.alpha > 0, node.style.strokeWidth > 0 {
            paths.append(path.copy(strokingWithWidth: node.style.strokeWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
        }
        return paths
    }
}

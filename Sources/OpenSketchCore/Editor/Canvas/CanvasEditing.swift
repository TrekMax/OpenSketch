import Foundation
import CoreGraphics

public struct SnapGuide: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public init(start: CGPoint, end: CGPoint) { self.start = start; self.end = end }
}

public struct MovementSnap: Equatable, Sendable {
    public var translation: CGSize
    public var guides: [SnapGuide]
    public init(translation: CGSize, guides: [SnapGuide]) { self.translation = translation; self.guides = guides }
}

public enum CanvasEditing {
    private struct Entry {
        let node: DesignNode
        let ancestors: [UUID]
        let parentTransform: CGAffineTransform
        let isEditable: Bool
        let isVisible: Bool
        let hasValidGeometry: Bool
        let fullBounds: CGRect?
        let visibleBounds: CGRect?
        var subtreeEnd: Int
    }

    private struct AxisMatch {
        let correction: CGFloat
        let coordinate: CGFloat
        let reference: CGRect
    }

    /// Selects units fully contained by the page-axis bounds of their visible frame geometry.
    public static func marqueeSelection(in page: DesignPage, rect: CGRect) -> Set<UUID> {
        guard !rect.isInfinite, !rect.isNull, finite(rect) else { return [] }
        let marquee = rect.standardized
        guard marquee.width > 0, marquee.height > 0, finite(marquee) else { return [] }
        let entries = scene(in: page)
        var selection = Set<UUID>()
        var index = 0
        while index < entries.count {
            let entry = entries[index]
            guard entry.isEditable else { index = entry.subtreeEnd; continue }
            if let bounds = entry.visibleBounds, contains(marquee, bounds) {
                selection.insert(entry.node.id)
                index = entry.subtreeEnd
            } else if entry.node.kind == .group {
                index = entry.subtreeEnd
            } else {
                index += 1
            }
        }
        return selection
    }

    /// Computes each axis independently from the original gesture translation.
    public static func snapMovement(in page: DesignPage, selection: Set<UUID>, translation: CGSize,
                                    tolerance: CGFloat) -> MovementSnap {
        let unchanged = MovementSnap(translation: translation, guides: [])
        guard translation.width.isFinite, translation.height.isFinite, tolerance.isFinite, tolerance >= 0 else {
            return unchanged
        }
        let entries = scene(in: page)
        guard let roots = try? selectedRoots(selection, entries: entries) else { return unchanged }
        let rootBounds = roots.compactMap(\.fullBounds)
        guard rootBounds.count == roots.count, let first = rootBounds.first else { return unchanged }
        let bounds = rootBounds.dropFirst().reduce(first) { $0.union($1) }
        let moved = bounds.offsetBy(dx: translation.width, dy: translation.height)
        guard finite(moved) else { return unchanged }
        let rootIDs = Set(roots.map { $0.node.id })
        let ancestorIDs = Set(roots.flatMap(\.ancestors))
        var horizontal: AxisMatch?
        var vertical: AxisMatch?
        // Strict replacement retains drawing order, reference-anchor order and
        // moving-anchor order when absolute corrections tie.
        for entry in entries where entry.isVisible && !rootIDs.contains(entry.node.id) &&
            !ancestorIDs.contains(entry.node.id) && rootIDs.isDisjoint(with: entry.ancestors) {
            guard let reference = entry.visibleBounds else { continue }
            match(moving: [moved.minX, moved.midX, moved.maxX],
                  reference: [reference.minX, reference.midX, reference.maxX],
                  bounds: reference, tolerance: tolerance, best: &horizontal)
            match(moving: [moved.minY, moved.midY, moved.maxY],
                  reference: [reference.minY, reference.midY, reference.maxY],
                  bounds: reference, tolerance: tolerance, best: &vertical)
        }
        let result = CGSize(width: translation.width + (horizontal?.correction ?? 0),
                            height: translation.height + (vertical?.correction ?? 0))
        let corrected = bounds.offsetBy(dx: result.width, dy: result.height)
        guard result.width.isFinite, result.height.isFinite, finite(corrected) else { return unchanged }
        var guides: [SnapGuide] = []
        if let horizontal {
            guides.append(SnapGuide(start: CGPoint(x: horizontal.coordinate, y: min(corrected.minY, horizontal.reference.minY)),
                                    end: CGPoint(x: horizontal.coordinate, y: max(corrected.maxY, horizontal.reference.maxY))))
        }
        if let vertical {
            guides.append(SnapGuide(start: CGPoint(x: min(corrected.minX, vertical.reference.minX), y: vertical.coordinate),
                                    end: CGPoint(x: max(corrected.maxX, vertical.reference.maxX), y: vertical.coordinate)))
        }
        return MovementSnap(translation: result, guides: guides)
    }

    /// Validates every root before applying changes; does not encode the document.
    public static func translating(_ document: DesignDocument, pageID: UUID, selection: Set<UUID>,
                                   by delta: CGSize) throws -> DesignDocument {
        guard !selection.isEmpty else { return document }
        guard let pageIndex = document.pages.firstIndex(where: { $0.id == pageID }) else {
            throw LayerEditError.invalidSelection
        }
        let roots = try selectedRoots(selection, entries: scene(in: document.pages[pageIndex]))
        guard delta.width.isFinite, delta.height.isFinite else { throw LayerEditError.invalidGeometry }
        guard delta != .zero else { return document }
        var origins: [UUID: CGPoint] = [:]
        for root in roots {
            let inverse = root.parentTransform.inverted()
            // A vector uses only the inverse linear transform, never its translation.
            let local = CGPoint(x: inverse.a * delta.width + inverse.c * delta.height,
                                y: inverse.b * delta.width + inverse.d * delta.height)
            let origin = CGPoint(x: root.node.frame.origin.x + local.x, y: root.node.frame.origin.y + local.y)
            guard validCoordinate(origin.x), validCoordinate(origin.y) else { throw LayerEditError.invalidGeometry }
            origins[root.node.id] = origin
        }
        var candidate = document
        func update(_ nodes: inout [DesignNode]) {
            for index in nodes.indices {
                if let origin = origins[nodes[index].id] {
                    nodes[index].frame.origin = origin
                } else if !nodes[index].children.isEmpty {
                    update(&nodes[index].children)
                }
            }
        }
        update(&candidate.pages[pageIndex].nodes)
        return candidate
    }

    private static func selectedRoots(_ selection: Set<UUID>, entries: [Entry]) throws -> [Entry] {
        guard !selection.isEmpty, selection.isSubset(of: Set(entries.map { $0.node.id })) else {
            throw LayerEditError.invalidSelection
        }
        let roots = entries.filter { selection.contains($0.node.id) && selection.isDisjoint(with: $0.ancestors) }
        guard roots.allSatisfy(\.isEditable) else { throw LayerEditError.lockedOrHidden }
        guard roots.allSatisfy(\.hasValidGeometry) else { throw LayerEditError.invalidGeometry }
        return roots
    }

    /// One depth-first traversal computes world transforms, eligibility and both bounds.
    private static func scene(in page: DesignPage) -> [Entry] {
        var entries: [Entry] = []
        func visit(_ nodes: [DesignNode], ancestors: [UUID], parent: CGAffineTransform,
                   visible: Bool, editable: Bool, valid: Bool, clips: [[CGPoint]]) {
            for node in nodes {
                let world = SceneGeometry.localTransform(for: node).concatenating(parent)
                let validGeometry = valid && validFrame(node.frame) && node.rotation.isFinite &&
                    (-1e9...1e9).contains(node.rotation) &&
                    [world.a, world.b, world.c, world.d, world.tx, world.ty].allSatisfy(\.isFinite)
                let isVisible = visible && node.isVisible
                let isEditable = editable && node.isVisible && !node.isLocked
                let polygon = validGeometry ? corners(size: node.frame.size, transform: world) : []
                let clipped = clips.reduce(polygon) { clip($0, to: $1) }
                let index = entries.count
                entries.append(Entry(node: node, ancestors: ancestors, parentTransform: parent,
                                     isEditable: isEditable, isVisible: isVisible, hasValidGeometry: validGeometry,
                                     fullBounds: polygonBounds(polygon), visibleBounds: isVisible ? polygonBounds(clipped) : nil,
                                     subtreeEnd: index + 1))
                let childClips = node.kind == .frame && node.clipsContent ? clips + [polygon] : clips
                visit(node.children, ancestors: ancestors + [node.id], parent: world,
                      visible: isVisible, editable: isEditable, valid: validGeometry, clips: childClips)
                entries[index].subtreeEnd = entries.count
            }
        }
        visit(page.nodes, ancestors: [], parent: .identity, visible: true, editable: true, valid: true, clips: [])
        return entries
    }

    private static func match(moving: [CGFloat], reference: [CGFloat], bounds: CGRect,
                              tolerance: CGFloat, best: inout AxisMatch?) {
        for coordinate in reference {
            for anchor in moving {
                let correction = coordinate - anchor
                guard correction.isFinite, abs(correction) <= tolerance else { continue }
                if let current = best, abs(correction) >= abs(current.correction) { continue }
                best = AxisMatch(correction: correction, coordinate: coordinate, reference: bounds)
            }
        }
    }

    private static func corners(size: CGSize, transform: CGAffineTransform) -> [CGPoint] {
        [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height),
         CGPoint(x: 0, y: size.height)].map { $0.applying(transform) }
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ point: CGPoint) -> CGFloat {
        (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
    }

    private static func area(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        // Relative coordinates keep small shapes far from the origin numerically useful.
        return (1..<(polygon.count - 1)).reduce(CGFloat.zero) {
            $0 + cross(polygon[0], polygon[$1], polygon[$1 + 1])
        }
    }

    /// Sutherland–Hodgman clipping against the actual convex ancestor frame.
    private static func clip(_ polygon: [CGPoint], to boundary: [CGPoint]) -> [CGPoint] {
        let signedArea = area(boundary)
        guard signedArea.isFinite, signedArea != 0, !polygon.isEmpty else { return [] }
        let orientation: CGFloat = signedArea > 0 ? 1 : -1
        var result = polygon
        for index in boundary.indices {
            let a = boundary[index], b = boundary[(index + 1) % boundary.count]
            let input = result
            result = []
            guard var previous = input.last else { break }
            var previousDistance = orientation * cross(a, b, previous)
            for current in input {
                let distance = orientation * cross(a, b, current)
                if (distance >= 0) != (previousDistance >= 0) {
                    let fraction = previousDistance / (previousDistance - distance)
                    result.append(CGPoint(x: previous.x + fraction * (current.x - previous.x),
                                          y: previous.y + fraction * (current.y - previous.y)))
                }
                if distance >= 0 { result.append(current) }
                previous = current
                previousDistance = distance
            }
        }
        return result
    }

    private static func polygonBounds(_ polygon: [CGPoint]) -> CGRect? {
        let signedArea = area(polygon)
        guard let first = polygon.first, polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              signedArea.isFinite, signedArea != 0 else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in polygon.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return finite(bounds) && bounds.width > 0 && bounds.height > 0 ? bounds : nil
    }

    private static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.minX <= inner.minX && outer.maxX >= inner.maxX && outer.minY <= inner.minY && outer.maxY >= inner.maxY
    }

    private static func finite(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, rect.minX, rect.maxX, rect.minY, rect.maxY].allSatisfy(\.isFinite)
    }

    private static func validCoordinate(_ value: CGFloat) -> Bool {
        value.isFinite && (-1e9...1e9).contains(value)
    }

    private static func validFrame(_ rect: CGRect) -> Bool {
        validCoordinate(rect.origin.x) && validCoordinate(rect.origin.y) &&
            [rect.size.width, rect.size.height].allSatisfy { $0.isFinite && (0...1e7).contains($0) }
    }
}

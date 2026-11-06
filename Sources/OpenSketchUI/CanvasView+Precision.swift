import AppKit
import OpenSketchCore

enum PrecisionInput {
    case marquee(origin: CGPoint, rect: CGRect?, initial: Set<UUID>, extending: Bool)
    case nudge(keys: Set<UInt16>, delta: CGSize)
}

extension CanvasView {
    func beginMarquee(at point: CGPoint, extending: Bool) {
        precision = .marquee(origin: point, rect: nil, initial: session.selection, extending: extending)
        if !extending { session.selection = [] }
    }

    @discardableResult func updateMarquee(to point: CGPoint) -> Bool {
        guard case let .marquee(origin, _, initial, extending) = precision else { return false }
        guard hypot(point.x - origin.x, point.y - origin.y) * session.zoom >= 3 else {
            session.selection = extending ? initial : []
            precision = .marquee(origin: origin, rect: nil, initial: initial, extending: extending)
            needsDisplay = true
            return true
        }
        let rect = CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                          width: abs(point.x - origin.x), height: abs(point.y - origin.y))
        var selected = CanvasEditing.marqueeSelection(in: session.page, rect: rect)
        if extending { selected.formUnion(initial) }
        session.selection = Set(selected.filter { id in
            var parent = session.document.parentID(of: id)
            while let ancestor = parent {
                if selected.contains(ancestor) { return false }
                parent = session.document.parentID(of: ancestor)
            }
            return true
        })
        precision = .marquee(origin: origin, rect: rect, initial: initial, extending: extending)
        needsDisplay = true
        return true
    }

    func finishPrecision(cancel: Bool = false) {
        let active = precision
        precision = nil; guides = []
        switch active {
        case let .marquee(_, _, initial, _): if cancel { session.selection = initial }
        case .nudge: if cancel { session.cancelGesture() } else { session.commitGesture() }
        case nil: break
        }
        needsDisplay = true
    }

    func nudge(with event: NSEvent) -> Bool {
        guard (123...126).contains(event.keyCode),
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        guard !session.selection.isEmpty else { return true }
        if case .nudge = precision {} else {
            session.finishInput?()
            session.beginGesture()
            precision = .nudge(keys: [], delta: .zero)
        }
        guard case var .nudge(keys, delta) = precision else { return true }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: delta.width -= step
        case 124: delta.width += step
        case 125: delta.height += step
        default: delta.height -= step
        }
        keys.insert(event.keyCode)
        precision = .nudge(keys: keys, delta: delta)
        session.moveSelection(by: delta)
        needsDisplay = true
        return true
    }

    func releaseNudge(_ code: UInt16) -> Bool {
        guard case let .nudge(held, delta) = precision, held.contains(code) else { return false }
        var keys = held
        keys.remove(code)
        precision = .nudge(keys: keys, delta: delta)
        if keys.isEmpty { finishPrecision() }
        return true
    }

    func moveSnapping(to point: CGPoint, from origin: CGPoint, event: NSEvent) {
        guard let page = session.gestureStart?.pages.first(where: { $0.id == session.pageID }) else { return }
        let raw = CGSize(width: point.x - origin.x, height: point.y - origin.y)
        let result = session.snapping && !event.modifierFlags.contains(.control)
            ? CanvasEditing.snapMovement(in: page, selection: session.selection, translation: raw, tolerance: 6 / session.zoom)
            : MovementSnap(translation: raw, guides: [])
        guides = session.moveSelection(by: result.translation) ? result.guides : []
    }

    func drawPrecision(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(EditorPalette.accent.cgColor)
        context.setLineWidth(1 / session.zoom)
        if case let .marquee(_, rect?, _, _) = precision {
            context.setFillColor(EditorPalette.accent.withAlphaComponent(0.12).cgColor)
            context.fill(rect); context.stroke(rect)
        }
        context.setLineDash(phase: 0, lengths: [4 / session.zoom, 3 / session.zoom])
        for guide in guides {
            context.move(to: guide.start); context.addLine(to: guide.end); context.strokePath()
        }
        context.restoreGState()
    }
}

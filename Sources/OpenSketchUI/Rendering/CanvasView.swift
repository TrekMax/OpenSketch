import AppKit
import SwiftUI
import OpenSketchCore

struct CanvasHost: NSViewRepresentable {
    @Environment(\.locale) private var locale
    var session: EditorSession
    func makeNSView(context: Context) -> CanvasView { CanvasView(session: session) }
    func updateNSView(_ view: CanvasView, context: Context) { _ = locale; _ = session.document; _ = session.selection; _ = session.zoom; _ = session.pan; _ = session.grid; _ = session.snapping; _ = session.needsInitialFit; view.refreshLanguage(); view.needsDisplay = true; view.needsLayout = true }
}
@MainActor final class InlineTextView: NSTextView {
    var commitEditing: (() -> Void)?
    private func commitsEditing(_ event: NSEvent) -> Bool {
        !hasMarkedText() && event.modifierFlags.contains(.command) && (event.keyCode == 36 || event.keyCode == 76)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if commitsEditing(event) { commitEditing?(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if commitsEditing(event) { commitEditing?(); return }
        super.keyDown(with: event)
    }
}
@MainActor final class CanvasView: NSView, NSTextViewDelegate {
    let session: EditorSession
    var start: CGPoint?
    var creation: UUID?
    private var creationTool: EditorTool?
    private var textCreationTool: EditorTool?
    var resizing: UUID?
    var editor: NSTextView?
    var textID: UUID?
    var precision: PrecisionInput?
    var guides: [SnapGuide] = []
    var containerDrag: ContainerDrag?
    private var penPoints: [CGPoint] = []
    private var penDragStart: CGPoint?
    private var penSegmentIndex: Int?
    private var pathEditingID: UUID?
    private var pathEditingPoint: PathPointReference?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(session: EditorSession) {
        self.session = session; super.init(frame: .zero)
        // Keep artwork, selection overlays and the inline editor inside the viewport.
        clipsToBounds = true
        setAccessibilityIdentifier("editor.canvas"); setAccessibilityLabel(L10n.text("设计画布"))
        session.finishInput = { [weak self] in
            self?.finishText(commit: true)
            self?.finishPrecision()
            self?.finishPathEditing(commit: true)
            self?.finishGesture()
        }
        session.canUndoPendingNudge = { [weak self] in
            guard let self, case .nudge = self.precision else { return false }
            // Menu validation must stay pure and must not commit mouse or text input.
            var candidate = self.session.history
            candidate.commit(document: self.session.document)
            return candidate.canUndo
        }
        session.fitCanvas = { [weak self] in self?.fit() }
        session.setCanvasZoom = { [weak self] value in
            guard let self else { return }
            self.zoom(to: value, anchor: CGPoint(x: self.bounds.midX, y: self.bounds.midY))
        }
        session.zoomCanvas = { [weak self] factor in
            guard let self else { return }
            self.finishText(commit: true)
            self.zoom(to: self.session.zoom * factor, anchor: CGPoint(x: self.bounds.midX, y: self.bounds.midY))
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func refreshLanguage() {
        setAccessibilityLabel(L10n.text("设计画布"))
        editor?.setAccessibilityLabel(L10n.text("编辑文字，Command Return 完成，Escape 取消"))
    }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size, start != nil, creation == nil, resizing == nil, precision == nil {
            finishGesture()
        }
        super.setFrameSize(newSize)
    }
    override func layout() {
        super.layout()
        // A new document's representable is created before it has a viewport.
        guard session.needsInitialFit, bounds.width > 0, bounds.height > 0 else { return }
        session.needsInitialFit = false
        fit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(windowInputEnded(_:)),
                                                       name: name, object: window)
            }
        }
        if window == nil { session.finishInput?() }
    }
    @objc private func windowInputEnded(_ notification: Notification) { session.finishInput?() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
    func world(_ event: NSEvent) -> CGPoint { let p = convert(event.locationInWindow, from: nil); return CGPoint(x: (p.x-session.pan.x)/session.zoom, y: (p.y-session.pan.y)/session.zoom) }
    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        EditorPalette.canvas.setFill(); bounds.fill()
        c.saveGState(); c.translateBy(x: session.pan.x, y: session.pan.y); c.scaleBy(x: session.zoom, y: session.zoom)
        if session.grid && session.zoom >= 0.25 {
            c.setFillColor(EditorPalette.grid.cgColor)
            let step: CGFloat = 20
            let left = floor(-session.pan.x/session.zoom/step)*step, top = floor(-session.pan.y/session.zoom/step)*step
            for x in stride(from: left, through: left+bounds.width/session.zoom+step, by: step) { for y in stride(from: top, through: top+bounds.height/session.zoom+step, by: step) { c.fill(CGRect(x: x, y: y, width: 1/session.zoom, height: 1/session.zoom)) } }
        }
        CanvasRenderer.draw(page: session.page, in: c)
        for id in session.selection {
            guard let n = session.document.node(id: id), let geometry = CanvasRenderer.selectionGeometry(id: id, page: session.page) else { continue }
            c.saveGState(); for clip in geometry.clips { c.addPath(clip); c.clip() }; c.concatenate(geometry.transform); c.setStrokeColor(EditorPalette.accent.cgColor); c.setLineWidth(1.5/session.zoom)
            let rect = CGRect(origin: .zero, size: n.frame.size); c.stroke(geometry.localBounds)
            if n.kind != .group && n.rotation == 0 && session.editable(id) { let size = 8/session.zoom; c.setFillColor(NSColor.white.cgColor); let handle = CGRect(x: rect.maxX-size/2, y: rect.maxY-size/2, width: size, height: size); c.fill(handle); c.stroke(handle) }
            c.restoreGState()
        }
        drawContainerDrag(in: c)
        drawPrecision(in: c)
        c.restoreGState()
        drawPathEditingOverlay(in: c)
        if session.page.nodes.isEmpty { (L10n.text("开始设计\n选择上方工具，然后在画布中拖动") as NSString).draw(in: CGRect(x: 40, y: 35, width: 340, height: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor]) }
    }
    override func mouseDown(with event: NSEvent) {
        let point = world(event)
        if session.tool == .pen {
            if creationTool == .pen {
                appendPenPoint(point, close: event.clickCount > 1)
                if creationTool == .pen {
                    penDragStart = point
                    penSegmentIndex = penPoints.count > 1 ? penPoints.count - 1 : nil
                }
            } else {
                beginPen(at: point)
            }
            return
        }
        if let id = pathEditingID {
            if let node = session.document.node(id: id),
               let transform = SceneGeometry.worldTransform(id: id, in: session.page),
               let reference = nearestPathPoint(in: node, to: point, transform: transform) {
                pathEditingPoint = reference
                session.beginGesture()
                return
            }
            finishPathEditing(commit: true)
        }
        session.finishInput?(); window?.makeFirstResponder(self)
        let p = point; start = p; creation = nil; creationTool = nil; resizing = nil
        if session.tool == .select {
            if let n = session.selected, n.kind != .group, n.rotation == 0, session.editable(n.id), let transform = SceneGeometry.worldTransform(id: n.id, in: session.page) {
                let corner = CGPoint(x: n.frame.width, y: n.frame.height).applying(transform)
                if hypot(corner.x-p.x, corner.y-p.y) < 10/session.zoom { resizing = n.id; session.beginGesture(); return }
            }
            if let hit = SceneGeometry.hitTest(p, in: session.page) {
                let target = session.canvasSelectionTarget(hit, direct: event.modifierFlags.contains(.option))
                if event.modifierFlags.contains(.shift) { if session.selection.contains(target) { session.selection.remove(target) } else { session.selection.insert(target) } }
                else if !session.selection.contains(target) { session.selection = [target] }
                if event.clickCount == 2, session.document.node(id: hit)?.kind == .path {
                    beginPathEditing(hit, at: p)
                    return
                }
                if event.clickCount == 2, session.document.node(id: hit)?.kind == .text {
                    session.selection = [hit]
                    start = nil; beginText(hit); return
                }
                if let selected = session.selected, selected.rotation != 0 { session.message = "旋转图层请通过检查器修改尺寸" }
            } else {
                beginMarquee(at: p, extending: event.modifierFlags.contains(.shift))
                start = nil; needsDisplay = true; return
            }
            session.beginGesture()
        } else {
            session.beginGesture()
            let kind = NodeKind(rawValue: session.tool.rawValue) ?? .rectangle
            let node = DesignNode(name: session.tool.title, kind: kind, frame: CGRect(x: p.x, y: p.y, width: kind == .text ? 240 : 120, height: kind == .text ? 80 : 100), text: kind == .text ? L10n.text("输入文字") : "")
            if session.create(node) { creation = node.id; creationTool = session.tool } else { session.cancelGesture(); start = nil }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let p = world(event)
        if creationTool == .pen, let id = creation, let start = penDragStart,
           let segment = penSegmentIndex, let node = session.document.node(id: id),
           let transform = SceneGeometry.worldTransform(id: id, in: session.page),
           let end = pathPoint(PathPointReference(commandIndex: segment), in: node) {
            let inverse = transform.inverted()
            let localStart = start.applying(inverse)
            let localPoint = p.applying(inverse)
            let dx = localPoint.x - end.x
            let dy = localPoint.y - end.y
            let control1 = localStart
            let control2 = CGPoint(x: end.x - dx, y: end.y - dy)
            if let path = try? PathEditing.replaceLineWithCubic(at: segment, control1: control1,
                                                                  control2: control2, in: node.path) {
                session.document.updateNode(id: id) { $0.path = path }
                needsDisplay = true
            }
            return
        }
        if let id = pathEditingID, let reference = pathEditingPoint,
           let transform = SceneGeometry.worldTransform(id: id, in: session.page),
           let local = try? PathEditing.movePoint(reference, to: p.applying(transform.inverted()), in: session.document.node(id: id)?.path ?? VectorPath()) {
            session.document.updateNode(id: id) { $0.path = local }
            needsDisplay = true
            return
        }
        if updateMarquee(to: p) { return }
        guard let start else { return }
        if let id = creation { session.document.updateNode(id: id) { $0.frame = CGRect(x: min(start.x,p.x), y: min(start.y,p.y), width: max(1,abs(p.x-start.x)), height: max(1,abs(p.y-start.y))) } }
        else if let id = resizing, let n = session.gestureStart?.node(id: id), let transform = SceneGeometry.worldTransform(id: id, in: session.page) {
            let local = p.applying(transform.inverted()); session.document.updateNode(id: id) { $0.frame.size = CGSize(width: max(1, local.x), height: max(1, local.y)); $0.frame.origin = n.frame.origin }
        } else {
            let applied = moveSnapping(to: p, from: start, event: event)
            updateContainerDrag(to: p, from: start, applied: applied)
        }
        needsDisplay = true
    }
    private func finishCreation(tool: EditorTool?) {
        if let tool, session.tool == tool { session.tool = .select }
    }
    func finishGesture(beginTextEditing: Bool = false) {
        let id = creation, tool = creationTool
        if creationTool == .pen {
            if penPoints.count >= 2 { session.commitGesture() }
            else { session.cancelGesture() }
        } else if start != nil {
            session.commitGesture()
        }
        guides = []
        clearContainerDrag()
        start = nil; creation = nil; creationTool = nil; resizing = nil; penPoints = []
        penDragStart = nil; penSegmentIndex = nil
        if beginTextEditing, let id, session.document.node(id: id)?.kind == .text {
            beginText(id)
            if textID == id { textCreationTool = tool; return }
        }
        finishCreation(tool: tool)
    }
    override func mouseUp(with event: NSEvent) {
        if pathEditingPoint != nil {
            finishPathEditing(commit: true)
            needsDisplay = true
            return
        }
        if creationTool == .pen { return }
        finishContainerDrop()
        finishPrecision(); finishGesture(beginTextEditing: true); needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finishText(commit: false)
            finishPrecision(cancel: true)
            if pathEditingID != nil {
                finishPathEditing(commit: false)
                needsDisplay = true
                return
            }
            if creationTool == .pen {
                let tool = creationTool
                session.cancelGesture()
                session.selection = []
                finishCreation(tool: tool)
                creation = nil; creationTool = nil; penPoints = []
                penDragStart = nil; penSegmentIndex = nil
                session.message = "路径至少需要两个节点"
            } else if start != nil {
                session.cancelGesture(); start = nil; creation = nil; resizing = nil
                finishCreation(tool: creationTool); creationTool = nil
            }
            clearContainerDrag()
            guides = []; needsDisplay = true; return
        }
        if creationTool == .pen && (event.keyCode == 36 || event.keyCode == 76) {
            finishPen()
            return
        }
        if nudge(with: event) { return }
        if precision != nil { session.finishInput?() }
        if event.keyCode == 51 || event.keyCode == 117 { session.deleteSelection(); return }
        let tools: [String: EditorTool] = ["v": .select, "f": .frame, "r": .rectangle, "o": .ellipse, "p": .pen, "t": .text]
        if let tool = tools[event.charactersIgnoringModifiers ?? ""] { session.tool = tool } else { super.keyDown(with: event) }
    }

    private func beginPen(at point: CGPoint) {
        session.finishInput?()
        window?.makeFirstResponder(self)
        session.beginGesture()
        penPoints = [point]
        do {
            let style = NodeStyle(fill: nil, stroke: RGBAColor(red: 0.27, green: 0.48, blue: 0.95), strokeWidth: 2)
            let node = try PathEditing.makeNode(name: session.tool.title, points: penPoints, style: style)
            guard session.create(node) else {
                session.cancelGesture(); penPoints = []; penDragStart = nil; penSegmentIndex = nil; return
            }
            creation = node.id
            creationTool = .pen
            session.message = "点击添加路径节点 · Enter 完成 · Escape 取消"
            needsDisplay = true
        } catch {
            session.cancelGesture()
            penPoints = []
            session.message = "无法创建路径"
        }
    }

    private func beginPathEditing(_ id: UUID, at point: CGPoint? = nil) {
        session.finishInput?()
        pathEditingID = id
        session.selection = [id]
        if let point,
           let node = session.document.node(id: id),
           let transform = SceneGeometry.worldTransform(id: id, in: session.page) {
            pathEditingPoint = nearestPathPoint(in: node, to: point, transform: transform)
            if pathEditingPoint != nil { session.beginGesture() }
        } else {
            pathEditingPoint = nil
        }
        session.message = "拖动节点编辑路径 · Escape 退出节点编辑"
        needsDisplay = true
    }

    private func finishPathEditing(commit: Bool) {
        guard pathEditingID != nil else { return }
        if pathEditingPoint != nil {
            if commit { session.commitGesture() } else { session.cancelGesture() }
        }
        pathEditingID = nil
        pathEditingPoint = nil
        needsDisplay = true
    }

    private func pathPoint(_ reference: PathPointReference, in node: DesignNode) -> CGPoint? {
        guard node.path.commands.indices.contains(reference.commandIndex) else { return nil }
        switch (node.path.commands[reference.commandIndex], reference.role) {
        case (.move(let point), .destination), (.line(let point), .destination): return point
        case let (.cubic(control1, _, _), .control1): return control1
        case let (.cubic(_, control2, _), .control2): return control2
        case let (.cubic(_, _, destination), .destination): return destination
        default: return nil
        }
    }

    private func pathPointReferences(in node: DesignNode) -> [PathPointReference] {
        node.path.commands.enumerated().flatMap { index, command in
            switch command {
            case .move, .line: return [PathPointReference(commandIndex: index)]
            case .cubic: return [PathPointReference(commandIndex: index, role: .control1),
                                  PathPointReference(commandIndex: index, role: .control2),
                                  PathPointReference(commandIndex: index)]
            case .close: return []
            }
        }
    }

    private func nearestPathPoint(in node: DesignNode, to worldPoint: CGPoint,
                                  transform: CGAffineTransform) -> PathPointReference? {
        let localPoint = worldPoint.applying(transform.inverted())
        return pathPointReferences(in: node).compactMap { reference -> (PathPointReference, CGFloat)? in
            guard let point = pathPoint(reference, in: node) else { return nil }
            return (reference, hypot(point.x - localPoint.x, point.y - localPoint.y))
        }.filter { $0.1 <= 12 / session.zoom }.min { $0.1 < $1.1 }?.0
    }

    private func drawPathEditingOverlay(in context: CGContext) {
        guard let id = pathEditingID, let node = session.document.node(id: id),
              let transform = SceneGeometry.worldTransform(id: id, in: session.page) else { return }
        context.saveGState()
        context.concatenate(transform)
        let radius = 5 / session.zoom
        for reference in pathPointReferences(in: node) {
            guard let point = pathPoint(reference, in: node) else { continue }
            if reference.role != .destination,
               let destination = pathPoint(PathPointReference(commandIndex: reference.commandIndex), in: node) {
                context.setStrokeColor(EditorPalette.accent.withAlphaComponent(0.55).cgColor)
                context.setLineWidth(1 / session.zoom)
                context.move(to: destination)
                context.addLine(to: point)
                context.strokePath()
            }
            let isControl = reference.role != .destination
            context.setFillColor((isControl ? NSColor.white : EditorPalette.accent).cgColor)
            context.setStrokeColor(EditorPalette.accent.cgColor)
            context.setLineWidth(1 / session.zoom)
            let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: circle)
            context.strokeEllipse(in: circle)
        }
        context.restoreGState()
    }

    private func appendPenPoint(_ point: CGPoint, close: Bool) {
        guard let id = creation, creationTool == .pen else { return }
        let nearStart = penPoints.count >= 2 && hypot(point.x - penPoints[0].x, point.y - penPoints[0].y) <= 10 / session.zoom
        if (close || nearStart) && penPoints.count >= 2 {
            do {
                let geometry = try PathEditing.geometry(points: penPoints, closed: true)
                session.document.updateNode(id: id) { $0.frame = geometry.frame; $0.path = geometry.path }
                finishPen()
            } catch {
                session.message = "无法闭合路径"
            }
            return
        }
        penPoints.append(point)
        updatePenNode(id: id)
        needsDisplay = true
    }

    private func updatePenNode(id: UUID) {
        guard let geometry = try? PathEditing.geometry(points: penPoints) else { return }
        session.document.updateNode(id: id) { $0.frame = geometry.frame; $0.path = geometry.path }
    }

    private func finishPen() {
        guard creationTool == .pen else { return }
        guard penPoints.count >= 2 else {
            session.cancelGesture()
            session.selection = []
            creation = nil; creationTool = nil; penPoints = []
            session.message = "路径至少需要两个节点"
            return
        }
        finishGesture()
    }
    override func keyUp(with event: NSEvent) {
        if releaseNudge(event.keyCode) { return }
        super.keyUp(with: event)
    }
    override func resignFirstResponder() -> Bool {
        // beginText already owns the shared history when AppKit resigns Canvas.
        finishPrecision()
        if textID == nil { finishGesture() }
        return super.resignFirstResponder()
    }
    override func scrollWheel(with event: NSEvent) {
        session.finishInput?()
        if event.modifierFlags.contains(.command) { zoom(to: session.zoom * exp(-event.scrollingDeltaY/100), anchor: convert(event.locationInWindow, from: nil)) }
        else { session.pan.x -= event.scrollingDeltaX; session.pan.y -= event.scrollingDeltaY }; needsDisplay = true
    }
    override func magnify(with event: NSEvent) { session.finishInput?(); zoom(to: session.zoom*(1+event.magnification), anchor: convert(event.locationInWindow, from: nil)) }
    func zoom(to value: CGFloat, anchor: CGPoint) { session.finishInput?(); let z = min(8,max(0.05,value)); let ratio = z/session.zoom; session.pan = CGPoint(x: anchor.x-(anchor.x-session.pan.x)*ratio, y: anchor.y-(anchor.y-session.pan.y)*ratio); session.zoom = z; needsDisplay = true }
    func fit() { session.finishInput?(); let rect = CanvasRenderer.bounds(page: session.page); session.zoom = min(2,max(0.05,min((bounds.width-80)/rect.width,(bounds.height-80)/rect.height))); session.pan = CGPoint(x: bounds.midX-rect.midX*session.zoom,y: bounds.midY-rect.midY*session.zoom); needsDisplay = true }
    func beginText(_ id: UUID) {
        guard let n = session.document.node(id: id), session.editable(id) else { return }
        guard n.rotation == 0, session.document.parentID(of: id) == nil else { session.message = "嵌套或旋转文字请在右侧检查器编辑内容"; return }
        session.beginGesture(); textID = id
        let view = InlineTextView(frame: CGRect(x: n.frame.minX*session.zoom+session.pan.x, y: n.frame.minY*session.zoom+session.pan.y, width: max(80,n.frame.width*session.zoom), height: max(40,n.frame.height*session.zoom)))
        view.commitEditing = { [weak self] in self?.finishText(commit: true) }
        view.isRichText = false; view.allowsUndo = true; view.textContainerInset = .zero; view.textContainer?.lineFragmentPadding = 0; view.delegate = self
        view.string = n.text; view.typingAttributes = TextLayout.attributes(n); view.font = NSFont(name: n.fontName, size: n.fontSize*session.zoom) ?? .systemFont(ofSize: n.fontSize*session.zoom)
        view.setAccessibilityIdentifier("editor.inlineText"); view.setAccessibilityLabel(L10n.text("编辑文字，Command Return 完成，Escape 取消"))
        addSubview(view); editor = view; window?.makeFirstResponder(view); view.selectAll(nil); session.message = "Command Return 完成文字编辑 · Escape 取消"
    }
    func finishText(commit: Bool) {
        guard let editor, let id = textID else { return }
        let shouldRestoreCanvasFocus = window?.firstResponder === editor
        if commit { session.document.updateNode(id: id) { $0.text = editor.string }; session.commitGesture() }
        else { session.cancelGesture() }
        self.editor = nil; textID = nil; editor.removeFromSuperview()
        finishCreation(tool: textCreationTool); textCreationTool = nil
        // Another control may already own focus when it asks Canvas to commit.
        if shouldRestoreCanvasFocus { window?.makeFirstResponder(self) }
        needsDisplay = true
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(commit: false); return true }
        return false
    }
}

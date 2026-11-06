import AppKit
import SwiftUI
import OpenSketchCore

struct CanvasHost: NSViewRepresentable {
    var session: EditorSession
    func makeNSView(context: Context) -> CanvasView { CanvasView(session: session) }
    func updateNSView(_ view: CanvasView, context: Context) { _ = session.document; _ = session.selection; _ = session.zoom; _ = session.pan; _ = session.grid; _ = session.snapping; _ = session.needsInitialFit; view.needsDisplay = true; view.needsLayout = true }
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
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(session: EditorSession) {
        self.session = session; super.init(frame: .zero)
        // Keep artwork, selection overlays and the inline editor inside the viewport.
        clipsToBounds = true
        setAccessibilityIdentifier("editor.canvas"); setAccessibilityLabel("设计画布")
        session.finishInput = { [weak self] in self?.finishText(commit: true); self?.finishPrecision(); self?.finishGesture() }
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
    override func layout() {
        super.layout()
        // A new document's representable is created before it has a viewport.
        guard session.needsInitialFit, bounds.width > 0, bounds.height > 0 else { return }
        session.needsInitialFit = false
        fit()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)),
                                                   name: NSWindow.didResignKeyNotification, object: window)
        } else {
            session.finishInput?()
        }
    }
    @objc private func windowResignedKey(_ notification: Notification) { session.finishInput?() }
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
        drawPrecision(in: c)
        c.restoreGState()
        if session.page.nodes.isEmpty { ("开始设计\n选择上方工具，然后在画布中拖动" as NSString).draw(in: CGRect(x: 40, y: 35, width: 340, height: 70), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor]) }
    }
    override func mouseDown(with event: NSEvent) {
        session.finishInput?(); window?.makeFirstResponder(self)
        let p = world(event); start = p; creation = nil; creationTool = nil; resizing = nil
        if session.tool == .select {
            if let n = session.selected, n.kind != .group, n.rotation == 0, session.editable(n.id), let transform = SceneGeometry.worldTransform(id: n.id, in: session.page) {
                let corner = CGPoint(x: n.frame.width, y: n.frame.height).applying(transform)
                if hypot(corner.x-p.x, corner.y-p.y) < 10/session.zoom { resizing = n.id; session.beginGesture(); return }
            }
            if let hit = SceneGeometry.hitTest(p, in: session.page) {
                let target = session.canvasSelectionTarget(hit, direct: event.modifierFlags.contains(.option))
                if event.modifierFlags.contains(.shift) { if session.selection.contains(target) { session.selection.remove(target) } else { session.selection.insert(target) } }
                else if !session.selection.contains(target) { session.selection = [target] }
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
            let node = DesignNode(name: session.tool.title, kind: kind, frame: CGRect(x: p.x, y: p.y, width: kind == .text ? 240 : 120, height: kind == .text ? 80 : 100), text: kind == .text ? "输入文字" : "")
            if session.create(node) { creation = node.id; creationTool = session.tool } else { session.cancelGesture(); start = nil }
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let p = world(event)
        if updateMarquee(to: p) { return }
        guard let start else { return }
        if let id = creation { session.document.updateNode(id: id) { $0.frame = CGRect(x: min(start.x,p.x), y: min(start.y,p.y), width: max(1,abs(p.x-start.x)), height: max(1,abs(p.y-start.y))) } }
        else if let id = resizing, let n = session.gestureStart?.node(id: id), let transform = SceneGeometry.worldTransform(id: id, in: session.page) {
            let local = p.applying(transform.inverted()); session.document.updateNode(id: id) { $0.frame.size = CGSize(width: max(1, local.x), height: max(1, local.y)); $0.frame.origin = n.frame.origin }
        } else { moveSnapping(to: p, from: start, event: event) }
        needsDisplay = true
    }
    private func finishCreation(tool: EditorTool?) {
        if let tool, session.tool == tool { session.tool = .select }
    }
    func finishGesture(beginTextEditing: Bool = false) {
        let id = creation, tool = creationTool
        if start != nil { session.commitGesture() }
        guides = []
        start = nil; creation = nil; creationTool = nil; resizing = nil
        if beginTextEditing, let id, session.document.node(id: id)?.kind == .text {
            beginText(id)
            if textID == id { textCreationTool = tool; return }
        }
        finishCreation(tool: tool)
    }
    override func mouseUp(with event: NSEvent) { finishPrecision(); finishGesture(beginTextEditing: true); needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finishText(commit: false)
            finishPrecision(cancel: true)
            if start != nil {
                session.cancelGesture(); start = nil; creation = nil; resizing = nil
                finishCreation(tool: creationTool); creationTool = nil
            }
            guides = []; needsDisplay = true; return
        }
        if nudge(with: event) { return }
        if precision != nil { session.finishInput?() }
        if event.keyCode == 51 || event.keyCode == 117 { session.deleteSelection(); return }
        let tools: [String: EditorTool] = ["v": .select, "f": .frame, "r": .rectangle, "o": .ellipse, "t": .text]
        if let tool = tools[event.charactersIgnoringModifiers ?? ""] { session.tool = tool } else { super.keyDown(with: event) }
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
        view.setAccessibilityIdentifier("editor.inlineText"); view.setAccessibilityLabel("编辑文字，Command Return 完成，Escape 取消")
        addSubview(view); editor = view; window?.makeFirstResponder(view); view.selectAll(nil); session.message = "Command Return 完成文字编辑 · Escape 取消"
    }
    func finishText(commit: Bool) {
        guard let editor, let id = textID else { return }
        if commit { session.document.updateNode(id: id) { $0.text = editor.string }; session.commitGesture() }
        else { session.cancelGesture() }
        self.editor = nil; textID = nil; editor.removeFromSuperview()
        finishCreation(tool: textCreationTool); textCreationTool = nil
        window?.makeFirstResponder(self); needsDisplay = true
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(commit: false); return true }
        return false
    }
}

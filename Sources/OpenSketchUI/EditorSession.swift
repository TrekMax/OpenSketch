import AppKit
import Observation
import OpenSketchCore

enum EditorTool: String, CaseIterable { case select, frame, rectangle, ellipse, text
    var title: String { switch self { case .select: "选择"; case .frame: "画板"; case .rectangle: "矩形"; case .ellipse: "椭圆"; case .text: "文字" } }
    var symbol: String { switch self { case .select: "cursorarrow"; case .frame: "rectangle.dashed"; case .rectangle: "rectangle"; case .ellipse: "circle"; case .text: "textformat" } }
}
@MainActor @Observable final class EditorSession {
    var document: DesignDocument
    var history: DocumentHistory
    var pageID: UUID { willSet { if newValue != pageID { finishInspectorInput() } } }
    var selection: Set<UUID> = [] { willSet { if newValue != selection { finishInspectorInput() } } }
    var tool: EditorTool = .select
    var zoom: CGFloat = 1
    var pan = CGPoint(x: 60, y: 60)
    var grid = true
    var snapping = true
    var message = "拖动画布创建图形 · V 选择 / F 画板 / R 矩形 / O 椭圆 / T 文字"
    var url: URL?
    var gestureStart: DesignDocument?
    @ObservationIgnored private var canvasFinishInput: (() -> Void)?
    @ObservationIgnored var finishInspectorText: (() -> Void)?
    var inspectorEdit: InspectorNumberEdit?
    /// Canvas keeps ownership of its callback; callers always finish both input owners.
    var finishInput: (() -> Void)? {
        get { { [weak self] in self?.finishInspectorInput(); self?.canvasFinishInput?() } }
        set { canvasFinishInput = newValue }
    }
    var canUndoPendingNudge: (() -> Bool)?
    var needsInitialFit = false
    var fitCanvas: (() -> Void)?
    var zoomCanvas: ((CGFloat) -> Void)?
    var setCanvasZoom: ((CGFloat) -> Void)?
    init(document: DesignDocument = .blank()) {
        self.document = document; history = DocumentHistory(document: document); pageID = document.pages[0].id
    }
    var page: DesignPage { document.pages.first { $0.id == pageID } ?? document.pages[0] }
    var isDirty: Bool { history.isDirty(document) }
    var canUndo: Bool { history.canUndo || canUndoInspectorEdit || (canUndoPendingNudge?() ?? false) }
    var selected: DesignNode? { selection.count == 1 ? selection.first.flatMap { document.node(id: $0) } : nil }
    func editable(_ id: UUID) -> Bool {
        var next: UUID? = id
        while let current = next { guard let n = document.node(id: current), !n.isLocked, n.isVisible else { return false }; next = document.parentID(of: current) }
        return true
    }
    var roots: [UUID] { SceneGeometry.traversal(in: page).map(\.id).filter { id in
        guard selection.contains(id) else { return false }
        guard editable(id) else { return false }
        var p = document.parentID(of: id)
        while let ancestor = p { if selection.contains(ancestor) { return false }; p = document.parentID(of: ancestor) }
        return true
    } }
    func change(_ body: (inout DesignDocument) -> Void) { finishInput?(); history.begin(document: document); body(&document); history.commit(document: document) }
    func update(_ id: UUID, _ body: (inout DesignNode) -> Void) { guard editable(id) else { return }; change { $0.updateNode(id: id, body) } }
    func beginGesture() { gestureStart = document; history.begin(document: document) }
    func commitGesture() { history.commit(document: document); gestureStart = nil }
    func cancelGesture() { if let old = history.cancel() { document = old }; gestureStart = nil }
    @discardableResult func moveSelection(by delta: CGSize) -> Bool {
        guard let start = gestureStart else { return false }
        do {
            document = try CanvasEditing.translating(start, pageID: pageID, selection: selection, by: delta)
            return true
        } catch {
            switch error as? LayerEditError {
            case .invalidGeometry: message = "无法移动图层：位移或图层坐标无效或超出范围"
            case .lockedOrHidden: message = "无法移动图层：所选图层或其祖先已锁定或隐藏"
            default: message = "无法移动图层：选择无效，请重新选择图层"
            }
            return false
        }
    }
    func undo() { finishInput?(); if let d = history.undo(current: document) { document = d }; reconcilePage() }
    func redo() { finishInput?(); if let d = history.redo(current: document) { document = d }; reconcilePage() }
    func reconcilePage() {
        if !document.pages.contains(where: { $0.id == pageID }) { pageID = document.pages[0].id }
        let active = Set(SceneGeometry.traversal(in: page).map(\.id))
        selection.formIntersection(active)
    }
    @discardableResult func create(_ node: DesignNode) -> Bool {
        reconcilePage()
        do { try document.insertNode(node, into: pageID); selection = [node.id]; return true }
        catch { message = "无法创建图层：\(error.localizedDescription)"; return false }
    }
    func deleteSelection() { finishInput?(); let ids = roots; change { d in for id in ids { d.removeNode(id: id) } }; selection = [] }
    func detachedSelection() -> [DesignNode] {
        roots.compactMap { id in
            guard var node = document.node(id: id), let world = SceneGeometry.worldTransform(id: id, in: page) else { return nil }
            let center = CGPoint(x: node.frame.width/2, y: node.frame.height/2).applying(world)
            node.frame.origin = CGPoint(x: center.x-node.frame.width/2, y: center.y-node.frame.height/2)
            node.rotation = atan2(world.b, world.a) * 180 / .pi
            return node
        }
    }
    func duplicate() { finishInput?(); insert(detachedSelection().map { $0.cloned() }) }
    func insert(_ nodes: [DesignNode]) {
        finishInput?(); reconcilePage(); var candidate = document
        do {
            for var node in nodes { node.frame.origin.x += 20; node.frame.origin.y += 20; try candidate.insertNode(node, into: pageID) }
            _ = try DocumentCodec.encode(candidate)
            change { $0 = candidate }; selection = Set(nodes.map(\.id))
        } catch { message = "无法插入图层：\(error.localizedDescription)" }
    }
    func copy() { let nodes = detachedSelection(); guard let data = try? JSONEncoder().encode(nodes) else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .init("org.opensketch.nodes")) }
    func paste() {
        guard let data = NSPasteboard.general.data(forType: .init("org.opensketch.nodes")), data.count <= DocumentCodec.maximumDataBytes,
              let nodes = try? JSONDecoder().decode([DesignNode].self, from: data) else { return }
        let cloned = nodes.map { $0.cloned() }
        let probe = DesignDocument(pages: [DesignPage(nodes: cloned)])
        guard (try? DocumentCodec.encode(probe)) != nil else { message = "剪贴板内容无效"; return }; insert(cloned)
    }
    func selectPage(_ id: UUID) {
        guard document.pages.contains(where: { $0.id == id }), id != pageID else { return }
        finishInput?()
        pageID = id
        selection = []
    }
    func setZoom(_ value: CGFloat) {
        guard value.isFinite else { return }
        finishInput?()
        let value = min(8, max(0.05, value))
        if let setCanvasZoom { setCanvasZoom(value) }
        else { zoom = value }
    }
    func addPage() { finishInput?(); let p = DesignPage(name: "页面 \(document.pages.count + 1)"); change { $0.pages.append(p) }; pageID = p.id; selection = [] }
    func replace(_ d: DesignDocument, url: URL? = nil) { finishInput?(); document = d; history = DocumentHistory(document: d); pageID = d.pages[0].id; selection = []; self.url = url; pan = CGPoint(x: 60, y: 60); zoom = 1 }
    static func exampleDocument() -> DesignDocument {
        let title = DesignNode(name: "问候", kind: .text, frame: CGRect(x: 48, y: 44, width: 480, height: 68), text: "你好，openSketch ✨", fontSize: 36)
        let subtitle = DesignNode(name: "说明", kind: .text, frame: CGRect(x: 48, y: 116, width: 480, height: 56), text: "选择图层，调整颜色与形状。", fontSize: 22)
        let card = DesignNode(name: "紫色卡片", kind: .rectangle, frame: CGRect(x: 48, y: 204, width: 286, height: 156), style: NodeStyle(fill: RGBAColor(red: 0.58, green: 0.36, blue: 0.9), cornerRadius: 24))
        let circle = DesignNode(name: "暖色圆形", kind: .ellipse, frame: CGRect(x: 358, y: 214, width: 136, height: 136), style: NodeStyle(fill: RGBAColor(red: 1, green: 0.67, blue: 0.38)))
        let frame = DesignNode(name: "初次设计", kind: .frame, frame: CGRect(x: 0, y: 0, width: 560, height: 408), clipsContent: true, children: [title, subtitle, card, circle])
        return DesignDocument(name: "示例设计", pages: [DesignPage(name: "欢迎", nodes: [frame])])
    }

}

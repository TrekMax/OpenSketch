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
    var pageID: UUID
    var selection: Set<UUID> = []
    var tool: EditorTool = .select
    var zoom: CGFloat = 1
    var pan = CGPoint(x: 60, y: 60)
    var grid = true
    var message = "拖动画布创建图形 · V 选择 / F 画板 / R 矩形 / O 椭圆 / T 文字"
    var url: URL?
    var gestureStart: DesignDocument?
    var finishInput: (() -> Void)?
    var fitCanvas: (() -> Void)?
    init(document: DesignDocument = .blank()) {
        self.document = document; history = DocumentHistory(document: document); pageID = document.pages[0].id
    }
    var page: DesignPage { document.pages.first { $0.id == pageID } ?? document.pages[0] }
    var isDirty: Bool { history.isDirty(document) }
    var selected: DesignNode? { selection.count == 1 ? selection.first.flatMap { document.node(id: $0) } : nil }
    func editable(_ id: UUID) -> Bool {
        var next: UUID? = id
        while let current = next { guard let n = document.node(id: current), !n.isLocked, n.isVisible else { return false }; next = document.parentID(of: current) }
        return true
    }
    var roots: [UUID] { selection.filter { id in
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
    func moveSelection(by delta: CGSize) {
        guard let start = gestureStart else { return }
        for id in roots {
            guard let original = start.node(id: id) else { continue }
            let inverse = start.parentID(of: id).flatMap { SceneGeometry.worldTransform(id: $0, in: page)?.inverted() } ?? .identity
            let a = CGPoint.zero.applying(inverse), b = CGPoint(x: delta.width, y: delta.height).applying(inverse)
            document.updateNode(id: id) { $0.frame.origin = CGPoint(x: original.frame.minX + b.x-a.x, y: original.frame.minY + b.y-a.y) }
        }
    }
    func undo() { finishInput?(); if let d = history.undo(current: document) { document = d }; selection = selection.filter { document.node(id: $0) != nil } }
    func redo() { finishInput?(); if let d = history.redo(current: document) { document = d } }
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
    func duplicate() { insert(detachedSelection().map { $0.cloned() }) }
    func insert(_ nodes: [DesignNode]) { let pid = pageID; change { d in for var n in nodes { n.frame.origin.x += 20; n.frame.origin.y += 20; try? d.insertNode(n, into: pid) } }; selection = Set(nodes.map(\.id)) }
    func copy() { let nodes = detachedSelection(); guard let data = try? JSONEncoder().encode(nodes) else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .init("org.opensketch.nodes")) }
    func paste() {
        guard let data = NSPasteboard.general.data(forType: .init("org.opensketch.nodes")), data.count <= DocumentCodec.maximumDataBytes,
              let nodes = try? JSONDecoder().decode([DesignNode].self, from: data) else { return }
        let cloned = nodes.map { $0.cloned() }
        let probe = DesignDocument(pages: [DesignPage(nodes: cloned)])
        guard (try? DocumentCodec.encode(probe)) != nil else { message = "剪贴板内容无效"; return }; insert(cloned)
    }
    func addPage() { finishInput?(); let p = DesignPage(name: "页面 \(document.pages.count + 1)"); change { $0.pages.append(p) }; pageID = p.id; selection = [] }
    func replace(_ d: DesignDocument, url: URL? = nil) { document = d; history = DocumentHistory(document: d); pageID = d.pages[0].id; selection = []; self.url = url; pan = CGPoint(x: 60, y: 60); zoom = 1 }
}

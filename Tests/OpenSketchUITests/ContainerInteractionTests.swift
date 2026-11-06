import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct ContainerInteractionTests {
    @Test func nativeRootDropPreservesWorldGeometryAndUsesOneUndoAndRedo() throws {
        let a = shape(), frame = container()
        let f = fixture([a, frame]); defer { f.window.close() }
        let original = f.session.document
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        #expect(f.session.document.parentID(of: a.id) == nil)
        try release(f, at: CGPoint(x: 235, y: 155))
        #expect(f.session.document.parentID(of: a.id) == frame.id)
        try expectWorld(f, a.id, x: 230, y: 150)
        #expect(f.session.selection == [a.id])
        let dropped = f.session.document
        f.session.undo(); #expect(f.session.document == original); #expect(!f.session.history.canUndo)
        f.session.redo(); #expect(f.session.document == dropped)
        #expect(!f.session.history.isEditing)
    }

    @Test(arguments: [false, true]) func nativeChildLeavesOrCrossesFrame(crosses: Bool) throws {
        let a = shape(x: 20, y: 40), left = container(x: 0, y: 0, children: [])
        var source = left; source.children = [a]
        let target = container(x: 400, y: 0)
        let f = fixture([source, target]); defer { f.window.close() }
        let end = CGPoint(x: crosses ? 435 : 335, y: 155)
        try drag(f, from: CGPoint(x: 25, y: 45), to: end)
        try release(f, at: end)
        #expect(f.session.document.parentID(of: a.id) == (crosses ? target.id : nil))
        try expectWorld(f, a.id, x: end.x - 5, y: 150)
    }

    @Test func nativeDropIntoNinetyDegreeFramePreservesWorldRotationAndPosition() throws {
        let a = shape(), frame = container(rotation: 90)
        let f = fixture([a, frame]); defer { f.window.close() }
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 355, y: 225))
        try release(f, at: CGPoint(x: 355, y: 225))
        #expect(f.session.document.parentID(of: a.id) == frame.id)
        try expectWorld(f, a.id, x: 350, y: 220)
        let world = try #require(SceneGeometry.worldTransform(id: a.id, in: f.session.page))
        #expect(abs(world.a - 1) < 1e-9 && abs(world.b) < 1e-9)
    }

    @Test func failedMoveAfterSuccessNeverDropsAtUnappliedCursor() throws {
        let a = shape(), source = container(x: 0, y: 0, children: [])
        var frame = source; frame.children = [a]
        let f = fixture([frame, container(x: 400, y: 0)]); defer { f.window.close() }
        let original = f.session.document
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 435, y: 155))
        let moved = f.session.document
        #expect(f.canvas.dropTargetID != nil)
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 1e9 + 100, y: 155), f))
        #expect(f.session.document == moved)
        #expect(f.canvas.containerDrag == nil)
        try release(f, at: CGPoint(x: 1e9 + 100, y: 155))
        #expect(f.session.document == moved)
        #expect(f.session.document.parentID(of: a.id) == source.id)
        #expect(f.session.message.contains("无法移动图层"))
        f.session.undo(); #expect(f.session.document == original); #expect(!f.session.history.canUndo)
    }

    @Test func releaseLocationWithoutAppliedDragDoesNotChooseAnotherContainer() throws {
        let a = shape(), frame = container()
        let f = fixture([a, frame]); defer { f.window.close() }
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        try release(f, at: CGPoint(x: 600, y: 400))
        #expect(f.session.document.parentID(of: a.id) == frame.id)
    }

    @Test(arguments: [CGFloat(1), 2]) func subThreeScreenPointMoveDoesNotReparent(zoom: CGFloat) throws {
        let a = shape(x: 198, y: 140), frame = container()
        let f = fixture([frame, a]); defer { f.window.close() }
        f.session.zoom = zoom
        let start = CGPoint(x: 199 * zoom, y: 145 * zoom), end = CGPoint(x: start.x + 2, y: start.y)
        try drag(f, from: start, to: end); try release(f, at: end)
        #expect(f.session.document.parentID(of: a.id) == nil)
    }

    @Test func clickMouseCreationResizeAndKeyboardNudgeNeverReparent() throws {
        let a = shape(x: 230, y: 150), frame = container()
        let f = fixture([frame, a]); defer { f.window.close() }
        f.canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 235, y: 155), f))
        try release(f, at: CGPoint(x: 235, y: 155))
        #expect(!f.session.history.canUndo)
        try drag(f, from: CGPoint(x: 270, y: 180), to: CGPoint(x: 290, y: 200))
        try release(f, at: CGPoint(x: 290, y: 200))
        #expect(f.session.document.parentID(of: a.id) == nil)
        #expect(f.session.document.node(id: a.id)?.frame.size == CGSize(width: 60, height: 50))
        f.canvas.keyDown(with: try key(124, f)); f.canvas.keyUp(with: try key(124, f, up: true))
        #expect(f.session.document.parentID(of: a.id) == nil)
        f.session.tool = .rectangle
        try drag(f, from: CGPoint(x: 330, y: 230), to: CGPoint(x: 360, y: 260))
        let created = try #require(f.session.selection.first)
        try release(f, at: CGPoint(x: 360, y: 260))
        #expect(f.session.document.parentID(of: created) == nil)
    }

    @Test func movingFrameCarriesChildrenWithoutNestingAndMovingGroupDoesNotSplitIt() throws {
        let child = shape(x: 10, y: 10), target = container()
        let source = container(x: 0, y: 0, children: [child])
        let f = fixture([source, target]); defer { f.window.close() }
        f.session.selection = [source.id]
        try drag(f, from: CGPoint(x: 100, y: 80), to: CGPoint(x: 350, y: 180))
        try release(f, at: CGPoint(x: 350, y: 180))
        #expect(f.session.document.parentID(of: source.id) == nil)
        #expect(f.session.document.parentID(of: child.id) == source.id)
        try expectWorld(f, child.id, x: 260, y: 110)
        let group = DesignNode(kind: .group, frame: CGRect(x: 20, y: 40, width: 60, height: 50), children: [child])
        f.session.replace(DesignDocument(pages: [DesignPage(nodes: [group, target])]))
        f.session.pan = .zero
        try drag(f, from: CGPoint(x: 35, y: 55), to: CGPoint(x: 245, y: 165))
        try release(f, at: CGPoint(x: 245, y: 165))
        #expect(f.session.selection == [group.id])
        #expect(f.session.document.parentID(of: group.id) == target.id)
        #expect(f.session.document.parentID(of: child.id) == group.id)
    }

    @Test func explicitAncestorAndDescendantPlusOtherFrameChildMoveOnce() throws {
        let child = shape(x: 5, y: 5)
        let group = DesignNode(kind: .group, frame: CGRect(x: 20, y: 40, width: 60, height: 50), children: [child])
        let other = shape(x: 10, y: 10), source = container(x: 0, y: 0, children: [])
        var frame = source; frame.children = [group, other]
        let target = container(x: 400, y: 0)
        let f = fixture([frame, target]); defer { f.window.close() }
        f.session.selection = [group.id, child.id, other.id]
        try drag(f, from: CGPoint(x: 27, y: 47), to: CGPoint(x: 437, y: 157))
        try release(f, at: CGPoint(x: 437, y: 157))
        #expect(f.session.document.parentID(of: group.id) == target.id)
        #expect(f.session.document.parentID(of: child.id) == group.id)
        #expect(f.session.document.parentID(of: other.id) == target.id)
        try expectWorld(f, child.id, x: 435, y: 155)
        #expect(f.session.document.node(id: target.id)?.children.map(\.id) == [group.id, other.id])
    }

    @Test func lockedSelectedRootRejectsNativeMovementAtomicallyWithChineseStatus() throws {
        let a = shape(), blocked = DesignNode(kind: .rectangle, isLocked: true), target = container()
        let f = fixture([a, blocked, target]); defer { f.window.close() }
        f.session.selection = [a.id, blocked.id]
        let original = f.session.document
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        try release(f, at: CGPoint(x: 235, y: 155))
        #expect(f.session.document == original)
        #expect(f.session.message.contains("锁定"))
        #expect(!f.session.history.canUndo)
    }

    @Test func dropFailureKeepsSuccessfulPositionAndRefusesAllHierarchyChanges() throws {
        let a = shape(), b = shape(x: 80), frame = container()
        let f = fixture([a, b, frame]); defer { f.window.close() }
        f.session.selection = [a.id, b.id]
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        f.session.document.updateNode(id: b.id) { $0.isLocked = true }
        let moved = f.session.document
        try release(f, at: CGPoint(x: 235, y: 155))
        #expect(f.session.document == moved)
        #expect(f.session.message.contains("无法调整图层归属"))
        #expect(f.session.message.contains("锁定"))
    }

    @Test(arguments: ["escape", "finish", "focus", "window", "close", "viewport", "size", "page", "replace", "detach"])
    func interruptedDragClearsPreviewWithoutDropping(reason: String) throws {
        let a = shape(), target = container()
        let f = fixture([a, target]); defer { f.window.close() }
        f.session.document.pages.append(DesignPage())
        f.session.history = DocumentHistory(document: f.session.document)
        let original = f.session.document
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        #expect(f.canvas.dropTargetID == target.id)
        switch reason {
        case "escape": f.canvas.keyDown(with: try key(53, f))
        case "finish": f.session.finishInput?()
        case "focus": _ = f.canvas.resignFirstResponder()
        case "window": NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
        case "close": f.window.close()
        case "viewport": f.canvas.zoom(to: 2, anchor: .zero)
        case "size": f.canvas.setFrameSize(CGSize(width: 700, height: 450))
        case "page": f.session.selectPage(f.session.document.pages[1].id)
        case "replace": f.session.replace(.blank())
        default: f.canvas.removeFromSuperview()
        }
        #expect(!f.session.history.isEditing)
        #expect(f.canvas.start == nil)
        #expect(f.canvas.containerDrag == nil)
        if reason == "escape" { #expect(f.session.document == original); #expect(!f.session.history.canUndo) }
        else if reason != "replace" { #expect(f.session.document.parentID(of: a.id) == nil); try expectWorld(f, a.id, x: 230, y: 150, page: original.pages[0].id) }
        let cleared = try pixel(f.canvas, x: 200, y: 280)
        f.canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 235, y: 155), f))
        #expect(try distance(cleared, pixel(f.canvas, x: 200, y: 280)) < 0.002)
    }

    @Test func targetBitmapDisappearsAfterDropAndExportRemainsUnchangedWhileHeld() throws {
        let a = shape(), frame = container()
        let f = fixture([a, frame]); defer { f.window.close() }
        let before = try pixel(f.canvas, x: 200, y: 280)
        let exportBefore = try Exporter.png(page: f.session.page, bounds: f.canvas.bounds)
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        let held = try pixel(f.canvas, x: 200, y: 280)
        #expect(distance(before, held) > 0.02)
        let exportHeld = try Exporter.png(page: f.session.page, bounds: f.canvas.bounds)
        try release(f, at: CGPoint(x: 235, y: 155))
        let released = try pixel(f.canvas, x: 200, y: 280)
        #expect(distance(before, released) < 0.002)
        let exportedBefore = try exportedPixel(exportBefore, x: 200, y: 280)
        let exportedHeld = try exportedPixel(exportHeld, x: 200, y: 280)
        #expect(distance(exportedBefore, exportedHeld) < 0.002)
        #expect(distance(held, exportedHeld) > 0.02)
        #expect(f.canvas.containerDrag == nil)
    }

    @Test func unclippedMovingOutlineRemainsVisibleOutsideOldClippingFrame() throws {
        let a = shape(x: 20, y: 40), frame = container(x: 0, y: 0, children: [])
        var source = frame; source.children = [a]
        let f = fixture([source]); defer { f.window.close() }
        let before = try pixel(f.canvas, x: 330, y: 150)
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 335, y: 155))
        #expect(distance(before, try pixel(f.canvas, x: 330, y: 150)) > 0.02)
        f.session.finishInput?()
        #expect(distance(before, try pixel(f.canvas, x: 330, y: 150)) < 0.002)
        #expect(f.session.document.parentID(of: a.id) == source.id)
    }

    @Test func droppedTreeRowsAndRealPackageReopenKeepHierarchyAndIDs() throws {
        let a = shape(), frame = container()
        let f = fixture([a, frame]); defer { f.window.close() }
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155)); try release(f, at: CGPoint(x: 235, y: 155))
        let rows = LayerTreeRow.rows(in: f.session.page)
        #expect(rows.map(\.id) == [frame.id, a.id])
        #expect(rows.map(\.depth) == [0, 1])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".opensketch")
        defer { try? FileManager.default.removeItem(at: url) }
        try DocumentCodec.save(f.session.document, to: url)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("document.json").path))
        let reopened = try DocumentCodec.load(from: url)
        #expect(reopened == f.session.document)
        #expect(reopened.parentID(of: a.id) == frame.id)
    }

    @Test func nativeChildOfRotatedFrameCrossesToUprightFrameWithoutWorldJump() throws {
        let a = shape(), source = container(x: 0, y: 100, rotation: 90, children: [])
        var rotated = source; rotated.children = [a]
        let target = container(x: 400, y: 0)
        let f = fixture([rotated, target]); defer { f.window.close() }
        try drag(f, from: CGPoint(x: 230, y: 120), to: CGPoint(x: 435, y: 155))
        try release(f, at: CGPoint(x: 435, y: 155))
        #expect(f.session.document.parentID(of: a.id) == target.id)
        try expectWorld(f, a.id, x: 440, y: 130)
        let world = try #require(SceneGeometry.worldTransform(id: a.id, in: f.session.page))
        #expect(abs(world.a) < 1e-9 && abs(world.b - 1) < 1e-9)
    }

    @Test func directGroupChildMovingWithinSameFrameKeepsItsImmediateParent() throws {
        let a = shape(x: 10, y: 10)
        let group = DesignNode(kind: .group, frame: CGRect(x: 20, y: 40, width: 80, height: 60), children: [a])
        let frame = container(x: 0, y: 0, children: [group])
        let f = fixture([frame]); defer { f.window.close() }
        f.canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 35, y: 55), f, flags: .option))
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 135, y: 155), f))
        try release(f, at: CGPoint(x: 135, y: 155))
        #expect(f.session.selection == [a.id])
        #expect(f.session.document.parentID(of: a.id) == group.id)
        try expectWorld(f, a.id, x: 130, y: 150)
    }

    @Test func snappingBackToOriginalGeometryDoesNotTurnMouseMovementIntoDrop() throws {
        let a = shape(x: 200, y: 100), frame = container()
        let f = fixture([frame, a]); defer { f.window.close() }
        f.session.snapping = true
        let original = f.session.document
        try drag(f, from: CGPoint(x: 205, y: 105), to: CGPoint(x: 210, y: 105))
        #expect(f.session.document == original)
        #expect(f.canvas.containerDrag == nil)
        try release(f, at: CGPoint(x: 210, y: 105))
        #expect(f.session.document == original)
        #expect(!f.session.history.canUndo)
    }

    @Test func rotatedTargetOutlineUsesTrueEdgesInsteadOfWorldBoundingBox() throws {
        let a = shape(), frame = container(rotation: 45)
        let f = fixture([a, frame]); defer { f.window.close() }
        let edgeBefore = try pixel(f.canvas, x: 438, y: 136)
        let emptyBefore = try pixel(f.canvas, x: 156, y: 100)
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 355, y: 225))
        #expect(f.canvas.dropTargetID == frame.id)
        #expect(distance(edgeBefore, try pixel(f.canvas, x: 438, y: 136)) > 0.02)
        #expect(distance(emptyBefore, try pixel(f.canvas, x: 156, y: 100)) < 0.002)
        f.session.finishInput?()
        #expect(distance(edgeBefore, try pixel(f.canvas, x: 438, y: 136)) < 0.002)
    }

    @Test(arguments: [CGFloat(1), 2]) func targetStrokeWidthRemainsInScreenPoints(zoom: CGFloat) throws {
        let a = shape(), frame = container()
        let f = fixture([a, frame]); defer { f.window.close() }
        f.session.zoom = zoom
        let x = 200 * zoom, y = 200 * zoom
        let beforeCenter = try pixel(f.canvas, x: x, y: y)
        let beforeLeft = try pixel(f.canvas, x: x - 2, y: y)
        let beforeRight = try pixel(f.canvas, x: x + 2, y: y)
        try drag(f, from: CGPoint(x: 25 * zoom, y: 45 * zoom), to: CGPoint(x: 235 * zoom, y: 155 * zoom))
        #expect(f.canvas.dropTargetID == frame.id)
        #expect(distance(beforeCenter, try pixel(f.canvas, x: x, y: y)) > 0.02)
        #expect(distance(beforeLeft, try pixel(f.canvas, x: x - 2, y: y)) < 0.002)
        #expect(distance(beforeRight, try pixel(f.canvas, x: x + 2, y: y)) < 0.002)
    }

    @Test(arguments: [false, true]) func resizingViewportPreservesExistingTextAndCreationInput(textEditing: Bool) throws {
        let text = DesignNode(kind: .text, frame: CGRect(x: 20, y: 40, width: 100, height: 50), text: "原文")
        let f = fixture([text, container()]); defer { f.window.close() }
        if textEditing {
            f.canvas.beginText(text.id)
            let editor = try #require(f.canvas.editor)
            editor.string = "未提交文字"
            f.canvas.setFrameSize(CGSize(width: 700, height: 450))
            #expect(f.canvas.editor === editor)
            #expect(f.session.document.node(id: text.id)?.text == "原文")
            #expect(f.session.history.isEditing)
            f.canvas.finishText(commit: false)
        } else {
            f.session.tool = .rectangle
            try drag(f, from: CGPoint(x: 330, y: 230), to: CGPoint(x: 360, y: 260))
            let created = try #require(f.canvas.creation)
            f.canvas.setFrameSize(CGSize(width: 700, height: 450))
            #expect(f.canvas.creation == created)
            #expect(f.session.tool == .rectangle)
            #expect(f.session.history.isEditing)
            try release(f, at: CGPoint(x: 360, y: 260))
            #expect(f.session.document.parentID(of: created) == nil)
        }
    }

    @Test func workspaceSwitchCommitsOnlyOldPositionAndClearsItsPendingDrop() throws {
        let a = shape(), frame = container()
        let workspace = DocumentWorkspace()
        workspace.current.session.replace(DesignDocument(pages: [DesignPage(nodes: [a, frame])]))
        let first = workspace.current
        let f = fixture([a, frame], session: first.session); defer { f.window.close() }
        let original = first.session.document
        try drag(f, from: CGPoint(x: 25, y: 45), to: CGPoint(x: 235, y: 155))
        #expect(f.canvas.dropTargetID == frame.id)
        let second = workspace.newDocument()
        #expect(f.canvas.containerDrag == nil)
        #expect(first.session.document.parentID(of: a.id) == nil)
        try expectWorld(f, a.id, x: 230, y: 150)
        try release(f, at: CGPoint(x: 235, y: 155))
        #expect(first.session.document.parentID(of: a.id) == nil)
        #expect(!second.session.history.canUndo && !second.session.isDirty)
        first.session.undo(); #expect(first.session.document == original)
        #expect(!first.session.history.canUndo)
    }

    private typealias Fixture = (session: EditorSession, canvas: CanvasView, window: NSWindow)
    private func shape(x: CGFloat = 20, y: CGFloat = 40) -> DesignNode {
        DesignNode(kind: .rectangle, frame: CGRect(x: x, y: y, width: 40, height: 30))
    }
    private func container(x: CGFloat = 200, y: CGFloat = 100, rotation: CGFloat = 0, children: [DesignNode] = []) -> DesignNode {
        DesignNode(kind: .frame, frame: CGRect(x: x, y: y, width: 300, height: 250), rotation: rotation, clipsContent: true, children: children)
    }
    private func fixture(_ nodes: [DesignNode], session provided: EditorSession? = nil) -> Fixture {
        _ = NSApplication.shared
        let session = provided ?? EditorSession(document: DesignDocument(pages: [DesignPage(nodes: nodes)]))
        session.pan = .zero; session.grid = false; session.snapping = false
        let canvas = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 800, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas
        return (session, canvas, window)
    }
    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint, _ f: Fixture, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: f.canvas.convert(point, to: nil), modifierFlags: flags, timestamp: 0, windowNumber: f.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    private func key(_ code: UInt16, _ f: Fixture, up: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: f.window.windowNumber, context: nil, characters: code == 53 ? "\u{1b}" : "\u{F703}", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
    }
    private func drag(_ f: Fixture, from: CGPoint, to: CGPoint) throws {
        f.canvas.mouseDown(with: try mouse(.leftMouseDown, from, f))
        f.canvas.mouseDragged(with: try mouse(.leftMouseDragged, to, f))
    }
    private func release(_ f: Fixture, at point: CGPoint) throws { f.canvas.mouseUp(with: try mouse(.leftMouseUp, point, f)) }
    private func expectWorld(_ f: Fixture, _ id: UUID, x: CGFloat, y: CGFloat, page: UUID? = nil) throws {
        let p = f.session.document.pages.first { $0.id == (page ?? f.session.pageID) }!
        let world = try #require(SceneGeometry.worldTransform(id: id, in: p))
        #expect(abs(world.tx - x) < 1e-8); #expect(abs(world.ty - y) < 1e-8)
    }
    private func pixel(_ canvas: CanvasView, x: CGFloat, y: CGFloat) throws -> NSColor {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.needsDisplay = true; canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        return try #require(bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / canvas.bounds.width), y: Int(y * CGFloat(bitmap.pixelsHigh) / canvas.bounds.height))?.usingColorSpace(.sRGB))
    }
    private func exportedPixel(_ data: Data, x: Int, y: Int) throws -> NSColor {
        let bitmap = try #require(NSBitmapImageRep(data: data))
        return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
    }
}

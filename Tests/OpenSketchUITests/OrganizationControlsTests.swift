import AppKit
import SwiftUI
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct OrganizationControlsTests {
    @Test func actualSizePreservesTheCanvasCenterWithoutDirtyingTheDocument() {
        _ = NSApplication.shared
        let controller = AppController()
        let session = controller.session
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        session.pan = CGPoint(x: 20, y: 30)
        session.zoom = 2
        controller.actualSize(nil)
        #expect(session.zoom == 1)
        #expect(session.pan == CGPoint(x: 110, y: 90))
        #expect(!session.isDirty)
        #expect(!session.history.canUndo)
    }

    @Test func toolbarOffersTheHostedZoomSlider() throws {
        _ = NSApplication.shared
        let controller = AppController()
        let toolbar = NSToolbar(identifier: "organization-test")
        #expect(controller.toolbarDefaultItemIdentifiers(toolbar).contains(.init("view.zoomSlider")))
        let item = try #require(controller.toolbar(toolbar, itemForItemIdentifier: .init("view.zoomSlider"), willBeInsertedIntoToolbar: true))
        #expect(item.view?.frame.size == CGSize(width: 160, height: 32))
    }
    @Test func selectingAnotherPageClearsSelectionWithoutAddingHistory() {
        let node = DesignNode(kind: .rectangle)
        let first = DesignPage(nodes: [node]), second = DesignPage(name: "第二页")
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        session.selection = [node.id]
        session.selectPage(second.id)
        #expect(session.pageID == second.id)
        #expect(session.selection.isEmpty)
        #expect(!session.isDirty)
        #expect(!session.history.canUndo)
        session.selectPage(UUID())
        #expect(session.pageID == second.id)
    }

    @Test func pageSwitchCommitsPendingTextOnTheOriginalPage() throws {
        _ = NSApplication.shared
        let text = DesignNode(kind: .text, text: "原文")
        let first = DesignPage(nodes: [text]), second = DesignPage(name: "第二页")
        let session = EditorSession(document: DesignDocument(pages: [first, second]))
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        canvas.beginText(text.id)
        try #require(canvas.editor).string = "已提交"
        session.selectPage(second.id)
        #expect(session.document.node(id: text.id)?.text == "已提交")
        #expect(session.pageID == second.id)
        #expect(session.selection.isEmpty)
        #expect(canvas.editor == nil)
        session.undo()
        #expect(session.document.node(id: text.id)?.text == "原文")
        #expect(!session.history.canUndo)
    }

    @Test func invalidPageDoesNotFinishInputOrChangeSelection() {
        let session = EditorSession()
        let id = UUID()
        session.selection = [id]
        var finished = false
        session.finishInput = { finished = true }
        let page = session.pageID
        session.selectPage(UUID())
        #expect(session.pageID == page)
        #expect(session.selection == [id])
        #expect(!finished)
    }

    @Test(arguments: [false, true]) func contextActionUsesUnselectedRowAndCommitsPendingText(deleting: Bool) throws {
        _ = NSApplication.shared
        let text = DesignNode(kind: .text, text: "原文")
        let other = DesignNode(kind: .rectangle)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [text, other])]))
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        session.selection = [text.id]
        canvas.beginText(text.id)
        try #require(canvas.editor).string = "已提交"
        #expect(session.canEditContextLayers(for: other.id))
        #expect(session.selection == [text.id])
        #expect(canvas.editor != nil)
        if deleting { session.deleteContextLayers(for: other.id) }
        else { session.duplicateContextLayers(for: other.id) }
        #expect(canvas.editor == nil)
        #expect(session.document.node(id: text.id)?.text == "已提交")
        #expect(session.page.nodes.count == (deleting ? 1 : 3))
        #expect((session.document.node(id: other.id) == nil) == deleting)
        if !deleting {
            #expect(session.selected?.kind == .rectangle)
            #expect(session.selected?.id != other.id)
            #expect(session.selected?.frame.origin == CGPoint(x: 20, y: 20))
        }
        session.undo()
        #expect(session.page.nodes.count == 2)
        #expect(session.document.node(id: text.id)?.text == "已提交")
    }

    @Test(arguments: [false, true]) func contextActionPreservesMultiSelectionAndNormalizesParentChild(deleting: Bool) {
        let child = DesignNode(kind: .rectangle)
        let group = DesignNode(kind: .group, children: [child])
        let sibling = DesignNode(kind: .ellipse)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [group, sibling])]))
        session.selection = [group.id, child.id, sibling.id]
        #expect(session.canEditContextLayers(for: child.id))
        #expect(session.selection.count == 3)
        if deleting { session.deleteContextLayers(for: child.id) }
        else { session.duplicateContextLayers(for: child.id) }
        #expect(session.page.nodes.count == (deleting ? 0 : 4))
        if !deleting {
            #expect(session.selection.count == 2)
            #expect(session.page.nodes.filter { $0.kind == .group }.count == 2)
            #expect(session.page.nodes.last { $0.kind == .group }?.children.count == 1)
        }
        session.undo()
        #expect(session.page.nodes == [group, sibling])
    }

    @Test(arguments: [false, true], [false, true])
    func contextActionsRejectTheEntireSelectionWhenAnyRootOrAncestorIsUnavailable(hidden: Bool, ancestor: Bool) {
        let first = DesignNode(kind: .rectangle)
        var blocked = DesignNode(kind: .ellipse)
        var group = DesignNode(kind: .group, children: [blocked])
        if ancestor {
            group.isVisible = !hidden; group.isLocked = !hidden
        } else {
            blocked.isVisible = !hidden; blocked.isLocked = !hidden
            group.children = [blocked]
        }
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [first, group])]))
        session.selection = [first.id, blocked.id]
        let original = session.document
        #expect(!session.canEditContextLayers(for: first.id))
        session.duplicateContextLayers(for: first.id)
        #expect(session.document == original)
        #expect(session.selection == [first.id, blocked.id])
        session.deleteContextLayers(for: first.id)
        #expect(session.document == original)
        #expect(session.selection == [first.id, blocked.id])
        #expect(!session.isDirty)
    }

    @Test func contextActionsRejectMissingAndOtherPageIDs() {
        let first = DesignNode(kind: .rectangle), second = DesignNode(kind: .ellipse)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [first]), DesignPage(nodes: [second])]))
        let original = session.document
        for invalid in [UUID(), second.id] {
            session.selection = [first.id, invalid]
            #expect(!session.canEditContextLayers(for: first.id))
            session.duplicateContextLayers(for: first.id)
            session.deleteContextLayers(for: first.id)
            #expect(session.document == original)
        }
    }

    @Test(arguments: [(CGFloat(-2), CGFloat(0.05)), (0.05, 0.05), (1, 1), (8, 8), (20, 8)])
    func absoluteZoomClampsWithoutHistory(input: CGFloat, expected: CGFloat) {
        let session = EditorSession()
        session.setZoom(input)
        #expect(session.zoom == expected)
        #expect(!session.isDirty)
        #expect(!session.history.canUndo)
    }

    @Test(arguments: [CGFloat.nan, .infinity, -.infinity]) func invalidZoomDoesNotFinishInput(input: CGFloat) {
        let session = EditorSession()
        var finished = false
        session.finishInput = { finished = true }
        session.setZoom(input)
        #expect(session.zoom == 1)
        #expect(!finished)
    }

    @Test(arguments: [CGFloat(0.05), 1, 8]) func absoluteZoomPreservesWorldPointAtCanvasCenter(value: CGFloat) {
        _ = NSApplication.shared
        let session = EditorSession()
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        session.pan = CGPoint(x: 20, y: 30)
        session.zoom = 2
        session.setZoom(value)
        #expect(abs((200 - session.pan.x) / session.zoom - 90) < 0.0001)
        #expect(abs((150 - session.pan.y) / session.zoom - 60) < 0.0001)
        #expect(!session.isDirty)
    }

    @Test func hostedSliderTracksTheCurrentDocumentAndExternalZoomChanges() throws {
        _ = NSApplication.shared
        let controller = AppController()
        let first = controller.session
        let firstCanvas = CanvasView(session: first)
        firstCanvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let toolbar = NSToolbar(identifier: "organization-host-test")
        let item = try #require(controller.toolbar(toolbar, itemForItemIdentifier: .init("view.zoomSlider"), willBeInsertedIntoToolbar: true))
        let host = try #require(item.view)
        let window = offscreenWindow()
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let control = try #require(slider(in: host))
        #expect(control.isContinuous)
        #expect(control.accessibilityIdentifier() == "view.zoomSlider")
        #expect(control.accessibilityLabel() == "缩放")
        control.doubleValue = 1
        control.sendAction(control.action, to: control.target)
        #expect(first.zoom == 2)
        first.zoomCanvas?(0.5)
        refresh(host)
        #expect(abs(control.doubleValue) < 0.0001)
        #expect(control.accessibilityValue() as? String == "100%")
        controller.newDocument(nil)
        let second = controller.session
        second.zoom = 4
        refresh(host)
        let current = try #require(slider(in: host))
        #expect(abs(current.doubleValue - 2) < 0.0001)
        current.doubleValue = -1
        current.sendAction(current.action, to: current.target)
        #expect(second.zoom == 0.5)
        #expect(first.zoom == 1)
        controller.actualSize(nil)
        refresh(host)
        #expect(abs(current.doubleValue) < 0.0001)
        #expect(!first.isDirty && !second.isDirty)
    }

    @Test func zoomSliderFloatingFeedbackIsLiveNonactivatingAndCleansUp() throws {
        _ = NSApplication.shared
        let workspace = DocumentWorkspace()
        let host = NSHostingView(rootView: ZoomControlView(workspace: workspace))
        let window = offscreenWindow()
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let control = try #require(slider(in: host) as? ZoomSlider)
        let responder = window.firstResponder
        control.setEditing(true)
        let panel = try #require(control.percentagePanel)
        #expect(control.isEditing)
        #expect(panel.isVisible)
        #expect(panel.parent === window)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(window.firstResponder === responder)
        #expect(panel.frame.maxX < -10000)
        control.doubleValue = 1.5
        control.sendAction(control.action, to: control.target)
        #expect(control.accessibilityValue() as? String == "283%")
        let label = try #require(panel.contentView?.subviews.first as? NSTextField)
        #expect(label.stringValue == "283%")
        control.setEditing(false)
        #expect(!control.isEditing && !panel.isVisible)
        #expect(panel.parent == nil)
        control.setEditing(true)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(!control.isEditing && !panel.isVisible)
        control.setEditing(true)
        workspace.newDocument()
        refresh(host)
        #expect(!control.isEditing && !panel.isVisible)
        control.setEditing(true)
        control.removeFromSuperview()
        #expect(!control.isEditing && !panel.isVisible)
        #expect(panel.parent == nil)
    }

    @Test func sliderCellTrackingShowsFeedbackUntilMouseUp() throws {
        _ = NSApplication.shared
        let window = offscreenWindow()
        defer { window.close() }
        let control = ZoomSlider(frame: CGRect(x: 10, y: 10, width: 160, height: 32))
        window.contentView?.addSubview(control)
        var editingDuringAction = false
        control.configure(zoom: 1, documentID: UUID()) { _ in
            editingDuringAction = control.isEditing && (control.percentagePanel?.isVisible ?? false)
        }
        let cell = try #require(control.cell as? NSSliderCell)
        let point = CGPoint(x: 80, y: 16)
        #expect(cell.startTracking(at: point, in: control))
        #expect(control.isEditing)
        control.doubleValue = 1.5
        control.sendAction(control.action, to: control.target)
        #expect(editingDuringAction)
        cell.stopTracking(last: point, current: point, in: control, mouseIsUp: true)
        #expect(!control.isEditing)
        #expect(control.percentagePanel?.isVisible == false)
    }

    @Test func commandWheelUpdatesTheHostedSlider() throws {
        _ = NSApplication.shared
        let workspace = DocumentWorkspace()
        let session = workspace.current.session
        let canvas = CanvasView(session: session)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let host = NSHostingView(rootView: ZoomControlView(workspace: workspace))
        let window = offscreenWindow()
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let control = try #require(slider(in: host))
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -50, wheel2: 0, wheel3: 0))
        cgEvent.flags = .maskCommand
        canvas.scrollWheel(with: try #require(NSEvent(cgEvent: cgEvent)))
        refresh(host)
        #expect(abs(session.zoom - 1.64872127) < 0.00001)
        #expect(abs(control.doubleValue - 0.72134752) < 0.00001)
        #expect(control.accessibilityValue() as? String == "165%")
        #expect(!session.isDirty)
    }

    private func offscreenWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    private func slider(in view: NSView) -> NSSlider? {
        if let slider = view as? NSSlider { return slider }
        return view.subviews.lazy.compactMap { slider(in: $0) }.first
    }

    private func refresh(_ view: NSView) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        view.layoutSubtreeIfNeeded()
    }

}

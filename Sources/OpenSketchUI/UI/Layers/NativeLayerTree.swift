import AppKit
import SwiftUI

/// AppKit owns row hit testing, selection, drag tracking and insertion feedback.
struct NativeLayerTree: NSViewRepresentable {
    @Environment(\.locale) private var locale
    @Bindable var session: EditorSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ view: NSScrollView, context: Context) {
        _ = locale
        // Read observable values here so native views receive document/selection edits.
        _ = session.page; _ = session.selection; _ = session.sidebarRename?.request.id
        context.coordinator.update()
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.session.finishSidebarRename()
        coordinator.endDrag()
    }
}

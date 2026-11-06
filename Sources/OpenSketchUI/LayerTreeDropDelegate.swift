import SwiftUI
import OpenSketchCore

struct LayerTreeDropDelegate: DropDelegate {
    let session: EditorSession
    let node: DesignNode?
    @Binding var target: LayerDropDestination?
    var expand: (UUID) -> Void

    static let rowHeight: CGFloat = 32

    static func destination(node: DesignNode, y: CGFloat) -> LayerDropDestination {
        if node.kind == .group || node.kind == .frame {
            if y < rowHeight * 0.25 { return .above(node.id) }
            if y > rowHeight * 0.75 { return .below(node.id) }
            return .inside(node.id)
        }
        return y < rowHeight / 2 ? .above(node.id) : .below(node.id)
    }

    private func destination(_ info: DropInfo) -> LayerDropDestination {
        node.map { Self.destination(node: $0, y: info.location.y) } ?? .pageEnd
    }
    private func advertisedToken(_ info: DropInfo) -> UUID? {
        guard let request = session.sidebarLayerDrag,
              info.hasItemsConforming(to: [request.itemTypeIdentifier]) else { return nil }
        return request.id
    }
    func validateDrop(info: DropInfo) -> Bool { advertisedToken(info) != nil }
    func dropEntered(info: DropInfo) { _ = update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: update(info) ? .move : .forbidden) }
    private func update(_ info: DropInfo) -> Bool {
        let destination = destination(info)
        guard let token = advertisedToken(info), session.canDropSidebarLayers(token, to: destination) else {
            target = nil
            return false
        }
        target = destination
        return true
    }
    func dropExited(info: DropInfo) {
        switch target {
        case .above(let id), .below(let id), .inside(let id): if id == node?.id { target = nil }
        case .pageEnd: if node == nil { target = nil }
        case nil: break
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        let destination = destination(info)
        target = nil
        return session.acceptSidebarLayerDrop(info.itemProviders(for: [SidebarLayerDrag.typeIdentifier]), to: destination) { moved in
            if moved, case .inside(let id) = destination { expand(id) }
        }
    }
}

struct LayerTreeDragSource: ViewModifier {
    let session: EditorSession
    let node: DesignNode

    @ViewBuilder func body(content: Content) -> some View {
        if session.sidebarRename == nil {
            content.onDrag { session.sidebarLayerDragProvider(for: node.id) } preview: {
                Label(node.name.isEmpty ? "图层" : node.name, systemImage: "square.3.layers.3d")
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        } else { content }
    }
}

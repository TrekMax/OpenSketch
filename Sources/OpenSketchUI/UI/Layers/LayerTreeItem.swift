import Foundation
import OpenSketchCore

@MainActor final class LayerTreeItem: NSObject {
    var node: DesignNode?
    var children: [LayerTreeItem] = []
    var id: UUID? { node?.id }
    var isContainer: Bool { node?.kind == .group || node?.kind == .frame || !children.isEmpty }
    init(node: DesignNode?) { self.node = node }
}

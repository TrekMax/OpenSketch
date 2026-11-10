import Foundation
import CoreGraphics

public enum StackLayoutEngine {
    public static func applying(_ document: DesignDocument, pageID: UUID? = nil) throws -> DesignDocument {
        var result = document
        for index in result.pages.indices where pageID == nil || result.pages[index].id == pageID {
            try solve(nodes: &result.pages[index].nodes)
        }
        _ = try DocumentCodec.encode(result)
        return result
    }

    private static func solve(nodes: inout [DesignNode]) throws {
        for index in nodes.indices {
            try solve(nodes: &nodes[index].children)
            guard let layout = nodes[index].stackLayout, !nodes[index].children.isEmpty else { continue }
            try solve(node: &nodes[index], layout: layout)
        }
    }

    private static func solve(node: inout DesignNode, layout: StackLayout) throws {
        let children = node.children
        let horizontal = layout.axis == .horizontal
        let count = children.count
        let spacing = max(0, layout.spacing)
        let pad = layout.padding
        let availableMain = (horizontal ? Double(node.frame.width) - pad.left - pad.right : Double(node.frame.height) - pad.top - pad.bottom)
        let availableCross = horizontal ? Double(node.frame.height) - pad.top - pad.bottom : Double(node.frame.width) - pad.left - pad.right
        let fixedMain = children.reduce(0.0) { partial, child in partial + (horizontal ? Double(child.frame.width) : Double(child.frame.height)) }
        let requiredMain = fixedMain + spacing * Double(max(0, count - 1)) + (horizontal ? pad.left + pad.right : pad.top + pad.bottom)
        if layout.sizing == .fit {
            if horizontal { node.frame.size.width = CGFloat(max(0.1, requiredMain)) }
            else { node.frame.size.height = CGFloat(max(0.1, requiredMain)) }
        }
        let mainSize = layout.sizing == .fit ? requiredMain - (horizontal ? pad.left + pad.right : pad.top + pad.bottom) : availableMain
        var cursor = horizontal ? pad.left : pad.top
        let fillCount = children.filter { horizontal ? $0.constraints?.fixedWidth == false : $0.constraints?.fixedHeight == false }.count
        let remaining = max(0, mainSize - fixedMain - spacing * Double(max(0, count - 1)))
        for index in node.children.indices {
            var child = node.children[index]
            let childMain = horizontal ? Double(child.frame.width) : Double(child.frame.height)
            let fill = horizontal ? child.constraints?.fixedWidth == false : child.constraints?.fixedHeight == false
            let main = fill && fillCount > 0 ? childMain + remaining / Double(fillCount) : childMain
            let cross = layout.alignment == .fill ? max(0.1, availableCross) : (horizontal ? Double(child.frame.height) : Double(child.frame.width))
            let crossOrigin: Double
            switch layout.alignment {
            case .leading, .fill: crossOrigin = horizontal ? pad.top : pad.left
            case .center: crossOrigin = (horizontal ? pad.top : pad.left) + (availableCross - cross) / 2
            case .trailing: crossOrigin = (horizontal ? node.frame.height - pad.bottom : node.frame.width - pad.right) - cross
            }
            if horizontal {
                child.frame.origin = CGPoint(x: CGFloat(cursor), y: CGFloat(crossOrigin))
                child.frame.size = CGSize(width: CGFloat(max(0.1, main)), height: CGFloat(cross))
            } else {
                child.frame.origin = CGPoint(x: CGFloat(crossOrigin), y: CGFloat(cursor))
                child.frame.size = CGSize(width: CGFloat(cross), height: CGFloat(max(0.1, main)))
            }
            node.children[index] = child
            cursor += main + spacing
        }
    }
}

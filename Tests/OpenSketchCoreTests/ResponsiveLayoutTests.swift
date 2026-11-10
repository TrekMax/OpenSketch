import Foundation
import Testing
@testable import OpenSketchCore

struct ResponsiveLayoutTests {
    @Test func pinnedChildTracksRightAndBottomWhenFrameGrows() throws {
        var child = DesignNode(kind: .rectangle, frame: CGRect(x: 240, y: 140, width: 40, height: 30))
        child.constraints = NodeConstraints(pinRight: true, pinBottom: true)
        let frame = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 320, height: 220), children: [child])
        let document = DesignDocument(pages: [DesignPage(nodes: [frame])])
        let resized = try ResponsiveLayoutEngine.applying(document, frameID: frame.id, newSize: CGSize(width: 420, height: 300))
        #expect(resized.node(id: child.id)?.frame.origin == CGPoint(x: 340, y: 220))
    }
}

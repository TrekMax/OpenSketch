import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct GradientTests {
    @Test func gradientRoundTripsThroughDocumentCodec() throws {
        let gradient = LinearGradient(stops: [
            GradientStop(position: 0, color: .black),
            GradientStop(position: 1, color: .white)
        ])
        var node = DesignNode(kind: .rectangle)
        node.style.linearGradient = gradient
        let document = DesignDocument(pages: [DesignPage(nodes: [node])])
        let decoded = try DocumentCodec.decode(DocumentCodec.encode(document))
        #expect(decoded.node(id: node.id)?.style.linearGradient == gradient)
    }

    @Test func invalidGradientStopsAreRejected() {
        var node = DesignNode(kind: .rectangle)
        node.style.linearGradient = LinearGradient(stops: [
            GradientStop(position: 0.8, color: .black),
            GradientStop(position: 0.2, color: .white)
        ])
        #expect(throws: DocumentCodecError.self) {
            try DocumentCodec.encode(DesignDocument(pages: [DesignPage(nodes: [node])]))
        }
    }
}

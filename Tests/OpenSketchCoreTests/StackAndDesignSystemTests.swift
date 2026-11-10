import Foundation
import Testing
@testable import OpenSketchCore

struct StackAndDesignSystemTests {
    @Test func verticalStackReflowsChildrenAndRoundTripsNewFields() throws {
        let first = DesignNode(name: "One", kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        let second = DesignNode(name: "Two", kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        var frame = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 200, height: 200), children: [first, second])
        frame.stackLayout = StackLayout(axis: .vertical, spacing: 10, padding: StackPadding(top: 4, left: 6))
        let document = DesignDocument(pages: [DesignPage(nodes: [frame])])
        let solved = try StackLayoutEngine.applying(document)
        let result = try #require(solved.pages[0].nodes[0])
        #expect(result.children[0].frame.origin == CGPoint(x: 6, y: 4))
        #expect(result.children[1].frame.origin == CGPoint(x: 6, y: 34))
        #expect(try DocumentCodec.decode(DocumentCodec.encode(solved)) == solved)
    }

    @Test func componentInstancesAndSharedStylesRemainEditable() throws {
        let source = DesignNode(name: "Button", kind: .rectangle)
        var document = DesignDocument(pages: [DesignPage(nodes: [source])])
        let definition = try document.makeComponentDefinition(from: source.id, name: "Button")
        let instance = try document.makeComponentInstance(definitionID: definition.id, in: document.pages[0].id, at: CGPoint(x: 200, y: 20))
        let shared = try document.makeSharedStyle(from: source.id, name: "Primary")
        try document.applySharedStyle(shared.id, to: instance.id)
        #expect(document.node(id: instance.id)?.componentDefinitionID == definition.id)
        #expect(document.node(id: instance.id)?.sharedStyleID == shared.id)
        #expect(document.componentDefinitions.count == 1)
        #expect(document.sharedStyles.count == 1)
    }
}

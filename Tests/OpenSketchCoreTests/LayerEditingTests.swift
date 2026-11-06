import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct LayerEditingTests {
    private func node(_ x: Double, _ y: Double = 0, _ width: Double = 20, _ height: Double = 20,
                      rotation: Double = 0) -> DesignNode {
        DesignNode(kind: .rectangle, frame: CGRect(x: x, y: y, width: width, height: height), rotation: rotation)
    }

    private func fixture(_ nodes: [DesignNode]) -> (DesignDocument, UUID) {
        let page = DesignPage(nodes: nodes)
        return (DesignDocument(pages: [page]), page.id)
    }

    private func edit(_ command: LayerCommand, _ document: DesignDocument, _ pageID: UUID,
                      _ nodes: [DesignNode]) throws -> LayerEditResult {
        try LayerEditing.apply(command, to: document, pageID: pageID, selection: Set(nodes.map(\.id)))
    }

    private func bounds(_ node: DesignNode, in document: DesignDocument) throws -> CGRect {
        let page = try #require(document.pages.first { $0.nodes.contains { $0.id == node.id } ||
            SceneGeometry.worldTransform(id: node.id, in: $0) != nil })
        let transform = try #require(SceneGeometry.worldTransform(id: node.id, in: page))
        return CGRect(origin: .zero, size: node.frame.size).applying(transform)
    }

    private func expectNear(_ actual: Double, _ expected: Double) {
        #expect(abs(actual - expected) < 0.000001)
    }

    @Test func groupAndUngroupUseParentCoordinatesAndPreserveIdentity() throws {
        let a = node(10, 20, 20, 30), b = node(70, 80, 40, 20)
        let (document, pageID) = fixture([a, b])
        let grouped = try edit(.group, document, pageID, [a, b])
        let group = try #require(grouped.document.pages[0].nodes.first)
        #expect(group.kind == .group)
        #expect(group.frame == CGRect(x: 10, y: 20, width: 100, height: 80))
        #expect(group.children.map(\.id) == [a.id, b.id])
        #expect(group.children.map(\.frame.origin) == [CGPoint.zero, CGPoint(x: 60, y: 60)])
        #expect(grouped.selection == [group.id])
        let ungrouped = try edit(.ungroup, grouped.document, pageID, [group])
        #expect(ungrouped.document == document)
        #expect(ungrouped.selection == [a.id, b.id])
        #expect(document.pages[0].nodes == [a, b])
    }

    @Test func groupingUsesTransformedBoundsAndTopmostSelectedPosition() throws {
        let a = node(10, 20, 20, 40, rotation: 90), gap = node(40), b = node(70, 80, 40, 20)
        let (document, pageID) = fixture([a, gap, b])
        let result = try edit(.group, document, pageID, [a, b])
        let group = try #require(result.document.pages[0].nodes.last)
        #expect(result.document.pages[0].nodes.map(\.id) == [gap.id, group.id])
        expectNear(group.frame.minX, 0)
        expectNear(group.frame.minY, 30)
        expectNear(group.frame.width, 110)
        expectNear(group.frame.height, 70)
        #expect(group.children[0].rotation == 90)
        try expectWorldPointsUnchanged(ids: [a.id, b.id], before: document, after: result.document)
    }

    private func expectWorldPointsUnchanged(ids: [UUID], before: DesignDocument,
                                            after: DesignDocument) throws {
        for id in ids {
            let original = try #require(before.node(id: id))
            let first = try #require(SceneGeometry.worldTransform(id: id, in: before.pages[0]))
            let second = try #require(SceneGeometry.worldTransform(id: id, in: after.pages[0]))
            for point in [CGPoint.zero, CGPoint(x: original.frame.width, y: 0),
                          CGPoint(x: original.frame.width / 3, y: original.frame.height / 4),
                          CGPoint(x: original.frame.width, y: original.frame.height)] {
                let old = point.applying(first), new = point.applying(second)
                expectNear(old.x, new.x); expectNear(old.y, new.y)
            }
        }
    }

    @Test func nestedRotationsSurviveGroupingAndUngrouping() throws {
        let grandchild = node(3, 7, 5, 8, rotation: -20)
        let child = DesignNode(kind: .group, frame: CGRect(x: 10, y: 20, width: 30, height: 40),
                               rotation: 31, children: [grandchild])
        let sibling = node(90, 60, 25, 50, rotation: -43)
        let group = DesignNode(kind: .group, frame: CGRect(x: 40, y: 50, width: 160, height: 150),
                               rotation: 67, children: [child, sibling])
        let outer = DesignNode(kind: .frame, frame: CGRect(x: 150, y: 70, width: 500, height: 400),
                               rotation: -28, children: [group])
        let (document, pageID) = fixture([outer])
        let ungrouped = try edit(.ungroup, document, pageID, [group])
        try expectWorldPointsUnchanged(ids: [child.id, grandchild.id, sibling.id], before: document,
                                      after: ungrouped.document)
        #expect(ungrouped.document.node(id: child.id)?.rotation == 98)
        #expect(ungrouped.document.node(id: grandchild.id) == grandchild)
        let regrouped = try edit(.group, ungrouped.document, pageID, [child, sibling])
        try expectWorldPointsUnchanged(ids: [child.id, grandchild.id, sibling.id], before: ungrouped.document,
                                      after: regrouped.document)
    }

    @Test(arguments: LayerAlignment.allCases) func alignUsesUnionOfWorldBounds(_ alignment: LayerAlignment) throws {
        let a = node(10, 20, 20, 30), b = node(70, 80, 40, 20)
        let (document, pageID) = fixture([a, b])
        let result = try edit(.align(alignment), document, pageID, [a, b])
        for id in [a.id, b.id] {
            let edited = try #require(result.document.node(id: id))
            switch alignment {
            case .left: expectNear(edited.frame.minX, 10)
            case .horizontalCenter: expectNear(edited.frame.midX, 60)
            case .right: expectNear(edited.frame.maxX, 110)
            case .top: expectNear(edited.frame.minY, 20)
            case .verticalCenter: expectNear(edited.frame.midY, 60)
            case .bottom: expectNear(edited.frame.maxY, 100)
            }
            #expect(edited.frame.size == document.node(id: id)?.frame.size)
        }
        #expect(result.selection == [a.id, b.id])
    }

    @Test func alignAcrossRotatedParentsConvertsWorldDeltaToLocalVector() throws {
        let a = node(10, 20, 20, 30, rotation: 25), b = node(70, 80, 40, 20, rotation: -13)
        let first = DesignNode(kind: .group, frame: CGRect(x: 50, y: 20, width: 200, height: 150),
                               rotation: 90, children: [a])
        let second = DesignNode(kind: .frame, frame: CGRect(x: 300, y: 10, width: 150, height: 200),
                                rotation: -30, children: [b])
        let (document, pageID) = fixture([first, second])
        let left = min(try bounds(a, in: document).minX, try bounds(b, in: document).minX)
        let result = try edit(.align(.left), document, pageID, [a, b])
        expectNear(try bounds(a, in: result.document).minX, left)
        expectNear(try bounds(b, in: result.document).minX, left)
        expectNear(try bounds(a, in: result.document).minY, try bounds(a, in: document).minY)
        expectNear(try bounds(b, in: result.document).minY, try bounds(b, in: document).minY)
        #expect(result.document.node(id: a.id)?.rotation == a.rotation)
    }

    @Test(arguments: LayerAxis.allCases) func distributeUsesEqualEdgeGaps(_ axis: LayerAxis) throws {
        let nodes = axis == .horizontal ? [node(0, 0, 20), node(40, 0, 30), node(100, 0, 40)] :
            [node(0, 0, 20, 20), node(0, 40, 20, 30), node(0, 100, 20, 40)]
        let (document, pageID) = fixture(nodes)
        let result = try edit(.distribute(axis), document, pageID, nodes)
        let middle = try #require(result.document.node(id: nodes[1].id))
        expectNear(axis == .horizontal ? middle.frame.minX : middle.frame.minY, 45)
        #expect(result.document.node(id: nodes[0].id) == nodes[0])
        #expect(result.document.node(id: nodes[2].id) == nodes[2])
    }

    @Test func distributionAllowsNegativeGapsAndUsesStableTieOrder() throws {
        let nodes = [node(0, 0, 100), node(10, 0, 100), node(30, 0, 100)]
        let (document, pageID) = fixture(nodes)
        let result = try edit(.distribute(.horizontal), document, pageID, nodes)
        #expect(result.document.node(id: nodes[1].id)?.frame.minX == 15)
        let tied = [node(0, 0, 20), node(0, 0, 30), node(0, 0, 40), node(100, 0, 10)]
        let (tieDocument, tiePage) = fixture(tied)
        let distributed = try edit(.distribute(.horizontal), tieDocument, tiePage, tied)
        expectNear(try #require(distributed.document.node(id: tied[1].id)).frame.minX, 20 + 10.0 / 3)
        expectNear(try #require(distributed.document.node(id: tied[2].id)).frame.minX, 50 + 20.0 / 3)
    }

    @Test func distributeAcrossRotatedParentsUsesWorldBoundsAndPreservesEndpoints() throws {
        let a = node(0, 0, 20), b = node(0, 0, 30), c = node(0, 0, 40)
        let parents = [a, b, c].enumerated().map { index, child in
            DesignNode(kind: .group, frame: CGRect(x: index * 100, y: index * 30, width: 80, height: 90),
                       rotation: Double(index * 30), children: [child])
        }
        let (document, pageID) = fixture(parents)
        let result = try edit(.distribute(.horizontal), document, pageID, [a, b, c])
        let first = try bounds(a, in: result.document), middle = try bounds(b, in: result.document)
        let last = try bounds(c, in: result.document)
        expectNear(middle.minX - first.maxX, last.minX - middle.maxX)
        #expect(result.document.node(id: a.id) == a)
        #expect(result.document.node(id: c.id) == c)
        expectNear(middle.minY, try bounds(b, in: document).minY)
    }

    @Test func orderMovesStableRunsAcrossOneUnselectedSibling() throws {
        let nodes = (0..<7).map { node(Double($0)) }
        let (document, pageID) = fixture(nodes)
        let selected = [nodes[1], nodes[2], nodes[4]]
        let cases: [(LayerOrder, [Int])] = [(.forward, [0, 3, 1, 2, 5, 4, 6]),
            (.backward, [1, 2, 0, 4, 3, 5, 6]), (.front, [0, 3, 5, 6, 1, 2, 4]),
            (.back, [1, 2, 4, 0, 3, 5, 6])]
        for (order, expected) in cases {
            let result = try edit(.order(order), document, pageID, selected)
            #expect(result.document.pages[0].nodes.map(\.id) == expected.map { nodes[$0].id })
            #expect(result.selection == Set(selected.map(\.id)))
        }
        let unchanged = try edit(.order(.front), document, pageID, [nodes[6]])
        #expect(unchanged.document == document)
    }

    @Test func childOrderStaysInsideParentAndMultipleGroupsUngroupInPlace() throws {
        let a = node(0), b = node(40), c = node(80), d = node(120), gap = node(150)
        let first = DesignNode(kind: .group, children: [a, b])
        let second = DesignNode(kind: .group, children: [c, d])
        let (document, pageID) = fixture([first, gap, second])
        let ordered = try edit(.order(.front), document, pageID, [a])
        #expect(ordered.document.node(id: first.id)?.children.map(\.id) == [b.id, a.id])
        #expect(ordered.document.pages[0].nodes.map(\.id) == [first.id, gap.id, second.id])
        let result = try edit(.ungroup, document, pageID, [first, second])
        #expect(result.document.pages[0].nodes.map(\.id) == [a.id, b.id, gap.id, c.id, d.id])
        #expect(result.selection == [a.id, b.id, c.id, d.id])
    }

    @Test func selectedAncestorsDeduplicateDescendantsBeforeEligibility() throws {
        var child = node(10); child.isLocked = true
        let parent = DesignNode(kind: .group, children: [child])
        let sibling = node(200)
        let (document, pageID) = fixture([parent, sibling])
        let result = try edit(.group, document, pageID, [parent, child, sibling])
        let group = try #require(result.document.pages[0].nodes.first)
        #expect(group.children.map(\.id) == [parent.id, sibling.id])
        #expect(result.document.node(id: child.id)?.isLocked == true)
        #expect(LayerEditing.canApply(.order(.front), to: document, pageID: pageID,
                                     selection: [parent.id, child.id]))
    }

    @Test func invalidSelectionAndCrossParentStructuralCommandsFailAtomically() throws {
        let a = node(0), b = node(100), parent = DesignNode(kind: .group)
        var containing = parent; containing.children = [b]
        let (document, pageID) = fixture([a, containing])
        for command in [LayerCommand.group, .ungroup, .order(.front)] {
            #expect(throws: LayerEditError.differentParents) { try edit(command, document, pageID, [a, b]) }
            #expect(!LayerEditing.canApply(command, to: document, pageID: pageID, selection: [a.id, b.id]))
        }
        for selection: Set<UUID> in [[], [UUID()], [a.id, UUID()]] {
            #expect(throws: LayerEditError.invalidSelection) {
                try LayerEditing.apply(.order(.front), to: document, pageID: pageID, selection: selection)
            }
        }
        #expect(throws: LayerEditError.invalidSelection) { try edit(.group, document, UUID(), [a, b]) }
        #expect(throws: LayerEditError.invalidSelection) { try edit(.group, document, pageID, [a]) }
        #expect(throws: LayerEditError.invalidSelection) { try edit(.align(.left), document, pageID, [a]) }
        #expect(throws: LayerEditError.invalidSelection) { try edit(.distribute(.vertical), document, pageID, [a, b]) }
        #expect(document.pages[0].nodes == [a, containing])
    }

    @Test(arguments: [true, false]) func lockedOrHiddenRootsAndAncestorsRejectChanges(_ hidden: Bool) throws {
        let child = node(10)
        let parent = DesignNode(kind: .group, isVisible: !hidden, isLocked: !hidden, children: [child])
        let (document, pageID) = fixture([parent])
        for selected in [child, parent] {
            #expect(throws: LayerEditError.lockedOrHidden) { try edit(.order(.front), document, pageID, [selected]) }
            #expect(!LayerEditing.canApply(.order(.front), to: document, pageID: pageID, selection: [selected.id]))
        }
    }

    @Test func ungroupRejectsStyledContainersAndNonGroups() throws {
        let child = node(0)
        for style in [NodeStyle(fill: .black), NodeStyle(stroke: .white), NodeStyle(opacity: 0.5)] {
            let group = DesignNode(kind: .group, style: style, children: [child])
            let (document, pageID) = fixture([group])
            #expect(throws: LayerEditError.styledGroup) { try edit(.ungroup, document, pageID, [group]) }
        }
        let clipped = DesignNode(kind: .group, clipsContent: true, children: [child])
        let (document, pageID) = fixture([clipped, child.cloned()])
        #expect(try edit(.ungroup, document, pageID, [clipped]).selection == [child.id])
        #expect(throws: LayerEditError.invalidSelection) { try edit(.ungroup, document, pageID, [child]) }
    }

    @Test func invalidAndOverflowingGeometryNeverEscapesCodecValidation() throws {
        var bad = node(0); bad.rotation = .infinity
        let (invalid, invalidPage) = fixture([bad])
        #expect(throws: LayerEditError.invalidGeometry) { try edit(.order(.front), invalid, invalidPage, [bad]) }
        #expect(!LayerEditing.canApply(.order(.front), to: invalid, pageID: invalidPage, selection: [bad.id]))
        let a = node(-1e9), b = node(1e9)
        let (document, pageID) = fixture([a, b])
        #expect(throws: LayerEditError.invalidGeometry) { try edit(.group, document, pageID, [a, b]) }
        #expect(!LayerEditing.canApply(.group, to: document, pageID: pageID, selection: [a.id, b.id]))
        #expect(document.pages[0].nodes == [a, b])
    }

    @Test func unpaintedGroupStyleAndHiddenDescendantsDoNotBlockUngroup() throws {
        var child = node(10); child.isVisible = false; child.isLocked = true
        let group = DesignNode(kind: .group, style: NodeStyle(strokeWidth: 20, cornerRadius: 15), children: [child])
        let (document, pageID) = fixture([group])
        #expect(LayerEditing.canApply(.ungroup, to: document, pageID: pageID, selection: [group.id, child.id]))
        let result = try edit(.ungroup, document, pageID, [group, child])
        #expect(result.selection == [child.id])
        #expect(result.document.pages[0].nodes == [child])
    }

    @Test func emptyGroupsUngroupToEmptySelectionAndBoundaryOrderingIsUnchanged() throws {
        let empty = DesignNode(kind: .group)
        let (document, pageID) = fixture([empty])
        let result = try edit(.ungroup, document, pageID, [empty])
        #expect(result.selection.isEmpty)
        #expect(result.document.pages[0].nodes.isEmpty)
        for order in LayerOrder.allCases {
            let unchanged = try edit(.order(order), document, pageID, [empty])
            #expect(unchanged.document == document)
            #expect(unchanged.selection == [empty.id])
        }
    }

    @Test func excessiveUngroupGeometryAndGroupDepthAreRejectedAtomically() throws {
        let child = node(1e9)
        let group = DesignNode(kind: .group, frame: CGRect(x: 1e9, y: 0, width: 100, height: 100), children: [child])
        let (document, pageID) = fixture([group])
        #expect(throws: LayerEditError.invalidGeometry) { try edit(.ungroup, document, pageID, [group]) }
        #expect(!LayerEditing.canApply(.ungroup, to: document, pageID: pageID, selection: [group.id]))
        #expect(document.pages[0].nodes == [group])
        let a = node(0), b = node(40)
        var deep = DesignNode(kind: .group, children: [a, b])
        for _ in 0..<62 { deep = DesignNode(kind: .group, children: [deep]) }
        let (deepDocument, deepPage) = fixture([deep])
        _ = try DocumentCodec.encode(deepDocument)
        #expect(throws: DocumentCodecError.limitExceeded("nodeDepth")) {
            try edit(.group, deepDocument, deepPage, [a, b])
        }
        #expect(!LayerEditing.canApply(.group, to: deepDocument, pageID: deepPage, selection: [a.id, b.id]))
    }

    @Test func selectionFromAnotherPageAndAncestorOnlyCardinalityAreInvalid() throws {
        let child = node(0), other = node(40)
        let parent = DesignNode(kind: .group, children: [child])
        let first = DesignPage(nodes: [parent]), second = DesignPage(nodes: [other])
        let document = DesignDocument(pages: [first, second])
        #expect(throws: LayerEditError.invalidSelection) { try edit(.align(.left), document, first.id, [child, other]) }
        #expect(throws: LayerEditError.invalidSelection) { try edit(.group, document, first.id, [parent, child]) }
    }

    @Test func eligibilityRejectsNegativeDimensionsWithoutEncoding() throws {
        var invalid = node(0)
        invalid.frame.size.width = -20
        let (document, pageID) = fixture([invalid])
        #expect(!LayerEditing.canApply(.order(.front), to: document, pageID: pageID, selection: [invalid.id]))
        #expect(throws: LayerEditError.invalidGeometry) { try edit(.order(.front), document, pageID, [invalid]) }
    }

    @Test func commandEligibilityIsPureAndSavedDocumentReopensWithGeometry() throws {
        let a = node(10, 20, 20, 30), b = node(70, 80, 40, 20)
        let (document, pageID) = fixture([a, b])
        let bytes = try DocumentCodec.encode(document)
        for _ in 0..<3 {
            #expect(LayerEditing.canApply(.group, to: document, pageID: pageID, selection: [a.id, b.id]))
        }
        #expect(try DocumentCodec.encode(document) == bytes)
        let result = try edit(.group, document, pageID, [a, b])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".opensketch")
        defer { try? FileManager.default.removeItem(at: url) }
        try DocumentCodec.save(result.document, to: url)
        #expect(try DocumentCodec.load(from: url) == result.document)
    }
}

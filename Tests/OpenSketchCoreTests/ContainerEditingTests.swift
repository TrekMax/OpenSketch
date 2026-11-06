import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct ContainerEditingTests {
    @Test func entersFrameWithoutVisualJumpAndReturnsToPage() throws {
        let frame = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 100, width: 300, height: 200))
        let a = DesignNode(kind: .rectangle, frame: CGRect(x: 140, y: 150, width: 20, height: 30))
        let page = DesignPage(nodes: [frame, a])
        let document = DesignDocument(pages: [page])
        #expect(ContainerEditing.dropTarget(in: page, selection: [a.id], at: CGPoint(x: 150, y: 160)) == frame.id)
        let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: frame.id)
        #expect(result.parentID(of: a.id) == frame.id)
        #expect(result.node(id: a.id)?.frame.origin == CGPoint(x: 40, y: 50))
        #expect(result.node(id: a.id)?.frame.size == a.frame.size)
        #expect(document.parentID(of: a.id) == nil)
        try expectWorldPoints(a.id, unchangedFrom: document, to: result)
        let outside = try ContainerEditing.reparenting(result, pageID: page.id, selection: [a.id], to: nil)
        #expect(outside.node(id: a.id) == a)
        #expect(outside.parentID(of: a.id) == nil)
    }

    @Test func rotatedParentsPreserveWorldPointsAndSubtree() throws {
        let child = DesignNode(kind: .ellipse, frame: CGRect(x: 4, y: 8, width: 10, height: 12), rotation: 17)
        let a = DesignNode(kind: .group, frame: CGRect(x: 20, y: 30, width: 20, height: 40), rotation: 15, children: [child])
        let parent = DesignNode(kind: .group, frame: CGRect(x: 100, y: 200, width: 100, height: 100), rotation: 90, children: [a])
        let target = DesignNode(kind: .frame, frame: CGRect(x: 300, y: 400, width: 200, height: 100), rotation: -90)
        let page = DesignPage(nodes: [parent, target]), document = DesignDocument(pages: [page])
        let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: target.id)
        let moved = try #require(result.node(id: a.id))
        #expect(abs(moved.frame.origin.x - 310) < 1e-8)
        #expect(abs(moved.frame.origin.y + 220) < 1e-8)
        #expect(abs(moved.rotation + 165) < 1e-8)
        #expect(moved.children == [child])
        try expectWorldPoints(a.id, unchangedFrom: document, to: result)
        try expectWorldPoints(child.id, unchangedFrom: document, to: result)
        let targetParent = DesignNode(kind: .group, frame: CGRect(x: -27, y: 62, width: 53, height: 71), rotation: 33, children: [target])
        let nestedPage = DesignPage(nodes: [parent, targetParent])
        let nestedDocument = DesignDocument(pages: [nestedPage])
        let nestedResult = try ContainerEditing.reparenting(nestedDocument, pageID: nestedPage.id, selection: [a.id], to: target.id)
        try expectWorldPoints(a.id, unchangedFrom: nestedDocument, to: nestedResult)
        try expectWorldPoints(child.id, unchangedFrom: nestedDocument, to: nestedResult)
    }

    @Test func sameNearestFramePreservesGroupAndNilPreservesRootGroup() throws {
        let a = DesignNode(kind: .rectangle)
        let group = DesignNode(kind: .group, children: [a])
        let frame = DesignNode(kind: .frame, children: [group])
        for (nodes, target) in [([frame], Optional(frame.id)), ([group], nil)] {
            let page = DesignPage(nodes: nodes), document = DesignDocument(pages: [page])
            let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: target)
            #expect(result == document)
            #expect(result.parentID(of: a.id) == group.id)
        }
    }

    @Test func crossFrameExtractsOnlySelectedRootAndAppendsInDrawingOrder() throws {
        let a = DesignNode(kind: .rectangle), b = DesignNode(kind: .ellipse), untouched = DesignNode(kind: .text)
        let group = DesignNode(kind: .group, children: [a, untouched])
        let source = DesignNode(kind: .frame, children: [group, b])
        let existing = DesignNode(kind: .rectangle)
        let target = DesignNode(kind: .frame, children: [existing])
        let page = DesignPage(nodes: [source, target]), document = DesignDocument(pages: [page])
        let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [b.id, a.id], to: target.id)
        #expect(result.node(id: target.id)?.children.map(\.id) == [existing.id, a.id, b.id])
        #expect(result.node(id: group.id)?.children == [untouched])
        try expectWorldPoints(a.id, unchangedFrom: document, to: result)
        try expectWorldPoints(b.id, unchangedFrom: document, to: result)
        let outside = try ContainerEditing.reparenting(result, pageID: page.id, selection: [b.id, a.id], to: nil)
        #expect(outside.pages[0].nodes.map(\.id) == [source.id, target.id, a.id, b.id])
    }

    @Test func selectedParentsNormalizeBeforeLockedDescendantEligibility() throws {
        let child = DesignNode(kind: .rectangle, isLocked: true)
        let group = DesignNode(kind: .group, children: [child])
        let target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [group, target]), document = DesignDocument(pages: [page])
        let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [group.id, child.id], to: target.id)
        #expect(result.node(id: target.id)?.children.map(\.id) == [group.id])
        #expect(result.node(id: group.id)?.children == [child])
        #expect(throws: LayerEditError.lockedOrHidden) {
            try ContainerEditing.reparenting(document, pageID: page.id, selection: [child.id], to: target.id)
        }
        #expect(ContainerEditing.dropTarget(in: page, selection: [group.id, child.id], at: CGPoint(x: 10, y: 10)) == target.id)
    }

    @Test func anySelectedFrameMakesWholeChangeNoOpAndEmptySelectionIsNoOp() throws {
        let a = DesignNode(kind: .rectangle), frame = DesignNode(kind: .frame), target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [frame, a, target]), document = DesignDocument(pages: [page])
        #expect(try ContainerEditing.reparenting(document, pageID: page.id, selection: [frame.id, a.id], to: target.id) == document)
        #expect(try ContainerEditing.reparenting(document, pageID: UUID(), selection: [], to: UUID()) == document)
    }

    @Test func invalidTargetAndSelectionRejectAtomically() throws {
        let descendant = DesignNode(kind: .frame)
        let group = DesignNode(kind: .group, children: [descendant])
        let leaf = DesignNode(kind: .rectangle), other = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [group, leaf]), anotherPage = DesignPage(nodes: [other])
        let document = DesignDocument(pages: [page, anotherPage])
        let bytes = try DocumentCodec.encode(document)
        for target in [UUID(), other.id, leaf.id, group.id, descendant.id] {
            #expect(throws: LayerEditError.invalidSelection) {
                try ContainerEditing.reparenting(document, pageID: page.id, selection: [group.id], to: target)
            }
        }
        for selection: Set<UUID> in [[UUID()], [leaf.id, UUID()], [other.id], [group.id, other.id]] {
            #expect(throws: LayerEditError.invalidSelection) {
                try ContainerEditing.reparenting(document, pageID: page.id, selection: selection, to: nil)
            }
            #expect(ContainerEditing.dropTarget(in: page, selection: selection, at: .zero) == nil)
        }
        #expect(throws: LayerEditError.invalidSelection) {
            try ContainerEditing.reparenting(document, pageID: UUID(), selection: [leaf.id], to: nil)
        }
        #expect(try DocumentCodec.encode(document) == bytes)
    }

    @Test(arguments: [true, false]) func lockedOrHiddenSourcesTargetsAndAncestorsReject(_ hidden: Bool) throws {
        let a = DesignNode(kind: .rectangle), target = DesignNode(kind: .frame)
        let blockedSource = DesignNode(kind: .group, isVisible: !hidden, isLocked: !hidden, children: [a])
        let blockedTarget = DesignNode(kind: .group, isVisible: !hidden, isLocked: !hidden, children: [target])
        for nodes in [[blockedSource, target], [a, blockedTarget]] {
            let page = DesignPage(nodes: nodes), document = DesignDocument(pages: [page])
            #expect(throws: LayerEditError.lockedOrHidden) {
                try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: target.id)
            }
            #expect(ContainerEditing.dropTarget(in: page, selection: [a.id], at: CGPoint(x: 10, y: 10)) == nil)
            #expect(document.pages[0].nodes == nodes)
        }
        let blocked = DesignNode(kind: .rectangle, isVisible: !hidden, isLocked: !hidden)
        let page = DesignPage(nodes: [a, blocked, target]), document = DesignDocument(pages: [page])
        #expect(throws: LayerEditError.lockedOrHidden) {
            try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id, blocked.id], to: target.id)
        }
        let blockedFrame = DesignNode(kind: .frame, isVisible: !hidden, isLocked: !hidden)
        let blockedPage = DesignPage(nodes: [a, blockedFrame]), blockedDocument = DesignDocument(pages: [blockedPage])
        #expect(throws: LayerEditError.lockedOrHidden) {
            try ContainerEditing.reparenting(blockedDocument, pageID: blockedPage.id, selection: [a.id], to: blockedFrame.id)
        }
    }

    @Test func invalidGeometryRejectsEverySourceAndTargetBeforeChangingAnything() throws {
        let good = DesignNode(kind: .rectangle), target = DesignNode(kind: .frame)
        var invalidNodes: [DesignNode] = []
        for value in [Double.nan, .infinity, -.infinity, 1e9 + 1, -1e9 - 1] {
            var position = good; position.frame.origin.x = value; invalidNodes.append(position)
            var rotation = good; rotation.rotation = value; invalidNodes.append(rotation)
        }
        for value in [Double.nan, .infinity, -1, 1e7 + 1] {
            var size = good; size.frame.size.width = value; invalidNodes.append(size)
        }
        for invalid in invalidNodes {
            let page = DesignPage(nodes: [invalid, target]), document = DesignDocument(pages: [page])
            #expect(throws: LayerEditError.invalidGeometry) {
                try ContainerEditing.reparenting(document, pageID: page.id, selection: [invalid.id], to: target.id)
            }
            #expect(ContainerEditing.dropTarget(in: page, selection: [invalid.id], at: CGPoint(x: 10, y: 10)) == nil)
            var invalidTarget = invalid; invalidTarget.kind = .frame
            let targetPage = DesignPage(nodes: [good.cloned(), invalidTarget])
            let sourceID = try #require(targetPage.nodes.first?.id)
            #expect(throws: LayerEditError.invalidGeometry) {
                try ContainerEditing.reparenting(DesignDocument(pages: [targetPage]), pageID: targetPage.id,
                                                selection: [sourceID], to: invalidTarget.id)
            }
        }
    }

    @Test(arguments: [-1.0, 1.0]) func convertedOriginsOutsideCodecLimitsRejectAtomically(_ sign: Double) throws {
        let a = DesignNode(kind: .rectangle, frame: CGRect(x: sign * 1e9, y: 0, width: 20, height: 30))
        let target = DesignNode(kind: .frame, frame: CGRect(x: -sign * 1e9, y: 0, width: 100, height: 100))
        let page = DesignPage(nodes: [a, target]), document = DesignDocument(pages: [page])
        let bytes = try DocumentCodec.encode(document)
        #expect(throws: LayerEditError.invalidGeometry) {
            try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: target.id)
        }
        #expect(try DocumentCodec.encode(document) == bytes)
    }

    @Test func targetUsesTopmostSubtreeThenDeepestFrameDespiteOrdinaryOverlays() {
        let source = DesignNode(kind: .rectangle)
        let deep = DesignNode(kind: .frame)
        let bottom = DesignNode(kind: .frame, children: [deep])
        let topFrame = DesignNode(kind: .frame)
        let topGroup = DesignNode(kind: .group, children: [topFrame])
        let overlay = DesignNode(kind: .rectangle)
        let point = CGPoint(x: 20, y: 20)
        #expect(ContainerEditing.dropTarget(in: DesignPage(nodes: [bottom, topGroup, overlay, source]), selection: [source.id], at: point) == topFrame.id)
        #expect(ContainerEditing.dropTarget(in: DesignPage(nodes: [bottom, overlay, source]), selection: [source.id], at: point) == deep.id)
        #expect(ContainerEditing.dropTarget(in: DesignPage(nodes: [bottom, overlay, source]), selection: [source.id], at: CGPoint(x: 120, y: 20)) == nil)
    }

    @Test func selectedSubtreesAreExcludedButTheirLegalAncestorsRemainTargets() {
        let descendant = DesignNode(kind: .frame)
        let selected = DesignNode(kind: .group, children: [descendant])
        let ancestor = DesignNode(kind: .frame, children: [selected])
        let page = DesignPage(nodes: [ancestor])
        #expect(ContainerEditing.dropTarget(in: page, selection: [selected.id], at: CGPoint(x: 20, y: 20)) == ancestor.id)
    }

    @Test func rotatedBoundsAndClippingDetermineTargetEligibility() {
        let source = DesignNode(kind: .rectangle)
        let rotated = DesignNode(kind: .frame, frame: CGRect(x: 100, y: 100, width: 100, height: 20), rotation: 90)
        let page = DesignPage(nodes: [rotated, source])
        #expect(ContainerEditing.dropTarget(in: page, selection: [source.id], at: CGPoint(x: 150, y: 70)) == rotated.id)
        #expect(ContainerEditing.dropTarget(in: page, selection: [source.id], at: CGPoint(x: 110, y: 110)) == nil)
        let outside = DesignNode(kind: .frame, frame: CGRect(x: 80, y: 80, width: 100, height: 100))
        var clip = DesignNode(kind: .frame, clipsContent: true, children: [outside])
        var clippedPage = DesignPage(nodes: [clip, source])
        #expect(ContainerEditing.dropTarget(in: clippedPage, selection: [source.id], at: CGPoint(x: 120, y: 120)) == nil)
        #expect(ContainerEditing.dropTarget(in: clippedPage, selection: [source.id], at: CGPoint(x: 90, y: 90)) == outside.id)
        clip.clipsContent = false; clippedPage.nodes[0] = clip
        #expect(ContainerEditing.dropTarget(in: clippedPage, selection: [source.id], at: CGPoint(x: 120, y: 120)) == outside.id)
    }

    @Test func invalidDropParametersNeverProduceTarget() {
        let source = DesignNode(kind: .rectangle), target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [source, target])
        for point in [CGPoint(x: CGFloat.nan, y: 10), CGPoint(x: 10, y: CGFloat.infinity), CGPoint(x: 1e9 + 1, y: 0)] {
            #expect(ContainerEditing.dropTarget(in: page, selection: [source.id], at: point) == nil)
        }
        #expect(ContainerEditing.dropTarget(in: page, selection: [], at: .zero) == nil)
    }

    @Test func savedReopenedDocumentRetainsIDsGeometryAndHierarchy() throws {
        let a = DesignNode(kind: .rectangle), target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [a, target]), document = DesignDocument(pages: [page])
        let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: target.id)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".opensketch")
        defer { try? FileManager.default.removeItem(at: url) }
        try DocumentCodec.save(result, to: url)
        let reopened = try DocumentCodec.load(from: url)
        #expect(reopened == result)
        #expect(reopened.parentID(of: a.id) == target.id)
        #expect(reopened.version == 1)
    }

    @Test func maximumLegalDepthRemainsEditableAndExcessiveResultDepthIsAtomic() throws {
        let a = DesignNode(kind: .rectangle)
        var deep = a
        for _ in 0..<63 { deep = DesignNode(kind: .group, children: [deep]) }
        let target = DesignNode(kind: .frame)
        let page = DesignPage(nodes: [deep, target]), document = DesignDocument(pages: [page])
        _ = try DocumentCodec.encode(document)
        #expect(try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: nil) == document)
        #expect(ContainerEditing.dropTarget(in: page, selection: [a.id], at: CGPoint(x: 20, y: 20)) == target.id)

        var deepTarget = target
        for _ in 0..<62 { deepTarget = DesignNode(kind: .group, children: [deepTarget]) }
        let group = DesignNode(kind: .group, children: [a])
        let overflowPage = DesignPage(nodes: [group, deepTarget])
        let overflowDocument = DesignDocument(pages: [overflowPage])
        let bytes = try DocumentCodec.encode(overflowDocument)
        #expect(throws: DocumentCodecError.limitExceeded("nodeDepth")) {
            try ContainerEditing.reparenting(overflowDocument, pageID: overflowPage.id, selection: [group.id], to: target.id)
        }
        #expect(try DocumentCodec.encode(overflowDocument) == bytes)
    }

    @Test func invalidAncestorGeometryAndFinalCodecValidationRejectAtomically() throws {
        let a = DesignNode(kind: .rectangle), target = DesignNode(kind: .frame)
        let invalidParent = DesignNode(kind: .group, rotation: .infinity, children: [a])
        let invalidTargetParent = DesignNode(kind: .group, rotation: .infinity, children: [target])
        for nodes in [[invalidParent, target], [a, invalidTargetParent]] {
            let page = DesignPage(nodes: nodes), document = DesignDocument(pages: [page])
            #expect(throws: LayerEditError.invalidGeometry) {
                try ContainerEditing.reparenting(document, pageID: page.id, selection: [a.id], to: target.id)
            }
            #expect(ContainerEditing.dropTarget(in: page, selection: [a.id], at: CGPoint(x: 20, y: 20)) == nil)
        }
        let invalidChild = DesignNode(kind: .rectangle, style: NodeStyle(opacity: 2))
        let group = DesignNode(kind: .group, children: [invalidChild])
        let page = DesignPage(nodes: [group, target]), document = DesignDocument(pages: [page])
        #expect(throws: DocumentCodecError.invalidContent("opacity")) {
            try ContainerEditing.reparenting(document, pageID: page.id, selection: [group.id], to: target.id)
        }
        #expect(document.pages[0].nodes == [group, target])
    }

    @Test func mixedSelectionKeepsExistingGroupsAndAppendsOnlyChangedRoots() throws {
        let staying = DesignNode(kind: .rectangle), entering = DesignNode(kind: .ellipse)
        let group = DesignNode(kind: .group, children: [staying])
        let target = DesignNode(kind: .frame, children: [group])
        let page = DesignPage(nodes: [entering, target]), document = DesignDocument(pages: [page])
        let result = try ContainerEditing.reparenting(document, pageID: page.id, selection: [staying.id, entering.id], to: target.id)
        #expect(result.node(id: target.id)?.children.map(\.id) == [group.id, entering.id])
        #expect(result.node(id: group.id) == group)
        #expect(result.parentID(of: staying.id) == group.id)
    }

    private func expectWorldPoints(_ id: UUID, unchangedFrom original: DesignDocument,
                                   to result: DesignDocument) throws {
        let before = try #require(SceneGeometry.worldTransform(id: id, in: original.pages[0]))
        let after = try #require(SceneGeometry.worldTransform(id: id, in: result.pages[0]))
        let size = try #require(original.node(id: id)?.frame.size)
        for point in [CGPoint.zero, CGPoint(x: size.width, y: 0),
                      CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height),
                      CGPoint(x: size.width * 0.37, y: size.height * 0.63)] {
            let a = point.applying(before), b = point.applying(after)
            #expect(abs(a.x - b.x) < 1e-7)
            #expect(abs(a.y - b.y) < 1e-7)
        }
    }
}

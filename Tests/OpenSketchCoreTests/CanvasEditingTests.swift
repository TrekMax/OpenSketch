import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct CanvasEditingTests {
    private func node(_ x: CGFloat, _ y: CGFloat = 0, _ width: CGFloat = 20, _ height: CGFloat = 20,
                      rotation: Double = 0) -> DesignNode {
        DesignNode(kind: .rectangle, frame: CGRect(x: x, y: y, width: width, height: height), rotation: rotation)
    }

    private func near(_ actual: CGFloat, _ expected: CGFloat) {
        #expect(abs(actual - expected) < 0.000001, "actual: \(actual), expected: \(expected)")
    }

    @Test func marqueeRequiresContainmentAndNormalizesReverseDrag() {
        let a = node(0), b = node(100, 80, 40, 40)
        let page = DesignPage(nodes: [a, b])
        #expect(CanvasEditing.marqueeSelection(in: page, rect: CGRect(x: -1, y: -1, width: 22, height: 22)) == [a.id])
        #expect(CanvasEditing.marqueeSelection(in: page, rect: CGRect(x: 21, y: 21, width: -22, height: -22)) == [a.id])
        #expect(CanvasEditing.marqueeSelection(in: page, rect: CGRect(x: 10, y: 10, width: 20, height: 20)).isEmpty)
    }

    @Test func marqueeTreatsGroupsAsUnitsAndDescendsIntoPartialFrames() {
        let child = node(10, 10)
        let group = DesignNode(kind: .group, clipsContent: true, children: [child])
        let frame = DesignNode(kind: .frame, children: [child])
        let rect = CGRect(x: 9, y: 9, width: 22, height: 22)
        #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [group]), rect: rect).isEmpty)
        #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [frame]), rect: rect) == [child.id])
        #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [frame]), rect: CGRect(x: -1, y: -1, width: 102, height: 102)) == [frame.id])
        let outside = node(120)
        let unclippedGroup = DesignNode(kind: .group, frame: CGRect(x: 0, y: 0, width: 10, height: 10), clipsContent: true, children: [outside])
        let selection = CanvasEditing.marqueeSelection(in: DesignPage(nodes: [unclippedGroup]), rect: CGRect(x: -1, y: -1, width: 12, height: 12))
        #expect(selection == [unclippedGroup.id])
    }

    @Test func marqueeUsesPolygonIntersectionRatherThanAncestorBoundingBoxes() {
        // Parent is a diamond. Counter-rotation makes the child's world frame
        // x=90...130, y=0...40; clipping leaves x=90...110.710678, y=19.289322...40.
        let child = node(51.21320343559643, -33.63961030678928, 40, 40, rotation: -45)
        let frame = DesignNode(kind: .frame, rotation: 45, clipsContent: true, children: [child])
        let page = DesignPage(nodes: [frame])
        #expect(CanvasEditing.marqueeSelection(in: page, rect: CGRect(x: 89, y: 19, width: 23, height: 22)) == [child.id])
        #expect(CanvasEditing.marqueeSelection(in: page, rect: CGRect(x: 89, y: 20, width: 23, height: 21)).isEmpty)
        // World frame 100...110 × 0...10 sits inside the ancestor AABB,
        // yet entirely outside its diamond, so it has no selectable geometry.
        let outside = node(52.071067811865476, -25.710678118654755, 10, 10, rotation: -45)
        var emptyClip = frame; emptyClip.children = [outside]
        #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [emptyClip]), rect: CGRect(x: 99, y: -1, width: 12, height: 12)).isEmpty)
    }

    @Test func marqueeIntersectsEveryAncestorClip() {
        let child = node(40, 30, 30, 10)
        let inner = DesignNode(kind: .frame, frame: CGRect(x: 50, y: 50, width: 100, height: 100), clipsContent: true, children: [child])
        let outer = DesignNode(kind: .frame, clipsContent: true, children: [inner])
        // Child's full bounds are 90...120 × 80...90; outer clipping leaves 90...100.
        #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [outer]), rect: CGRect(x: 89, y: 79, width: 12, height: 12)) == [child.id])
        #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [outer]), rect: CGRect(x: 91, y: 79, width: 10, height: 12)).isEmpty)
    }

    @Test func marqueeRejectsHiddenLockedAndInvalidGeometry() {
        let child = node(10)
        let hidden = DesignNode(kind: .frame, isVisible: false, children: [child])
        let locked = DesignNode(kind: .frame, isLocked: true, children: [child.cloned()])
        let zero = node(0, 0, 0, 20)
        var invalid = node(0); invalid.rotation = .nan
        let page = DesignPage(nodes: [hidden, locked, zero, invalid])
        #expect(CanvasEditing.marqueeSelection(in: page, rect: CGRect(x: -100, y: -100, width: 1000, height: 1000)).isEmpty)
        for rect in [CGRect.zero, CGRect.null, CGRect.infinite, CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20)] {
            #expect(CanvasEditing.marqueeSelection(in: DesignPage(nodes: [child]), rect: rect).isEmpty)
        }
    }

    @Test func translationUsesPageAxesAndPreservesIdentity() throws {
        let a = node(10, 20, 30, 40)
        let page = DesignPage(nodes: [a])
        let original = DesignDocument(pages: [page])
        let moved = try CanvasEditing.translating(original, pageID: page.id, selection: [a.id], by: CGSize(width: 1, height: -10))
        #expect(moved.node(id: a.id)?.frame.origin == CGPoint(x: 11, y: 10))
        #expect(original.node(id: a.id)?.frame.origin == CGPoint(x: 10, y: 20))
        #expect(moved.id == original.id)
        #expect(moved.pages[0].id == page.id)
        #expect(moved.node(id: a.id)?.style == a.style)
    }

    @Test func translationConvertsVectorsThroughRotatedParentsAndDeduplicatesChildren() throws {
        let a = node(10, 20), b = node(30, 40)
        let first = DesignNode(kind: .group, frame: CGRect(x: 100, y: 200, width: 100, height: 100), rotation: 90, children: [a])
        let second = DesignNode(kind: .frame, frame: CGRect(x: 300, y: 400, width: 100, height: 100), rotation: -90, children: [b])
        let page = DesignPage(nodes: [first, second]), delta = CGSize(width: 3, height: -7)
        let document = DesignDocument(pages: [page])
        let moved = try CanvasEditing.translating(document, pageID: page.id, selection: [a.id, b.id], by: delta)
        let movedA = try #require(moved.node(id: a.id)), movedB = try #require(moved.node(id: b.id))
        near(movedA.frame.minX, 3); near(movedA.frame.minY, 17)
        near(movedB.frame.minX, 37); near(movedB.frame.minY, 43)
        var lockedA = a; lockedA.isLocked = true
        var containing = first; containing.children = [lockedA]
        let nested = DesignDocument(pages: [DesignPage(nodes: [containing])])
        let deduplicated = try CanvasEditing.translating(nested, pageID: nested.pages[0].id, selection: [first.id, a.id], by: delta)
        #expect(deduplicated.node(id: a.id) == lockedA)
        #expect(deduplicated.node(id: first.id)?.frame.origin == CGPoint(x: 103, y: 193))
    }

    @Test func translationValidatesWholeSelectionAndFailsAtomically() throws {
        let a = node(0), edge = node(1e9), foreign = node(50)
        let page = DesignPage(nodes: [a, edge]), other = DesignPage(nodes: [foreign])
        let document = DesignDocument(pages: [page, other])
        #expect(throws: LayerEditError.invalidSelection) { try CanvasEditing.translating(document, pageID: page.id, selection: [a.id, foreign.id], by: .zero) }
        #expect(throws: LayerEditError.invalidSelection) { try CanvasEditing.translating(document, pageID: UUID(), selection: [a.id], by: .zero) }
        #expect(throws: LayerEditError.invalidGeometry) { try CanvasEditing.translating(document, pageID: page.id, selection: [a.id, edge.id], by: CGSize(width: 1, height: 0)) }
        #expect(throws: LayerEditError.invalidGeometry) { try CanvasEditing.translating(document, pageID: page.id, selection: [a.id], by: CGSize(width: CGFloat.infinity, height: 0)) }
        #expect(document.pages[0].nodes == [a, edge])
        #expect(try CanvasEditing.translating(document, pageID: page.id, selection: [a.id], by: .zero) == document)
        #expect(try CanvasEditing.translating(document, pageID: UUID(), selection: [], by: CGSize(width: CGFloat.nan, height: 0)) == document)
    }

    @Test(arguments: [true, false]) func translationRejectsHiddenOrLockedRootAndAncestor(_ hidden: Bool) {
        let child = node(10), free = node(200)
        let parent = DesignNode(kind: .frame, isVisible: !hidden, isLocked: !hidden, children: [child])
        let page = DesignPage(nodes: [parent, free])
        let original = DesignDocument(pages: [page])
        for id in [parent.id, child.id] {
            #expect(throws: LayerEditError.lockedOrHidden) { try CanvasEditing.translating(original, pageID: page.id, selection: [free.id, id], by: CGSize(width: 1, height: 1)) }
        }
    }

    @Test func snapEdgesAndGuidesUseCorrectedBoundsAndRemainPure() {
        let a = node(0), b = node(100, 80, 40, 40), page = DesignPage(nodes: [])
        var original = page; original.nodes = [a, b]
        let result = CanvasEditing.snapMovement(in: original, selection: [a.id], translation: CGSize(width: 78, height: 58), tolerance: 3)
        #expect(result.translation == CGSize(width: 80, height: 60))
        #expect(result.guides == [SnapGuide(start: CGPoint(x: 100, y: 60), end: CGPoint(x: 100, y: 120)), SnapGuide(start: CGPoint(x: 80, y: 80), end: CGPoint(x: 140, y: 80))])
        #expect(CanvasEditing.snapMovement(in: original, selection: [a.id], translation: CGSize(width: 76, height: 56), tolerance: 3) == MovementSnap(translation: CGSize(width: 76, height: 56), guides: []))
        #expect(original.nodes == [a, b])
    }

    @Test func snapUsesCentersAndStableSceneThenAnchorOrder() {
        let a = node(0), center = node(100, 200, 40, 40)
        let centered = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, center]), selection: [a.id], translation: CGSize(width: 109, height: 100), tolerance: 2)
        #expect(centered.translation == CGSize(width: 110, height: 100))
        #expect(centered.guides.first?.start.x == 120)
        let left = node(38, 200), right = node(62, 200)
        let tied = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, left, right]), selection: [a.id], translation: CGSize(width: 40, height: 100), tolerance: 2)
        #expect(tied.translation.width == 38)
        let reversed = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, right, left]), selection: [a.id], translation: CGSize(width: 40, height: 100), tolerance: 2)
        #expect(reversed.translation.width == 42)
        let anchorTie = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, node(48, 200, 20, 20)]), selection: [a.id], translation: CGSize(width: 40, height: 100), tolerance: 2)
        #expect(anchorTie.translation.width == 38)
        #expect(anchorTie.guides.first?.start.x == 48)
        let movingAnchorTie = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, node(45, 200)]), selection: [a.id], translation: CGSize(width: 40, height: 100), tolerance: 5)
        #expect(movingAnchorTie.translation.width == 45)
        #expect(movingAnchorTie.guides.first?.start.x == 45)
    }

    @Test func snapAllowsLockedReferencesButExcludesHiddenAncestorsAndSelectedSubtrees() {
        let a = node(0), child = node(30, 200)
        let parent = DesignNode(kind: .frame, frame: CGRect(x: 0, y: 0, width: 20, height: 20), children: [a, child])
        let selected = CanvasEditing.snapMovement(in: DesignPage(nodes: [parent]), selection: [parent.id, a.id], translation: CGSize(width: 9, height: 99), tolerance: 3)
        #expect(selected.guides.isEmpty)
        let nested = CanvasEditing.snapMovement(in: DesignPage(nodes: [parent]), selection: [a.id], translation: CGSize(width: 1, height: 99), tolerance: 2)
        #expect(nested.guides.isEmpty)
        var reference = node(100, 80, 40, 40); reference.isLocked = true
        #expect(CanvasEditing.snapMovement(in: DesignPage(nodes: [a, reference]), selection: [a.id], translation: CGSize(width: 78, height: 58), tolerance: 3).translation == CGSize(width: 80, height: 60))
        let hidden = DesignNode(kind: .frame, isVisible: false, children: [reference])
        #expect(CanvasEditing.snapMovement(in: DesignPage(nodes: [a, hidden]), selection: [a.id], translation: CGSize(width: 78, height: 58), tolerance: 3).guides.isEmpty)
    }

    @Test func snapUsesClippedReferenceAndFullMovingGeometry() {
        let a = node(200, 200, 2, 2)
        let child = node(51.21320343559643, -33.63961030678928, 40, 40, rotation: -45)
        let frame = DesignNode(kind: .frame, rotation: 45, clipsContent: true, children: [child])
        let result = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, frame]), selection: [a.id], translation: CGSize(width: -90, height: -181), tolerance: 1)
        near(result.translation.width, -90.28932188134524)
        near(result.translation.height, -180.71067811865476)
        // Selected child's full bounds have x=90...130, even though clipped at x=110.71.
        let reference = node(150, 200, 20, 20)
        let moved = CanvasEditing.snapMovement(in: DesignPage(nodes: [frame, reference]), selection: [child.id], translation: CGSize(width: 18, height: 100), tolerance: 3)
        near(moved.translation.width, 20)
    }

    @Test func snapUsesSelectionUnionAndIgnoresGroupClippingFlags() {
        let a = node(0), b = node(100, 30)
        let reference = node(200, 200)
        let page = DesignPage(nodes: [a, b, reference])
        let result = CanvasEditing.snapMovement(in: page, selection: [a.id, b.id], translation: CGSize(width: 78, height: 100), tolerance: 3)
        #expect(result.translation == CGSize(width: 80, height: 100))
        #expect(result.guides == [SnapGuide(start: CGPoint(x: 200, y: 100), end: CGPoint(x: 200, y: 220))])
        let outside = node(100, 80, 40, 40)
        let group = DesignNode(kind: .group, frame: CGRect(x: 0, y: 0, width: 10, height: 10), clipsContent: true, children: [outside])
        let groupedReference = CanvasEditing.snapMovement(in: DesignPage(nodes: [a, group]), selection: [a.id], translation: CGSize(width: 78, height: 58), tolerance: 3)
        #expect(groupedReference.translation == CGSize(width: 80, height: 60))
    }

    @Test func invalidRootOrAncestorGeometryRejectsTranslationAndSnapping() {
        let a = node(0), reference = node(100, 80, 40, 40), raw = CGSize(width: 78, height: 58)
        var invalid = a; invalid.frame.size.width = -1
        var invalidRotation = a; invalidRotation.rotation = .infinity
        var invalidOrigin = a; invalidOrigin.frame.origin.x = .nan
        let invalidParent = DesignNode(kind: .frame, rotation: .nan, children: [a])
        for nodes in [[invalid, reference], [invalidRotation, reference], [invalidOrigin, reference], [invalidParent, reference]] {
            let page = DesignPage(nodes: nodes)
            let original = DesignDocument(pages: [page])
            #expect(throws: LayerEditError.invalidGeometry) { try CanvasEditing.translating(original, pageID: page.id, selection: [a.id], by: CGSize(width: 1, height: 1)) }
            #expect(CanvasEditing.snapMovement(in: page, selection: [a.id], translation: raw, tolerance: 3) == MovementSnap(translation: raw, guides: []))
        }
        let locked = DesignNode(kind: .frame, isLocked: true, children: [a])
        #expect(CanvasEditing.snapMovement(in: DesignPage(nodes: [locked, reference]), selection: [a.id], translation: raw, tolerance: 3) == MovementSnap(translation: raw, guides: []))
    }

    @Test func snapToleranceConvertsScreenThresholdAndInvalidInputsReturnRawValue() {
        let a = node(0), b = node(100, 80, 40, 40), raw = CGSize(width: 72, height: 52)
        let page = DesignPage(nodes: [a, b])
        #expect(CanvasEditing.snapMovement(in: page, selection: [a.id], translation: raw, tolerance: 12).translation == CGSize(width: 80, height: 60))
        #expect(CanvasEditing.snapMovement(in: page, selection: [a.id], translation: raw, tolerance: 3).translation == raw)
        for selection: Set<UUID> in [[], [UUID()], [a.id, UUID()]] {
            #expect(CanvasEditing.snapMovement(in: page, selection: selection, translation: raw, tolerance: 12) == MovementSnap(translation: raw, guides: []))
        }
        for tolerance: CGFloat in [-1, .nan, .infinity] {
            #expect(CanvasEditing.snapMovement(in: page, selection: [a.id], translation: raw, tolerance: tolerance) == MovementSnap(translation: raw, guides: []))
        }
        let invalid = CanvasEditing.snapMovement(in: page, selection: [a.id], translation: CGSize(width: CGFloat.infinity, height: 0), tolerance: 3)
        #expect(invalid.translation.width == .infinity && invalid.guides.isEmpty)
    }
}

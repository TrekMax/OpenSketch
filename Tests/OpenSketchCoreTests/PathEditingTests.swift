import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct PathEditingTests {
    @Test func geometryNormalizesPagePointsIntoNodeLocalCoordinates() throws {
        let geometry = try PathEditing.geometry(points: [CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90), CGPoint(x: 40, y: 50)], closed: true)
        #expect(geometry.frame == CGRect(x: 20, y: 30, width: 60, height: 60))
        #expect(geometry.path.commands == [
            .move(to: CGPoint(x: 0, y: 0)),
            .line(to: CGPoint(x: 60, y: 60)),
            .line(to: CGPoint(x: 20, y: 20)),
            .close
        ])
    }

    @Test func penOperationsAppendAndCloseOnlyOpenSubpaths() throws {
        var path = VectorPath(commands: [.move(to: CGPoint(x: 0, y: 0))])
        path = try PathEditing.appendLine(to: CGPoint(x: 10, y: 0), in: path)
        path = try PathEditing.appendLine(to: CGPoint(x: 10, y: 10), in: path)
        path = try PathEditing.close(path)
        #expect(path.commands.count == 4)
        #expect(throws: PathEditingError.invalidSequence) { try PathEditing.appendLine(to: .zero, in: path) }
        #expect(throws: PathEditingError.invalidSequence) { try PathEditing.close(path) }
    }

    @Test func nodeEditingMovesCubicControlsAndDestinations() throws {
        let path = VectorPath(commands: [
            .move(to: .zero),
            .cubic(control1: CGPoint(x: 10, y: 0), control2: CGPoint(x: 20, y: 10), to: CGPoint(x: 30, y: 0))
        ])
        let movedControl = try PathEditing.movePoint(PathPointReference(commandIndex: 1, role: .control1), to: CGPoint(x: 12, y: 2), in: path)
        #expect(movedControl.commands[1] == .cubic(control1: CGPoint(x: 12, y: 2), control2: CGPoint(x: 20, y: 10), to: CGPoint(x: 30, y: 0)))
        let movedDestination = try PathEditing.movePoint(PathPointReference(commandIndex: 1), to: CGPoint(x: 40, y: 0), in: movedControl)
        #expect(movedDestination.commands[1] == .cubic(control1: CGPoint(x: 12, y: 2), control2: CGPoint(x: 20, y: 10), to: CGPoint(x: 40, y: 0)))
    }

    @Test func lineCanBecomeCubicWithoutChangingItsDestination() throws {
        let path = VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 40, y: 0))])
        let curved = try PathEditing.replaceLineWithCubic(
            at: 1,
            control1: CGPoint(x: 10, y: 20),
            control2: CGPoint(x: 30, y: -20),
            in: path
        )
        #expect(curved.commands[1] == .cubic(control1: CGPoint(x: 10, y: 20), control2: CGPoint(x: 30, y: -20), to: CGPoint(x: 40, y: 0)))
    }

    @Test func nodesCanBeInsertedAndRemovedAtomically() throws {
        let path = VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 40, y: 0)), .line(to: CGPoint(x: 40, y: 40))])
        let inserted = try PathEditing.insertLine(after: 1, to: CGPoint(x: 20, y: 10), in: path)
        #expect(inserted.commands[2] == .line(to: CGPoint(x: 20, y: 10)))
        let removed = try PathEditing.removeCommands(at: [1, 2], from: inserted)
        #expect(removed.commands == [.move(to: .zero), .line(to: CGPoint(x: 40, y: 40))])
        #expect(throws: PathEditingError.cannotRemoveMove) { try PathEditing.removeCommands(at: [0], from: path) }
    }

    @Test func handleModesKeepHandlesFreeAlignedOrMirrored() throws {
        let path = VectorPath(commands: [
            .move(to: .zero),
            .cubic(control1: CGPoint(x: 10, y: 0), control2: CGPoint(x: 30, y: 0), to: CGPoint(x: 40, y: 0)),
            .cubic(control1: CGPoint(x: 50, y: 0), control2: CGPoint(x: 70, y: 0), to: CGPoint(x: 80, y: 0))
        ])
        let free = try PathEditing.moveHandle(PathPointReference(commandIndex: 1, role: .control2), to: CGPoint(x: 30, y: 20), mode: .free, in: path)
        #expect(PathEditingTestSupport.point(.control1, command: free.commands[2]) == CGPoint(x: 50, y: 0))
        let mirrored = try PathEditing.moveHandle(PathPointReference(commandIndex: 1, role: .control2), to: CGPoint(x: 30, y: 20), mode: .mirrored, in: path)
        #expect(PathEditingTestSupport.point(.control1, command: mirrored.commands[2]) == CGPoint(x: 50, y: -20))
        let closed = try PathEditing.togglingClosed(path)
        #expect(closed.commands.last == .close)
        #expect(try PathEditing.togglingClosed(closed) == path)
    }

    private enum PathEditingTestSupport {
        static func point(_ role: PathPointRole, command: PathCommand) -> CGPoint? {
            switch (role, command) {
            case (.control1, let .cubic(control1, _, _)): return control1
            case (.control2, let .cubic(_, control2, _)): return control2
            default: return nil
            }
        }
    }

    @Test func invalidPathEditsAreRejectedWithoutChangingInput() throws {
        let path = VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 10, y: 0))])
        #expect(throws: PathEditingError.cannotRemoveMove) { try PathEditing.removeCommand(at: 0, from: path) }
        #expect(throws: PathEditingError.invalidCommandIndex) { try PathEditing.movePoint(PathPointReference(commandIndex: 3), to: .zero, in: path) }
        #expect(throws: PathEditingError.invalidPointRole) { try PathEditing.movePoint(PathPointReference(commandIndex: 1, role: .control1), to: .zero, in: path) }
        #expect(throws: PathEditingError.invalidGeometry) { try PathEditing.geometry(points: [CGPoint(x: CGFloat.nan, y: 0)]) }
        #expect(path.commands.count == 2)
    }
}

import Foundation
import CoreGraphics
import Testing
@testable import OpenSketchCore

struct BooleanEditingTests {
    private func square(_ origin: CGPoint, _ size: CGFloat) -> VectorPath {
        VectorPath(commands: [
            .move(to: origin),
            .line(to: CGPoint(x: origin.x + size, y: origin.y)),
            .line(to: CGPoint(x: origin.x + size, y: origin.y + size)),
            .line(to: CGPoint(x: origin.x, y: origin.y + size)),
            .close
        ])
    }

    @Test(arguments: BooleanOperation.allCases)
    func combinesClosedPathsIntoAnEditableClosedPath(_ operation: BooleanOperation) throws {
        let result = try BooleanEditing.combine([square(.zero, 40), square(CGPoint(x: 20, y: 20), 40)], operation: operation)
        try PathEditing.validate(result)
        #expect(result.commands.contains { if case .close = $0 { true } else { false } })
    }

    @Test func rejectsOpenPathsAndInsufficientInputs() {
        let open = VectorPath(commands: [.move(to: .zero), .line(to: CGPoint(x: 10, y: 0))])
        #expect(throws: BooleanEditingError.requiresAtLeastTwoPaths) {
            try BooleanEditing.combine([open], operation: .union)
        }
        #expect(throws: BooleanEditingError.openPath) {
            try BooleanEditing.combine([open, open], operation: .union)
        }
    }

    @Test func subtractionProducesAnEditableClosedResult() throws {
        let result = try BooleanEditing.combine([square(.zero, 100), square(CGPoint(x: 25, y: 25), 50)], operation: .subtraction)
        try PathEditing.validate(result)
        #expect(result.commands.contains { if case .close = $0 { true } else { false } })
    }
}

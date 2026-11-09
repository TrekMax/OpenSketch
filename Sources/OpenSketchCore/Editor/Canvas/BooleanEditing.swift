import Foundation
import CoreGraphics

public enum BooleanOperation: String, Codable, CaseIterable, Sendable {
    case union
    case intersection
    case subtraction
    case exclusion
}

public enum BooleanEditingError: Error, Equatable, Sendable {
    case requiresAtLeastTwoPaths
    case openPath
    case invalidPath
    case emptyResult
    case unsupportedSubpaths
}

/// First destructive boolean geometry backend. The caller is responsible for
/// retaining the original operand nodes when a non-destructive result is needed.
public enum BooleanEditing {
    public static func combine(_ paths: [VectorPath], operation: BooleanOperation) throws -> VectorPath {
        guard paths.count >= 2 else { throw BooleanEditingError.requiresAtLeastTwoPaths }
        for path in paths {
            try PathEditing.validate(path)
            guard isClosed(path) else { throw BooleanEditingError.openPath }
            guard subpathCount(path) == 1 else { throw BooleanEditingError.unsupportedSubpaths }
        }

        var result = SceneGeometry.cgPath(for: paths[0])
        for path in paths.dropFirst() {
            let next = SceneGeometry.cgPath(for: path)
            result = switch operation {
            case .union: result.union(next)
            case .intersection: result.intersection(next)
            case .subtraction: result.subtracting(next)
            case .exclusion: result.symmetricDifference(next)
            }
        }
        guard !result.isEmpty else { throw BooleanEditingError.emptyResult }
        return try vectorPath(from: result)
    }

    static func isClosed(_ path: VectorPath) -> Bool {
        guard let last = path.commands.last else { return false }
        if case .close = last { return true }
        return false
    }

    private static func subpathCount(_ path: VectorPath) -> Int {
        path.commands.reduce(into: 0) { count, command in
            if case .move = command { count += 1 }
        }
    }

    static func vectorPath(from path: CGPath) throws -> VectorPath {
        var commands: [PathCommand] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                commands.append(.move(to: element.pointee.points[0]))
            case .addLineToPoint:
                commands.append(.line(to: element.pointee.points[0]))
            case .addCurveToPoint:
                commands.append(.cubic(control1: element.pointee.points[0],
                                       control2: element.pointee.points[1],
                                       to: element.pointee.points[2]))
            case .addQuadCurveToPoint:
                // Core Graphics may emit quadratic segments on some boolean
                // results. Convert them to cubic using the current endpoint.
                let current = commands.last.flatMap { command -> CGPoint? in
                    switch command {
                    case .move(let point), .line(let point): return point
                    case .cubic(_, _, let point): return point
                    case .close: return nil
                    }
                } ?? element.pointee.points[1]
                let control = element.pointee.points[0]
                let destination = element.pointee.points[1]
                let control1 = CGPoint(x: current.x + (2 / 3) * (control.x - current.x),
                                       y: current.y + (2 / 3) * (control.y - current.y))
                let control2 = CGPoint(x: destination.x + (2 / 3) * (control.x - destination.x),
                                       y: destination.y + (2 / 3) * (control.y - destination.y))
                commands.append(.cubic(control1: control1, control2: control2, to: destination))
            case .closeSubpath:
                commands.append(.close)
            @unknown default:
                break
            }
        }
        let result = VectorPath(commands: commands)
        try PathEditing.validate(result)
        return result
    }
}

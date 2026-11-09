import Foundation
import CoreGraphics

public enum PathPointRole: String, Codable, CaseIterable, Sendable {
    case destination
    case control1
    case control2
}

public enum PathEditingError: Error, Equatable, Sendable {
    case emptyPath
    case invalidCommandIndex
    case invalidPointRole
    case invalidSequence
    case cannotRemoveMove
    case invalidGeometry
}

public struct PathPointReference: Equatable, Sendable {
    public var commandIndex: Int
    public var role: PathPointRole

    public init(commandIndex: Int, role: PathPointRole = .destination) {
        self.commandIndex = commandIndex
        self.role = role
    }
}

public struct PathGeometry: Equatable, Sendable {
    public var frame: CGRect
    public var path: VectorPath

    public init(frame: CGRect, path: VectorPath) {
        self.frame = frame
        self.path = path
    }
}

/// Pure path construction and node-editing operations used by the pen tool
/// and the future node editor. Coordinates in the returned path are local to
/// the returned frame.
public enum PathEditing {
    public static func geometry(points: [CGPoint], closed: Bool = false) throws -> PathGeometry {
        guard !points.isEmpty, points.allSatisfy(finite) else { throw PathEditingError.invalidGeometry }
        var commands = [PathCommand.move(to: points[0])]
        commands.append(contentsOf: points.dropFirst().map(PathCommand.line(to:)))
        if closed { commands.append(.close) }
        let bounds = bounds(of: points)
        let origin = bounds.origin
        let local = commands.map { command in
            map(command) { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        }
        let frame = CGRect(x: origin.x, y: origin.y,
                           width: max(1, bounds.width), height: max(1, bounds.height))
        return PathGeometry(frame: frame, path: VectorPath(commands: local))
    }

    public static func makeNode(name: String = "路径", points: [CGPoint], closed: Bool = false,
                                style: NodeStyle? = nil) throws -> DesignNode {
        let geometry = try geometry(points: points, closed: closed)
        return DesignNode(name: name, kind: .path, frame: geometry.frame,
                          style: style, path: geometry.path)
    }

    public static func appendLine(to point: CGPoint, in path: VectorPath) throws -> VectorPath {
        guard finite(point), !path.commands.isEmpty else { throw PathEditingError.invalidGeometry }
        guard hasOpenSubpath(path) else { throw PathEditingError.invalidSequence }
        var result = path
        result.commands.append(.line(to: point))
        return result
    }

    public static func close(_ path: VectorPath) throws -> VectorPath {
        guard !path.commands.isEmpty, hasOpenSubpath(path) else { throw PathEditingError.invalidSequence }
        var result = path
        result.commands.append(.close)
        return result
    }

    public static func movePoint(_ reference: PathPointReference, to point: CGPoint,
                                 in path: VectorPath) throws -> VectorPath {
        guard finite(point), path.commands.indices.contains(reference.commandIndex) else {
            throw PathEditingError.invalidCommandIndex
        }
        var result = path
        switch (result.commands[reference.commandIndex], reference.role) {
        case (.move, .destination):
            result.commands[reference.commandIndex] = .move(to: point)
        case (.line, .destination):
            result.commands[reference.commandIndex] = .line(to: point)
        case let (.cubic(_, control2, destination), .control1):
            result.commands[reference.commandIndex] = .cubic(control1: point, control2: control2, to: destination)
        case let (.cubic(control1, _, destination), .control2):
            result.commands[reference.commandIndex] = .cubic(control1: control1, control2: point, to: destination)
        case let (.cubic(control1, control2, _), .destination):
            result.commands[reference.commandIndex] = .cubic(control1: control1, control2: control2, to: point)
        default:
            throw PathEditingError.invalidPointRole
        }
        try validate(result)
        return result
    }

    public static func removeCommand(at index: Int, from path: VectorPath) throws -> VectorPath {
        guard path.commands.indices.contains(index) else { throw PathEditingError.invalidCommandIndex }
        guard index != 0 else { throw PathEditingError.cannotRemoveMove }
        var result = path
        result.commands.remove(at: index)
        try validate(result)
        return result
    }

    public static func validate(_ path: VectorPath) throws {
        guard !path.commands.isEmpty else { throw PathEditingError.emptyPath }
        var open = false
        for command in path.commands {
            switch command {
            case .move(let point):
                guard finite(point), !open else { throw PathEditingError.invalidSequence }
                open = true
            case .line(let point):
                guard open, finite(point) else { throw PathEditingError.invalidSequence }
            case .cubic(let control1, let control2, let point):
                guard open, finite(control1), finite(control2), finite(point) else {
                    throw PathEditingError.invalidSequence
                }
            case .close:
                guard open else { throw PathEditingError.invalidSequence }
                open = false
            }
        }
    }

    private static func hasOpenSubpath(_ path: VectorPath) -> Bool {
        var open = false
        for command in path.commands {
            switch command {
            case .move: open = true
            case .close: open = false
            default: break
            }
        }
        return open
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        let first = points[0]
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func map(_ command: PathCommand, _ transform: (CGPoint) -> CGPoint) -> PathCommand {
        switch command {
        case .move(let point): .move(to: transform(point))
        case .line(let point): .line(to: transform(point))
        case .cubic(let control1, let control2, let point):
            .cubic(control1: transform(control1), control2: transform(control2), to: transform(point))
        case .close: .close
        }
    }

    private static func finite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}

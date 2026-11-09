import Foundation
import CoreGraphics

public enum PathPointRole: String, Codable, CaseIterable, Sendable, Hashable {
    case destination
    case control1
    case control2
}

public enum PathHandleMode: String, Codable, CaseIterable, Sendable {
    case free
    case aligned
    case mirrored
}

public enum PathEditingError: Error, Equatable, Sendable {
    case emptyPath
    case invalidCommandIndex
    case invalidPointRole
    case invalidSequence
    case cannotRemoveMove
    case invalidGeometry
}

public struct PathPointReference: Equatable, Sendable, Hashable {
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

    public static func insertLine(after commandIndex: Int, to point: CGPoint,
                                  in path: VectorPath) throws -> VectorPath {
        guard path.commands.indices.contains(commandIndex), finite(point) else {
            throw PathEditingError.invalidCommandIndex
        }
        switch path.commands[commandIndex] {
        case .move, .line, .cubic:
            break
        case .close:
            throw PathEditingError.invalidPointRole
        }
        var result = path
        result.commands.insert(.line(to: point), at: commandIndex + 1)
        try validate(result)
        return result
    }

    public static func close(_ path: VectorPath) throws -> VectorPath {
        guard !path.commands.isEmpty, hasOpenSubpath(path) else { throw PathEditingError.invalidSequence }
        var result = path
        result.commands.append(.close)
        return result
    }

    public static func replaceLineWithCubic(at index: Int, control1: CGPoint, control2: CGPoint,
                                            in path: VectorPath) throws -> VectorPath {
        guard path.commands.indices.contains(index), finite(control1), finite(control2) else {
            throw PathEditingError.invalidCommandIndex
        }
        guard case .line(let destination) = path.commands[index], index > 0 else {
            throw PathEditingError.invalidPointRole
        }
        var result = path
        result.commands[index] = .cubic(control1: control1, control2: control2, to: destination)
        try validate(result)
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

    /// Moves a Bézier handle and optionally updates its opposite handle at the
    /// same anchor. `aligned` preserves the opposite handle length while
    /// making both handles collinear; `mirrored` reflects the dragged handle.
    public static func moveHandle(_ reference: PathPointReference, to draggedPoint: CGPoint,
                                  mode: PathHandleMode, in path: VectorPath) throws -> VectorPath {
        guard reference.role != .destination else {
            return try movePoint(reference, to: draggedPoint, in: path)
        }
        var result = try movePoint(reference, to: draggedPoint, in: path)
        guard let opposite = oppositeHandle(of: reference, in: result),
              let anchor = anchor(for: reference, in: result),
              let oldOpposite = point(for: opposite, in: path) else { return result }
        let oppositePoint: CGPoint
        switch mode {
        case .free:
            return result
        case .mirrored:
            oppositePoint = CGPoint(x: 2 * anchor.x - draggedPoint.x, y: 2 * anchor.y - draggedPoint.y)
        case .aligned:
            let dx = anchor.x - draggedPoint.x, dy = anchor.y - draggedPoint.y
            let length = hypot(oldOpposite.x - anchor.x, oldOpposite.y - anchor.y)
            let distance = hypot(dx, dy)
            guard distance > 0, length.isFinite else { return result }
            oppositePoint = CGPoint(x: anchor.x + dx / distance * length,
                                    y: anchor.y + dy / distance * length)
        }
        result = try movePoint(opposite, to: oppositePoint, in: result)
        return result
    }

    public static func togglingClosed(_ path: VectorPath) throws -> VectorPath {
        guard !path.commands.isEmpty else { throw PathEditingError.emptyPath }
        var result = path
        if case .close = result.commands.last {
            result.commands.removeLast()
        } else {
            guard hasOpenSubpath(result) else { throw PathEditingError.invalidSequence }
            result.commands.append(.close)
        }
        try validate(result)
        return result
    }

    /// Reverses a single-subpath path while preserving line and cubic geometry.
    public static func reversed(_ path: VectorPath) throws -> VectorPath {
        guard !path.commands.isEmpty else { throw PathEditingError.emptyPath }
        let closed = path.commands.last.map { if case .close = $0 { true } else { false } } ?? false
        let body = closed ? Array(path.commands.dropLast()) : path.commands
        guard let first = body.first, case .move = first else { throw PathEditingError.invalidSequence }
        var points: [PathCommand] = []
        var segments: [(start: CGPoint, command: PathCommand, end: CGPoint)] = []
        var current: CGPoint?
        for command in body {
            switch command {
            case .move(let point): current = point
            case .line(let point):
                guard let start = current else { throw PathEditingError.invalidSequence }
                segments.append((start, command, point)); current = point
            case .cubic(_, _, let point):
                guard let start = current else { throw PathEditingError.invalidSequence }
                segments.append((start, command, point)); current = point
            case .close: break
            }
        }
        guard let lastEnd = segments.last?.end ?? (firstPoint(in: body)) else { throw PathEditingError.emptyPath }
        points.append(.move(to: lastEnd))
        for segment in segments.reversed() {
            switch segment.command {
            case .line: points.append(.line(to: segment.start))
            case .cubic(let control1, let control2, _):
                points.append(.cubic(control1: control2, control2: control1, to: segment.start))
            default: break
            }
        }
        if closed { points.append(.close) }
        let result = VectorPath(commands: points)
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

    public static func removeCommands(at indices: Set<Int>, from path: VectorPath) throws -> VectorPath {
        guard !indices.isEmpty, indices.allSatisfy(path.commands.indices.contains) else {
            throw PathEditingError.invalidCommandIndex
        }
        guard !indices.contains(0) else { throw PathEditingError.cannotRemoveMove }
        var result = path
        for index in indices.sorted(by: >) {
            result.commands.remove(at: index)
        }
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

    private static func firstPoint(in commands: [PathCommand]) -> CGPoint? {
        for command in commands {
            if case .move(let point) = command { return point }
        }
        return nil
    }

    private static func point(for reference: PathPointReference, in path: VectorPath) -> CGPoint? {
        guard path.commands.indices.contains(reference.commandIndex) else { return nil }
        switch (path.commands[reference.commandIndex], reference.role) {
        case (.move(let point), .destination), (.line(let point), .destination): return point
        case let (.cubic(control1, _, _), .control1): return control1
        case let (.cubic(_, control2, _), .control2): return control2
        case let (.cubic(_, _, destination), .destination): return destination
        default: return nil
        }
    }

    private static func anchor(for reference: PathPointReference, in path: VectorPath) -> CGPoint? {
        switch reference.role {
        case .control1:
            guard reference.commandIndex > 0 else { return firstPoint(in: Array(path.commands.prefix(1))) }
            return point(for: PathPointReference(commandIndex: reference.commandIndex - 1), in: path)
        case .control2:
            return point(for: PathPointReference(commandIndex: reference.commandIndex), in: path)
        case .destination: return nil
        }
    }

    private static func oppositeHandle(of reference: PathPointReference, in path: VectorPath) -> PathPointReference? {
        switch reference.role {
        case .control1:
            guard reference.commandIndex > 0,
                  case .cubic = path.commands[reference.commandIndex - 1] else { return nil }
            return PathPointReference(commandIndex: reference.commandIndex - 1, role: .control2)
        case .control2:
            let next = reference.commandIndex + 1
            guard path.commands.indices.contains(next), case .cubic = path.commands[next] else { return nil }
            return PathPointReference(commandIndex: next, role: .control1)
        case .destination: return nil
        }
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

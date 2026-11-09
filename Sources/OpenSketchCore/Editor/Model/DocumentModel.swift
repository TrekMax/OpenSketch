import Foundation
import CoreGraphics

public enum NodeKind: String, Codable, CaseIterable, Sendable {
    case frame, group, rectangle, ellipse, text, path
}

public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
}

public struct GradientStop: Codable, Equatable, Sendable {
    public var position: Double
    public var color: RGBAColor

    public init(position: Double, color: RGBAColor) {
        self.position = position
        self.color = color
    }
}

public struct LinearGradient: Codable, Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var stops: [GradientStop]

    public init(start: CGPoint = CGPoint(x: 0, y: 0.5),
                end: CGPoint = CGPoint(x: 1, y: 0.5),
                stops: [GradientStop]) {
        self.start = start
        self.end = end
        self.stops = stops
    }
}

public struct NodeStyle: Codable, Equatable, Sendable {
    public var fill: RGBAColor?
    public var linearGradient: LinearGradient?
    public var stroke: RGBAColor?
    public var strokeWidth: Double
    public var opacity: Double
    public var cornerRadius: Double
    public init(fill: RGBAColor? = nil, stroke: RGBAColor? = nil, strokeWidth: Double = 1,
                opacity: Double = 1, cornerRadius: Double = 0) {
        self.fill = fill; self.linearGradient = nil; self.stroke = stroke; self.strokeWidth = strokeWidth
        self.opacity = opacity; self.cornerRadius = cornerRadius
    }
    public static func `default`(for kind: NodeKind) -> Self {
        switch kind {
        case .frame: Self(fill: .white)
        case .group: Self()
        case .text: Self(fill: .black)
        case .rectangle, .ellipse, .path:
            Self(fill: RGBAColor(red: 0.27, green: 0.48, blue: 0.95))
        }
    }
}

public enum ParagraphAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right, justified
}

public enum PathCommand: Codable, Equatable, Sendable {
    case move(to: CGPoint)
    case line(to: CGPoint)
    case cubic(control1: CGPoint, control2: CGPoint, to: CGPoint)
    case close
}

public struct VectorPath: Codable, Equatable, Sendable {
    public var commands: [PathCommand]
    public init(commands: [PathCommand] = []) { self.commands = commands }
}

public struct BooleanSource: Codable, Equatable, Sendable {
    public var operation: BooleanOperation
    public var operands: [DesignNode]
    public init(operation: BooleanOperation, operands: [DesignNode]) {
        self.operation = operation
        self.operands = operands
    }
}

public struct DesignNode: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: NodeKind
    public var frame: CGRect
    /// Clockwise degrees in the canvas's downward-positive coordinate system.
    public var rotation: Double
    public var isVisible: Bool
    public var isLocked: Bool
    public var clipsContent: Bool
    public var style: NodeStyle
    public var text: String
    public var fontName: String
    public var fontSize: Double
    public var textAlignment: ParagraphAlignment
    public var path: VectorPath
    public var children: [DesignNode]
    public var booleanSource: BooleanSource?

    public init(id: UUID = UUID(), name: String = "", kind: NodeKind,
                frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100), rotation: Double = 0,
                isVisible: Bool = true, isLocked: Bool = false, clipsContent: Bool = false,
                style: NodeStyle? = nil, text: String = "", fontName: String = "Helvetica Neue",
                fontSize: Double = 24, textAlignment: ParagraphAlignment = .left,
                path: VectorPath = VectorPath(), children: [DesignNode] = []) {
        self.id = id; self.name = name; self.kind = kind; self.frame = frame; self.rotation = rotation
        self.isVisible = isVisible; self.isLocked = isLocked; self.clipsContent = clipsContent
        self.style = style ?? .default(for: kind); self.text = text; self.fontName = fontName
        self.fontSize = fontSize; self.textAlignment = textAlignment; self.path = path; self.children = children
        self.booleanSource = nil
    }
}

public struct DesignPage: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var size: CGSize
    public var nodes: [DesignNode]
    public init(id: UUID = UUID(), name: String = "页面 1",
                size: CGSize = CGSize(width: 1440, height: 900), nodes: [DesignNode] = []) {
        self.id = id; self.name = name; self.size = size; self.nodes = nodes
    }
}

public struct DesignDocument: Codable, Equatable, Identifiable, Sendable {
    public static let formatIdentifier = "org.opensketch.document"
    public static let currentVersion = 1
    public var format: String
    public var version: Int
    public var id: UUID
    public var name: String
    public var pages: [DesignPage]
    public init(id: UUID = UUID(), name: String = "未命名", pages: [DesignPage] = [DesignPage()],
                format: String = Self.formatIdentifier, version: Int = Self.currentVersion) {
        self.id = id; self.name = name; self.pages = pages; self.format = format; self.version = version
    }
    public static func blank() -> Self { Self() }
}

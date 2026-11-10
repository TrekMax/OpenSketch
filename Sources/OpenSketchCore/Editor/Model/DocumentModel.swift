import Foundation
import CoreGraphics

public enum NodeKind: String, Codable, CaseIterable, Sendable {
    case frame, group, rectangle, ellipse, text, path
}

public enum StackAxis: String, Codable, CaseIterable, Sendable { case horizontal, vertical }
public enum StackAlignment: String, Codable, CaseIterable, Sendable { case leading, center, trailing, fill }
public enum StackSizing: String, Codable, CaseIterable, Sendable { case fixed, fit, fill }

public struct StackPadding: Codable, Equatable, Sendable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double
    public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
}

public struct StackLayout: Codable, Equatable, Sendable {
    public var axis: StackAxis
    public var spacing: Double
    public var padding: StackPadding
    public var alignment: StackAlignment
    public var sizing: StackSizing
    public init(axis: StackAxis = .vertical, spacing: Double = 8, padding: StackPadding = .init(),
                alignment: StackAlignment = .leading, sizing: StackSizing = .fixed) {
        self.axis = axis; self.spacing = spacing; self.padding = padding
        self.alignment = alignment; self.sizing = sizing
    }
}

public struct NodeConstraints: Codable, Equatable, Sendable {
    public var pinLeft: Bool
    public var pinRight: Bool
    public var pinTop: Bool
    public var pinBottom: Bool
    public var fixedWidth: Bool
    public var fixedHeight: Bool
    public init(pinLeft: Bool = false, pinRight: Bool = false, pinTop: Bool = false,
                pinBottom: Bool = false, fixedWidth: Bool = true, fixedHeight: Bool = true) {
        self.pinLeft = pinLeft; self.pinRight = pinRight; self.pinTop = pinTop; self.pinBottom = pinBottom
        self.fixedWidth = fixedWidth; self.fixedHeight = fixedHeight
    }
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

public enum StrokeLineCap: String, Codable, CaseIterable, Sendable { case butt, round, square }
public enum StrokeLineJoin: String, Codable, CaseIterable, Sendable { case miter, round, bevel }

public struct NodeStyle: Codable, Equatable, Sendable {
    public var fill: RGBAColor?
    public var linearGradient: LinearGradient?
    public var stroke: RGBAColor?
    public var strokeWidth: Double
    public var opacity: Double
    public var cornerRadius: Double
    public var strokeLineCap: StrokeLineCap
    public var strokeLineJoin: StrokeLineJoin
    public var miterLimit: Double
    public init(fill: RGBAColor? = nil, stroke: RGBAColor? = nil, strokeWidth: Double = 1,
                opacity: Double = 1, cornerRadius: Double = 0) {
        self.fill = fill; self.linearGradient = nil; self.stroke = stroke; self.strokeWidth = strokeWidth
        self.opacity = opacity; self.cornerRadius = cornerRadius
        self.strokeLineCap = .butt; self.strokeLineJoin = .miter; self.miterLimit = 10
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

    private enum CodingKeys: String, CodingKey {
        case fill, linearGradient, stroke, strokeWidth, opacity, cornerRadius
        case strokeLineCap, strokeLineJoin, miterLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fill = try container.decodeIfPresent(RGBAColor.self, forKey: .fill)
        linearGradient = try container.decodeIfPresent(LinearGradient.self, forKey: .linearGradient)
        stroke = try container.decodeIfPresent(RGBAColor.self, forKey: .stroke)
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 1
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
        strokeLineCap = try container.decodeIfPresent(StrokeLineCap.self, forKey: .strokeLineCap) ?? .butt
        strokeLineJoin = try container.decodeIfPresent(StrokeLineJoin.self, forKey: .strokeLineJoin) ?? .miter
        miterLimit = try container.decodeIfPresent(Double.self, forKey: .miterLimit) ?? 10
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
    public var componentDefinitionID: UUID?
    public var sharedStyleID: UUID?
    public var stackLayout: StackLayout?
    public var constraints: NodeConstraints?

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
        self.componentDefinitionID = nil; self.sharedStyleID = nil; self.stackLayout = nil; self.constraints = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, frame, rotation, isVisible, isLocked, clipsContent, style, text, fontName
        case fontSize, textAlignment, path, children, booleanSource, componentDefinitionID, sharedStyleID
        case stackLayout, constraints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(NodeKind.self, forKey: .kind); frame = try c.decode(CGRect.self, forKey: .frame)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        clipsContent = try c.decodeIfPresent(Bool.self, forKey: .clipsContent) ?? false
        style = try c.decodeIfPresent(NodeStyle.self, forKey: .style) ?? .default(for: kind)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "Helvetica Neue"
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 24
        textAlignment = try c.decodeIfPresent(ParagraphAlignment.self, forKey: .textAlignment) ?? .left
        path = try c.decodeIfPresent(VectorPath.self, forKey: .path) ?? .init()
        children = try c.decodeIfPresent([DesignNode].self, forKey: .children) ?? []
        booleanSource = try c.decodeIfPresent(BooleanSource.self, forKey: .booleanSource)
        componentDefinitionID = try c.decodeIfPresent(UUID.self, forKey: .componentDefinitionID)
        sharedStyleID = try c.decodeIfPresent(UUID.self, forKey: .sharedStyleID)
        stackLayout = try c.decodeIfPresent(StackLayout.self, forKey: .stackLayout)
        constraints = try c.decodeIfPresent(NodeConstraints.self, forKey: .constraints)
    }
}

public struct ComponentDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var root: DesignNode
    public init(id: UUID = UUID(), name: String, root: DesignNode) {
        self.id = id; self.name = name; self.root = root
    }
}

public struct SharedStyle: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var style: NodeStyle
    public init(id: UUID = UUID(), name: String, style: NodeStyle) {
        self.id = id; self.name = name; self.style = style
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
    public var componentDefinitions: [ComponentDefinition]
    public var sharedStyles: [SharedStyle]
    public init(id: UUID = UUID(), name: String = "未命名", pages: [DesignPage] = [DesignPage()],
                format: String = Self.formatIdentifier, version: Int = Self.currentVersion) {
        self.id = id; self.name = name; self.pages = pages; self.format = format; self.version = version
        self.componentDefinitions = []; self.sharedStyles = []
    }
    public static func blank() -> Self { Self() }

    private enum CodingKeys: String, CodingKey { case format, version, id, name, pages, componentDefinitions, sharedStyles }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format); version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        pages = try c.decode([DesignPage].self, forKey: .pages)
        componentDefinitions = try c.decodeIfPresent([ComponentDefinition].self, forKey: .componentDefinitions) ?? []
        sharedStyles = try c.decodeIfPresent([SharedStyle].self, forKey: .sharedStyles) ?? []
    }
}

import Foundation

public enum PluginKind: String, Codable, CaseIterable, Sendable {
    case documentFormat
    case exporter
    case operation
    case devicePreview
}

public enum PluginCapability: String, Codable, CaseIterable, Sendable {
    case readDocument
    case writeDocument
    case export
    case network
    case device
    case aiOperation
    case fileAccess
    case configurationUI
}

public struct PluginFileType: Codable, Equatable, Sendable {
    public var extensionName: String
    public var mimeType: String?
    public var uniformTypeIdentifier: String?

    public init(extensionName: String, mimeType: String? = nil, uniformTypeIdentifier: String? = nil) {
        self.extensionName = extensionName
        self.mimeType = mimeType
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

public struct PluginManifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var apiVersion: Int
    public var kind: PluginKind
    public var capabilities: Set<PluginCapability>
    public var fileTypes: [PluginFileType]

    public init(id: String, name: String, version: String = "1.0.0", apiVersion: Int = 1,
                kind: PluginKind, capabilities: Set<PluginCapability> = [],
                fileTypes: [PluginFileType] = []) {
        self.id = id; self.name = name; self.version = version; self.apiVersion = apiVersion
        self.kind = kind; self.capabilities = capabilities; self.fileTypes = fileTypes
    }
}

public struct PluginDocumentSnapshot: Codable, Equatable, Sendable {
    public var document: DesignDocument
    public var pageID: UUID
    public var selection: Set<UUID>

    public init(document: DesignDocument, pageID: UUID, selection: Set<UUID> = []) {
        self.document = document; self.pageID = pageID; self.selection = selection
    }
}

public struct PluginDiagnostic: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case info, warning, error }
    public var severity: Severity
    public var message: String
    public var nodeID: UUID?

    public init(severity: Severity, message: String, nodeID: UUID? = nil) {
        self.severity = severity; self.message = message; self.nodeID = nodeID
    }
}

public struct PluginExportRequest: Codable, Equatable, Sendable {
    public var snapshot: PluginDocumentSnapshot
    public var options: [String: String]
    public var outputExtension: String

    public init(snapshot: PluginDocumentSnapshot, options: [String: String] = [:], outputExtension: String) {
        self.snapshot = snapshot; self.options = options; self.outputExtension = outputExtension
    }
}

public struct PluginExportResult: Codable, Equatable, Sendable {
    public var data: Data?
    public var diagnostics: [PluginDiagnostic]
    public var cancelled: Bool

    public init(data: Data? = nil, diagnostics: [PluginDiagnostic] = [], cancelled: Bool = false) {
        self.data = data; self.diagnostics = diagnostics; self.cancelled = cancelled
    }
}

public enum BuiltInPluginRegistry {
    public static let manifests: [PluginManifest] = [
        PluginManifest(id: "org.opensketch.format.document", name: "OpenSketch Document", kind: .documentFormat,
                       capabilities: [.readDocument, .writeDocument],
                       fileTypes: [PluginFileType(extensionName: "opensketch", uniformTypeIdentifier: "org.opensketch.document")]),
        PluginManifest(id: "org.opensketch.export.svg", name: "SVG Export", kind: .exporter,
                       capabilities: [.readDocument, .export],
                       fileTypes: [PluginFileType(extensionName: "svg", mimeType: "image/svg+xml", uniformTypeIdentifier: "public.svg-image")]),
        PluginManifest(id: "org.opensketch.export.png", name: "PNG Export", kind: .exporter,
                       capabilities: [.readDocument, .export],
                       fileTypes: [PluginFileType(extensionName: "png", mimeType: "image/png", uniformTypeIdentifier: "public.png")])
    ]
}

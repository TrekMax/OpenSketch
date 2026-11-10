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

public enum PluginPermissionError: Error, Equatable, Sendable {
    case missingCapability(PluginCapability)
    case unsupportedAPIVersion
}

public struct PluginTask: Codable, Equatable, Sendable {
    public var id: UUID
    public var pluginID: String
    public var startedAt: Date
    public var cancellable: Bool
    public init(id: UUID = UUID(), pluginID: String, startedAt: Date = Date(), cancellable: Bool = true) {
        self.id = id; self.pluginID = pluginID; self.startedAt = startedAt; self.cancellable = cancellable
    }
}

public enum PluginTaskState: String, Codable, CaseIterable, Sendable {
    case queued, running, cancelling, completed, failed, cancelled
}

public struct PluginTaskProgress: Codable, Equatable, Sendable {
    public var task: PluginTask
    public var state: PluginTaskState
    public var fraction: Double
    public var message: String?
    public var error: String?

    public init(task: PluginTask, state: PluginTaskState = .queued, fraction: Double = 0,
                message: String? = nil, error: String? = nil) {
        self.task = task; self.state = state; self.fraction = min(1, max(0, fraction))
        self.message = message; self.error = error
    }
}

public enum PluginOperationKind: String, Codable, CaseIterable, Sendable {
    case queryDocument
    case createNode
    case updateNode
    case deleteNode
    case moveNode
    case renameNode
    case groupNodes
    case export
}

public struct PluginOperation: Codable, Equatable, Sendable {
    public var kind: PluginOperationKind
    public var nodeIDs: [UUID]
    public var parameters: [String: String]
    public init(kind: PluginOperationKind, nodeIDs: [UUID] = [], parameters: [String: String] = [:]) {
        self.kind = kind; self.nodeIDs = nodeIDs; self.parameters = parameters
    }
}

public struct PluginOperationPlan: Codable, Equatable, Sendable {
    public var id: UUID
    public var source: String
    public var operations: [PluginOperation]
    public var diagnostics: [PluginDiagnostic]
    public init(id: UUID = UUID(), source: String, operations: [PluginOperation], diagnostics: [PluginDiagnostic] = []) {
        self.id = id; self.source = source; self.operations = operations; self.diagnostics = diagnostics
    }
}

public struct PluginAuditEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var pluginID: String
    public var operation: PluginOperationKind
    public var approved: Bool
    public init(timestamp: Date = Date(), pluginID: String, operation: PluginOperationKind, approved: Bool) {
        self.timestamp = timestamp; self.pluginID = pluginID; self.operation = operation; self.approved = approved
    }
}

public actor PluginAuditLog {
    private var events: [PluginAuditEvent] = []
    public init() {}
    public func append(_ newEvents: [PluginAuditEvent]) { events.append(contentsOf: newEvents) }
    public func all() -> [PluginAuditEvent] { events }
    public func removeAll() { events.removeAll() }
}

public struct PreviewDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var size: CGSize
    public var scale: Double
    public var isConnected: Bool
    public init(id: UUID = UUID(), name: String, size: CGSize, scale: Double = 2, isConnected: Bool = false) {
        self.id = id; self.name = name; self.size = size; self.scale = scale; self.isConnected = isConnected
    }
}

public struct DevicePreviewSnapshot: Codable, Equatable, Sendable {
    public var documentID: UUID
    public var page: DesignPage
    public var revision: UUID
    public init(documentID: UUID, page: DesignPage, revision: UUID = UUID()) {
        self.documentID = documentID; self.page = page; self.revision = revision
    }
}

public enum DevicePreviewState: String, Codable, Sendable { case disconnected, connecting, connected, syncing, failed }

public struct DevicePreviewStatus: Codable, Equatable, Sendable {
    public var device: PreviewDevice
    public var state: DevicePreviewState
    public var lastRevision: UUID?
    public var message: String?
    public init(device: PreviewDevice, state: DevicePreviewState = .disconnected, lastRevision: UUID? = nil, message: String? = nil) {
        self.device = device; self.state = state; self.lastRevision = lastRevision; self.message = message
    }
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

public struct PluginPackageManifest: Codable, Equatable, Sendable {
    public static let formatIdentifier = "org.opensketch.plugin"
    public static let packageExtension = "opskplugin"
    public static let currentVersion = 1

    public var format: String
    public var packageVersion: Int
    public var plugin: PluginManifest
    public var entrypoint: String
    public var minimumHostVersion: String

    public init(plugin: PluginManifest, entrypoint: String,
                minimumHostVersion: String = "0.1.0",
                format: String = Self.formatIdentifier,
                packageVersion: Int = Self.currentVersion) {
        self.format = format
        self.packageVersion = packageVersion
        self.plugin = plugin
        self.entrypoint = entrypoint
        self.minimumHostVersion = minimumHostVersion
    }

    public func validate() throws {
        guard format == Self.formatIdentifier else { throw PluginPackageError.invalidFormat }
        guard packageVersion == Self.currentVersion else { throw PluginPackageError.unsupportedVersion(packageVersion) }
        guard plugin.apiVersion == 1, !plugin.id.isEmpty, !plugin.version.isEmpty,
              !entrypoint.isEmpty, entrypoint.count <= 512,
              entrypoint.hasPrefix("Contents/"), !entrypoint.contains(".."), !entrypoint.contains("\\") else { throw PluginPackageError.invalidManifest }
        guard plugin.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else {
            throw PluginPackageError.invalidManifest
        }
    }
}

public enum PluginPackageError: Error, Equatable, Sendable {
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidManifest
    case missingManifest
    case oversizedPackage
    case invalidEntry(String)
    case archiveReadFailed
}

public enum PluginPackageLayout {
    public static let manifestPath = "plugin.json"
    public static let contentsDirectory = "Contents/"
    public static let resourcesDirectory = "Resources/"
    public static let signatureDirectory = "Signature/"
    public static let allowedTopLevelPaths: Set<String> = [manifestPath, contentsDirectory, resourcesDirectory, signatureDirectory]
}

/// Reads `.opskplugin` archives through the system ZIP reader. The loader does
/// not extract arbitrary files and validates every entry before exposing the
/// manifest, which keeps package inspection bounded and prevents traversal.
public struct PluginPackage: Equatable, Sendable {
    public static let maximumArchiveBytes = 100 * 1024 * 1024
    public static let maximumManifestBytes = 512 * 1024
    public static let maximumEntries = 4096

    public let url: URL
    public let manifest: PluginPackageManifest
    public let entries: [String]

    public static func load(from url: URL) throws -> PluginPackage {
        guard url.pathExtension == PluginPackageManifest.packageExtension else { throw PluginPackageError.invalidFormat }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumArchiveBytes else {
            throw PluginPackageError.oversizedPackage
        }
        let entries = try runUnzip(arguments: ["-Z1", url.path], maximumBytes: 2 * 1024 * 1024)
            .split(whereSeparator: { $0 == 10 || $0 == 13 }).map { String(decoding: $0, as: UTF8.self) }.filter { !$0.isEmpty }
        guard entries.count <= maximumEntries else { throw PluginPackageError.oversizedPackage }
        for entry in entries { try validateEntry(entry) }
        guard entries.contains(PluginPackageLayout.manifestPath) else { throw PluginPackageError.missingManifest }
        let manifestData = try runUnzip(arguments: ["-p", url.path, PluginPackageLayout.manifestPath], maximumBytes: maximumManifestBytes)
        let manifest = try JSONDecoder().decode(PluginPackageManifest.self, from: manifestData)
        try manifest.validate()
        guard entries.contains(manifest.entrypoint) else { throw PluginPackageError.invalidManifest }
        return PluginPackage(url: url, manifest: manifest, entries: entries)
    }

    public func data(for path: String, maximumBytes: Int = 10 * 1024 * 1024) throws -> Data {
        try Self.validateEntry(path)
        guard entries.contains(path) else { throw PluginPackageError.invalidEntry(path) }
        return try Self.runUnzip(arguments: ["-p", url.path, path], maximumBytes: maximumBytes)
    }

    private static func validateEntry(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains(".."),
              !path.contains(":") else { throw PluginPackageError.invalidEntry(path) }
        let top = path.split(separator: "/").first.map(String.init) ?? ""
        guard path == PluginPackageLayout.manifestPath || ["Contents", "Resources", "Signature"].contains(top) else {
            throw PluginPackageError.invalidEntry(path)
        }
    }

    private static func runUnzip(arguments: [String], maximumBytes: Int) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw PluginPackageError.archiveReadFailed }
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: min(64 * 1024, maximumBytes - data.count + 1))
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > maximumBytes {
                process.terminate()
                process.waitUntilExit()
                throw PluginPackageError.oversizedPackage
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= maximumBytes else {
            throw data.count > maximumBytes ? PluginPackageError.oversizedPackage : PluginPackageError.archiveReadFailed
        }
        return data
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
                       fileTypes: [PluginFileType(extensionName: "png", mimeType: "image/png", uniformTypeIdentifier: "public.png")]),
        PluginManifest(id: "org.opensketch.export.jpg", name: "JPEG Export", kind: .exporter,
                       capabilities: [.readDocument, .export],
                       fileTypes: [PluginFileType(extensionName: "jpg", mimeType: "image/jpeg", uniformTypeIdentifier: "public.jpeg")]),
        PluginManifest(id: "org.opensketch.export.pdf", name: "PDF Export", kind: .exporter,
                       capabilities: [.readDocument, .export],
                       fileTypes: [PluginFileType(extensionName: "pdf", mimeType: "application/pdf", uniformTypeIdentifier: "com.adobe.pdf")]),
        PluginManifest(id: "org.opensketch.export.html", name: "HTML Preview", kind: .exporter,
                       capabilities: [.readDocument, .export],
                       fileTypes: [PluginFileType(extensionName: "html", mimeType: "text/html")]),
        PluginManifest(id: "org.opensketch.export.assets", name: "Asset Package", kind: .exporter,
                       capabilities: [.readDocument, .export, .fileAccess],
                       fileTypes: [PluginFileType(extensionName: "json", mimeType: "application/json")]),
        PluginManifest(id: "org.opensketch.preview.local", name: "Local Device Preview", kind: .devicePreview,
                       capabilities: [.readDocument, .device])
    ]

    public static func manifest(id: String) -> PluginManifest? { manifests.first { $0.id == id } }
    public static func require(_ capability: PluginCapability, for id: String) throws {
        guard let manifest = manifest(id: id) else { throw PluginPermissionError.missingCapability(capability) }
        guard manifest.apiVersion == 1 else { throw PluginPermissionError.unsupportedAPIVersion }
        guard manifest.capabilities.contains(capability) else { throw PluginPermissionError.missingCapability(capability) }
    }
}

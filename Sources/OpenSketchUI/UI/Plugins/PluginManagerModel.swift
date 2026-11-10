import Foundation
import AppKit
import Observation
import OpenSketchCore
import UniformTypeIdentifiers

@MainActor @Observable final class PluginManagerModel {
    struct Item: Identifiable {
        let id: String
        var manifest: PluginManifest
        var packageURL: URL?
        var enabled: Bool
        var error: String?
    }

    private(set) var items: [Item] = []
    var lastError: String?
    private var library: PluginLibrary?
    let taskManager = PluginTaskManager()
    let previewBackend: LocalDevicePreviewBackend
    var tasks: [PluginTaskProgress] = []
    var devices: [DevicePreviewStatus] = []
    var previewImages: [UUID: NSImage] = [:]
    var deviceTasks: [UUID: UUID] = [:]
    @ObservationIgnored var workers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var currentSession: () -> EditorSession? = { nil }
    @ObservationIgnored var sessions: () -> [EditorSession] = { [] }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OpenSketch/Plugins"),
         previewBackend: LocalDevicePreviewBackend = LocalDevicePreviewBackend(devices: [
            PreviewDevice(name: "Local Preview", size: CGSize(width: 390, height: 844))
         ])) {
        self.previewBackend = previewBackend
        do { library = try PluginLibrary(directory: directory) }
        catch { lastError = L10n.errorDescription(error) }
        reloadItems()
    }

    var auditEvents: [PluginAuditEvent] {
        sessions().flatMap(\.pluginAuditEvents).sorted { $0.timestamp > $1.timestamp }
    }

    private func reloadItems() {
        items = BuiltInPluginRegistry.manifests.map {
            Item(id: $0.id, manifest: $0, packageURL: nil,
                 enabled: $0.kind == .documentFormat || !(library?.disabledBuiltIns.contains($0.id) ?? false), error: nil)
        } + (library?.installed ?? []).map {
            Item(id: $0.manifest.plugin.id, manifest: $0.manifest.plugin, packageURL: $0.packageURL,
                 enabled: $0.enabled, error: library?.errors[$0.manifest.plugin.id])
        }
    }

    func requireEnabled(_ id: String) throws {
        guard let item = items.first(where: { $0.id == id }), item.enabled, item.error == nil else {
            throw EditorError.invalid("插件已禁用或不可用。")
        }
    }

    var builtInItems: [Item] { items.filter { $0.packageURL == nil } }
    var externalItems: [Item] { items.filter { $0.packageURL != nil } }

    func install(url: URL) {
        do {
            guard library != nil else { throw EditorError.invalid("插件注册表不可用。") }
            try library?.install(from: url)
            reloadItems()
            lastError = nil
        } catch {
            lastError = L10n.errorDescription(error)
        }
    }

    func chooseAndInstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: PluginPackageManifest.packageExtension, conformingTo: .package) ?? .package]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { install(url: url) }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        do {
            guard library != nil else { throw EditorError.invalid("插件注册表不可用。") }
            try library?.setEnabled(enabled, id: id)
            reloadItems()
            lastError = nil
            if !enabled { cancelTasks(pluginID: id) }
        } catch { lastError = L10n.errorDescription(error) }
    }

    func uninstall(id: String) {
        do {
            try library?.uninstall(id: id)
            lastError = nil
            cancelTasks(pluginID: id)
        } catch { lastError = L10n.errorDescription(error) }
        reloadItems()
    }
}

import Foundation
import AppKit
import Observation
import OpenSketchCore

@MainActor @Observable final class PluginManagerModel {
    struct Item: Identifiable {
        let id: String
        var manifest: PluginManifest
        var packageURL: URL?
        var enabled: Bool
        var error: String?
    }

    var items: [Item] = BuiltInPluginRegistry.manifests.map {
        Item(id: $0.id, manifest: $0, packageURL: nil, enabled: true, error: nil)
    }
    var lastError: String?

    func install(url: URL) {
        do {
            let package = try PluginPackage.load(from: url)
            let item = Item(id: package.manifest.plugin.id, manifest: package.manifest.plugin,
                            packageURL: url, enabled: true, error: nil)
            items.removeAll { $0.id == item.id }
            items.append(item)
            lastError = nil
        } catch {
            lastError = L10n.errorDescription(error)
        }
    }

    func chooseAndInstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.package]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { install(url: url) }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].enabled = enabled
    }

    func uninstall(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].packageURL != nil else { return }
        let item = items.remove(at: index)
        if let url = item.packageURL { try? FileManager.default.removeItem(at: url) }
    }
}

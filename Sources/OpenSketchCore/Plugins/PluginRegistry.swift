import Foundation

public struct InstalledPlugin: Codable, Equatable, Sendable {
    public var manifest: PluginPackageManifest
    public var packageURL: URL
    public var enabled: Bool

    public init(manifest: PluginPackageManifest, packageURL: URL, enabled: Bool = true) {
        self.manifest = manifest; self.packageURL = packageURL; self.enabled = enabled
    }
}

public struct PluginRegistry: Sendable {
    public private(set) var installed: [InstalledPlugin] = []

    public init() {}

    @discardableResult
    public mutating func install(_ package: PluginPackage) -> InstalledPlugin {
        let item = InstalledPlugin(manifest: package.manifest, packageURL: package.url)
        installed.removeAll { $0.manifest.plugin.id == item.manifest.plugin.id }
        installed.append(item)
        return item
    }

    @discardableResult
    public mutating func uninstall(id: String) -> Bool {
        let oldCount = installed.count; installed.removeAll { $0.manifest.plugin.id == id }; return installed.count != oldCount
    }

    @discardableResult
    public mutating func setEnabled(_ enabled: Bool, id: String) -> Bool {
        guard let index = installed.firstIndex(where: { $0.manifest.plugin.id == id }) else { return false }
        installed[index].enabled = enabled; return true
    }

    public func plugin(id: String) -> InstalledPlugin? { installed.first { $0.manifest.plugin.id == id } }
}

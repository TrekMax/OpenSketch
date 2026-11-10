import Foundation

/// Owns installed copies; committing the index precedes removing an old copy.
public struct PluginLibrary: Sendable {
    private struct Index: Codable {
        var installed: [InstalledPlugin] = []
        var disabledBuiltIns: Set<String> = []
    }

    public let directory: URL
    public private(set) var registry = PluginRegistry()
    public private(set) var errors: [String: String] = [:]
    private var index = Index()
    public var installed: [InstalledPlugin] { index.installed }
    public var disabledBuiltIns: Set<String> { index.disabledBuiltIns }

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        let indexURL = directory.appendingPathComponent("registry.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        for item in index.installed {
            do {
                guard owns(item.packageURL), BuiltInPluginRegistry.manifest(id: item.manifest.plugin.id) == nil,
                      registry.plugin(id: item.manifest.plugin.id) == nil else { throw PluginPackageError.invalidManifest }
                let package = try PluginPackage.load(from: item.packageURL)
                guard package.manifest == item.manifest else { throw PluginPackageError.invalidManifest }
                registry.install(package)
                registry.setEnabled(item.enabled, id: item.manifest.plugin.id)
            } catch { errors[item.manifest.plugin.id] = String(describing: error) }
        }
    }

    public mutating func install(from source: URL) throws {
        let package = try PluginPackage.load(from: source)
        guard BuiltInPluginRegistry.manifest(id: package.manifest.plugin.id) == nil else {
            throw PluginPackageError.invalidManifest
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(UUID().uuidString).opskplugin")
        try FileManager.default.copyItem(at: source, to: destination)
        do {
            let copy = try PluginPackage.load(from: destination)
            guard copy.manifest == package.manifest else { throw PluginPackageError.invalidManifest }
            let id = copy.manifest.plugin.id
            let old = index.installed.first { $0.manifest.plugin.id == id }
            var candidate = index
            candidate.installed.removeAll { $0.manifest.plugin.id == id }
            candidate.installed.append(InstalledPlugin(manifest: copy.manifest, packageURL: destination, enabled: old?.enabled ?? true))
            try persist(candidate)
            index = candidate
            registry.install(copy)
            registry.setEnabled(old?.enabled ?? true, id: id)
            errors[id] = nil
            if let old, owns(old.packageURL) { try? FileManager.default.removeItem(at: old.packageURL) }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    public mutating func setEnabled(_ enabled: Bool, id: String) throws {
        var candidate = index
        if let builtIn = BuiltInPluginRegistry.manifest(id: id) {
            guard builtIn.kind != .documentFormat else { return }
            if enabled { candidate.disabledBuiltIns.remove(id) } else { candidate.disabledBuiltIns.insert(id) }
        } else {
            guard let position = candidate.installed.firstIndex(where: { $0.manifest.plugin.id == id }) else { return }
            guard !enabled || errors[id] == nil else { throw PluginPackageError.invalidManifest }
            candidate.installed[position].enabled = enabled
        }
        try persist(candidate)
        index = candidate
        registry.setEnabled(enabled, id: id)
    }

    public mutating func uninstall(id: String) throws {
        guard let item = index.installed.first(where: { $0.manifest.plugin.id == id }) else { return }
        var candidate = index
        candidate.installed.removeAll { $0.manifest.plugin.id == id }
        try persist(candidate)
        index = candidate
        registry.uninstall(id: id)
        errors[id] = nil
        if owns(item.packageURL), FileManager.default.fileExists(atPath: item.packageURL.path) {
            try FileManager.default.removeItem(at: item.packageURL)
        }
    }

    private func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == directory.path &&
        url.pathExtension == PluginPackageManifest.packageExtension &&
        UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }

    private func persist(_ candidate: Index) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(candidate).write(to: directory.appendingPathComponent("registry.json"), options: .atomic)
    }
}

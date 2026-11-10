import Foundation
import Testing
@testable import OpenSketchCore

struct PluginRuntimeTests {
    @Test func taskManagerReportsProgressAndHonorsCancellation() async {
        let manager = PluginTaskManager()
        let started = await manager.start(pluginID: "org.example.task")
        #expect(started.state == .running)
        await manager.update(started.task.id, state: .running, fraction: 0.5, message: "Half way")
        #expect(await manager.progress(for: started.task.id)?.fraction == 0.5)
        #expect(await manager.cancel(started.task.id))
        #expect(await manager.progress(for: started.task.id)?.state == .cancelled)
        #expect(!(await manager.cancel(started.task.id)))
    }

    @Test func registryReplacesVersionsAndCanDisableExternalPlugin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenSketchRegistry-\(UUID().uuidString)")
        let packageURL = root.appendingPathComponent("Demo.\(PluginPackageManifest.packageExtension)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PluginPackageManifest(plugin: PluginManifest(id: "org.example.registry", name: "Registry", kind: .operation), entrypoint: "Contents/Main")
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("plugin.json"))
        try Data("main".utf8).write(to: root.appendingPathComponent("Contents/Main"))
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.currentDirectoryURL = root
        zip.arguments = ["-q", "-r", packageURL.path, "plugin.json", "Contents"]
        try zip.run(); zip.waitUntilExit()
        let package = try PluginPackage.load(from: packageURL)
        var registry = PluginRegistry()
        _ = registry.install(package)
        let disabled = registry.setEnabled(false, id: manifest.plugin.id)
        #expect(disabled)
        #expect(registry.plugin(id: manifest.plugin.id)?.enabled == false)
        _ = registry.install(package)
        #expect(registry.installed.count == 1)
        let removed = registry.uninstall(id: manifest.plugin.id)
        #expect(removed)
        #expect(registry.installed.isEmpty)
    }
}

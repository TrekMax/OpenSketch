import Foundation
import Testing
@testable import OpenSketchCore

struct PluginLibraryTests {
    private func package(at root: URL, id: String = "org.example.library") throws -> URL {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let manifest = PluginPackageManifest(plugin: PluginManifest(id: id, name: "Library Test", kind: .operation), entrypoint: "Contents/Main")
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("plugin.json"))
        try Data("entry".utf8).write(to: root.appendingPathComponent("Contents/Main"))
        let url = root.appendingPathComponent("Source.opskplugin")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", url.path, "plugin.json", "Contents"]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return url
    }

    @Test func installationSurvivesReloadAndUninstallPreservesSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root)
        let directory = root.appendingPathComponent("Installed")
        var library = try PluginLibrary(directory: directory)
        try library.install(from: source)
        let installed = try #require(library.installed.first)
        #expect(installed.packageURL != source)
        try library.setEnabled(false, id: installed.manifest.plugin.id)
        // Updating retains the user's disabled state and removes only the old owned copy.
        try library.install(from: source)
        #expect(!FileManager.default.fileExists(atPath: installed.packageURL.path))
        library = try PluginLibrary(directory: directory)
        #expect(library.registry.plugin(id: installed.manifest.plugin.id)?.enabled == false)
        let copy = try #require(library.installed.first?.packageURL)
        try library.uninstall(id: installed.manifest.plugin.id)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(try PluginLibrary(directory: directory).installed.isEmpty)
    }

    @Test func brokenInstalledPackageIsVisibleButNotRegistered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root)
        let directory = root.appendingPathComponent("Installed")
        var library = try PluginLibrary(directory: directory)
        try library.install(from: source)
        let item = try #require(library.installed.first)
        try FileManager.default.removeItem(at: item.packageURL)
        library = try PluginLibrary(directory: directory)
        #expect(library.installed.count == 1)
        #expect(library.registry.installed.isEmpty)
        #expect(library.errors[item.manifest.plugin.id] != nil)
        try library.uninstall(id: item.manifest.plugin.id)
        #expect(library.installed.isEmpty)
    }

    @Test func builtInIdentityCannotBeReplacedOrDocumentFormatDisabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root, id: "org.opensketch.format.document")
        var library = try PluginLibrary(directory: root.appendingPathComponent("Installed"))
        #expect(throws: PluginPackageError.invalidManifest) { try library.install(from: source) }
        try library.setEnabled(false, id: "org.opensketch.format.document")
        #expect(library.disabledBuiltIns.isEmpty)
        try library.setEnabled(false, id: "org.opensketch.export.png")
        #expect(try PluginLibrary(directory: library.directory).disabledBuiltIns.contains("org.opensketch.export.png"))
    }
}

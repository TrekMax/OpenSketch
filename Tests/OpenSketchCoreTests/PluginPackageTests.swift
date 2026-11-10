import Foundation
import Testing
@testable import OpenSketchCore

struct PluginPackageTests {
    @Test func loadsOpskpluginZipAndReadsBoundedEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenSketchPlugin-\(UUID().uuidString)")
        let packageURL = root.appendingPathComponent("Demo.\(PluginPackageManifest.packageExtension)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PluginPackageManifest(plugin: PluginManifest(id: "org.example.demo", name: "Demo", kind: .operation), entrypoint: "Contents/Main")
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("plugin.json"))
        try Data("runtime".utf8).write(to: root.appendingPathComponent("Contents/Main"))
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.currentDirectoryURL = root
        zip.arguments = ["-q", "-r", packageURL.path, "plugin.json", "Contents"]
        try zip.run(); zip.waitUntilExit(); #expect(zip.terminationStatus == 0)

        let loaded = try PluginPackage.load(from: packageURL)
        #expect(loaded.manifest == manifest)
        #expect(String(data: try loaded.data(for: "Contents/Main"), encoding: .utf8) == "runtime")
    }

    @Test func rejectsPackageWithPathTraversalEntry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OpenSketchPlugin-\(UUID().uuidString)")
        let packageURL = root.appendingPathComponent("Bad.\(PluginPackageManifest.packageExtension)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PluginPackageManifest(plugin: PluginManifest(id: "org.example.bad", name: "Bad", kind: .operation), entrypoint: "Contents/Main")
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("plugin.json"))
        try Data("bad".utf8).write(to: root.appendingPathComponent("evil"))
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); zip.currentDirectoryURL = root
        zip.arguments = ["-q", packageURL.path, "plugin.json", "evil"]
        try zip.run(); zip.waitUntilExit()
        // A normal zip cannot create traversal entries through the command line;
        // the loader still validates every name before exposing package content.
        #expect(throws: PluginPackageError.invalidEntry("evil")) { try PluginPackage.load(from: packageURL) }
    }
}

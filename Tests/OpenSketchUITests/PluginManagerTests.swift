import AppKit
import Testing
import OpenSketchCore
@testable import OpenSketchUI

@MainActor struct PluginManagerTests {
    @Test func toolbarIncludesPluginManagerAndWindowIsReusable() throws {
        _ = NSApplication.shared
        let controller = AppController()
        let identifiers = controller.toolbarDefaultItemIdentifiers(NSToolbar(identifier: "test"))
        #expect(identifiers.contains(NSToolbarItem.Identifier("plugin.manager")))
        controller.showPluginManager(nil)
        let first = try #require(controller.pluginManagerController?.window)
        defer { first.close() }
        controller.showPluginManager(nil)
        #expect(controller.pluginManagerController?.window === first)
        #expect(first.identifier?.rawValue == "plugins.window")
    }

    @Test func applicationMenuIncludesPluginManager() throws {
        _ = NSApplication.shared
        let controller = AppController()
        controller.makeMenus()
        let appMenu = try #require(controller.applicationMenu?.items.first?.submenu)
        let item = try #require(appMenu.items.first(where: { $0.action == #selector(AppController.showPluginManager(_:)) }))
        #expect(item.title == L10n.text("插件管理器"))
    }

    @Test func pluginManagerSeparatesBuiltInAndExternalItems() {
        let model = PluginManagerModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(!model.builtInItems.isEmpty)
        #expect(model.externalItems.isEmpty)
        #expect(model.builtInItems.allSatisfy { $0.packageURL == nil })
    }

    @Test func previewSyncCapturesPageAndDisconnectClearsDisplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PluginManagerModel(directory: directory)
        let session = EditorSession(document: DesignDocument(pages: [DesignPage(nodes: [DesignNode(name: "Preview", kind: .rectangle)])]))
        model.currentSession = { session }
        let original = session.document
        await model.refreshRuntime()
        let device = try #require(model.devices.first?.device)
        await model.connectDevice(device.id)
        let taskID = try #require(await model.syncDevice(device.id))
        await model.workers[taskID]?.value
        #expect(model.tasks.first { $0.task.id == taskID }?.state == .completed)
        #expect(await model.previewBackend.snapshot(device.id)?.page == original.pages[0])
        #expect(model.previewImages[device.id] != nil)
        #expect(session.document == original)
        #expect(!session.canUndo)
        await model.disconnectDevice(device.id)
        #expect(model.devices.first?.device.isConnected == false)
        #expect(model.previewImages[device.id] == nil)
    }

    @Test func disabledPreviewCannotConnectAndExportStatePersists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PluginManagerModel(directory: directory)
        model.setEnabled(false, id: PluginManagerModel.previewPluginID)
        model.setEnabled(false, id: "org.opensketch.export.png")
        await model.refreshRuntime()
        let device = try #require(model.devices.first?.device)
        await model.connectDevice(device.id)
        #expect(model.lastError != nil)
        #expect(model.devices.first?.device.isConnected == false)
        let restored = PluginManagerModel(directory: directory)
        #expect(throws: (any Error).self) { try restored.requireEnabled("org.opensketch.export.png") }
    }

    @Test func auditTracksOpenSessionsAndRejectedOperations() throws {
        let model = PluginManagerModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = EditorSession()
        model.sessions = { [session] }
        let plugin = PluginManifest(id: "org.example.audit", name: "Audit", kind: .operation, capabilities: [.readDocument])
        let plan = PluginOperationPlan(source: "test", operations: [PluginOperation(kind: .queryDocument)])
        #expect(!session.applyPluginPlan(plan, plugin: plugin, approved: false))
        #expect(model.auditEvents.count == 1)
        #expect(model.auditEvents.first?.approved == false)
        model.sessions = { [] }
        #expect(model.auditEvents.isEmpty)
    }

    @Test func cancellationCannotBeOverwrittenByLateCompletion() async throws {
        let model = PluginManagerModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let task = await model.taskManager.start(pluginID: PluginManagerModel.previewPluginID)
        await model.cancelTask(task.task.id)
        await model.taskManager.update(task.task.id, state: .completed, fraction: 1)
        await model.refreshRuntime()
        #expect(model.tasks.first?.state == .cancelled)
    }

    @Test func cancelledSyncNeverPublishesSnapshot() async throws {
        let model = PluginManagerModel(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = EditorSession()
        model.currentSession = { session }
        await model.refreshRuntime()
        let device = try #require(model.devices.first?.device)
        await model.connectDevice(device.id)
        let taskID = try #require(await model.syncDevice(device.id))
        let worker = try #require(model.workers[taskID])
        await model.cancelTask(taskID)
        await worker.value
        #expect(await model.previewBackend.snapshot(device.id) == nil)
        #expect(model.previewImages[device.id] == nil)
        #expect(model.tasks.first { $0.task.id == taskID }?.state == .cancelled)
        #expect(model.deviceTasks.isEmpty)
    }
}

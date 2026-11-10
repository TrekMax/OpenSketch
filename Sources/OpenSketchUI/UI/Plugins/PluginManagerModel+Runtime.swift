import AppKit
import OpenSketchCore

extension PluginManagerModel {
    static let previewPluginID = "org.opensketch.preview.local"

    func refreshRuntime() async {
        tasks = await taskManager.all().sorted { $0.task.startedAt > $1.task.startedAt }
        var statuses: [DevicePreviewStatus] = []
        for device in await previewBackend.discover() {
            if let status = await previewBackend.status(device.id) { statuses.append(status) }
        }
        devices = statuses
    }

    func cancelTask(_ id: UUID) async {
        workers[id]?.cancel()
        _ = await taskManager.cancel(id)
        await refreshRuntime()
    }

    func cancelTasks(pluginID: String) {
        // Cancel workers immediately, before the next actor suspension can commit output.
        for progress in tasks where progress.task.pluginID == pluginID { workers[progress.task.id]?.cancel() }
        Task {
            for progress in await taskManager.all() where progress.task.pluginID == pluginID {
                await cancelTask(progress.task.id)
            }
            if pluginID == Self.previewPluginID {
                for device in await previewBackend.discover() { await previewBackend.disconnect(device.id) }
                previewImages.removeAll()
                await refreshRuntime()
            }
        }
    }

    func connectDevice(_ id: UUID) async {
        do {
            try requireEnabled(Self.previewPluginID)
            _ = try await previewBackend.connect(id)
            lastError = nil
        } catch { lastError = L10n.errorDescription(error) }
        await refreshRuntime()
    }

    func disconnectDevice(_ id: UUID) async {
        if let taskID = deviceTasks[id] { await cancelTask(taskID) }
        await previewBackend.disconnect(id)
        previewImages[id] = nil
        await refreshRuntime()
    }

    /// Capture the initiating document before scheduling. Switching tabs cannot
    /// change what a pending sync sends to the backend.
    @discardableResult
    func syncDevice(_ id: UUID) async -> UUID? {
        guard deviceTasks[id] == nil else { return nil }
        do {
            try requireEnabled(Self.previewPluginID)
            guard let session = currentSession() else { throw EditorError.invalid("没有可预览的文档。") }
            session.finishInput?()
            let snapshot = DevicePreviewSnapshot(documentID: session.document.id, page: session.page)
            let prepared = try ExportSnapshot.make(page: snapshot.page, selection: [], scope: .page)
            deviceTasks[id] = UUID()
            let progress = await taskManager.start(pluginID: Self.previewPluginID)
            let taskID = progress.task.id
            deviceTasks[id] = taskID
            tasks.insert(progress, at: 0)
            workers[taskID] = Task { [self] in
                defer { workers[taskID] = nil; deviceTasks[id] = nil }
                do {
                    try Task.checkCancellation()
                    try requireEnabled(Self.previewPluginID)
                    await taskManager.update(taskID, state: .running, fraction: 0.2, message: "正在渲染预览")
                    await refreshRuntime()
                    try Task.checkCancellation()
                    // AppKit rendering stays on the main actor; cancellation is
                    // checked again before publishing the rendered snapshot.
                    let data = try Exporter.png(page: prepared.page, bounds: prepared.bounds, scale: 1)
                    await taskManager.update(taskID, state: .running, fraction: 0.8, message: "正在同步快照")
                    await refreshRuntime()
                    try Task.checkCancellation()
                    try requireEnabled(Self.previewPluginID)
                    _ = try await previewBackend.sync(snapshot, to: id)
                    if !Task.isCancelled { previewImages[id] = NSImage(data: data) }
                    await taskManager.update(taskID, state: .completed, fraction: 1)
                } catch is CancellationError {
                    _ = await taskManager.cancel(taskID)
                } catch {
                    let message = L10n.errorDescription(error)
                    await taskManager.update(taskID, state: .failed, fraction: 0, error: message)
                    lastError = message
                }
                await refreshRuntime()
            }
            return taskID
        } catch { lastError = L10n.errorDescription(error); return nil }
    }

    func recordExport(pluginID: String, error: String? = nil) {
        Task {
            let progress = await taskManager.start(pluginID: pluginID, cancellable: false)
            await taskManager.update(progress.task.id, state: error == nil ? .completed : .failed,
                                     fraction: error == nil ? 1 : 0, error: error)
            await refreshRuntime()
        }
    }
}

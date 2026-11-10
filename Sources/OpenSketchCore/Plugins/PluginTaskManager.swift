import Foundation

/// Small actor-backed lifecycle store shared by built-in and external hosts.
public actor PluginTaskManager {
    private var tasks: [UUID: PluginTaskProgress] = [:]

    public init() {}

    @discardableResult
    public func start(pluginID: String, cancellable: Bool = true) -> PluginTaskProgress {
        let progress = PluginTaskProgress(task: PluginTask(pluginID: pluginID, cancellable: cancellable), state: .running)
        tasks[progress.task.id] = progress
        return progress
    }

    public func update(_ id: UUID, state: PluginTaskState, fraction: Double, message: String? = nil, error: String? = nil) {
        guard var progress = tasks[id], progress.state != .completed, progress.state != .failed, progress.state != .cancelled else { return }
        progress.state = state; progress.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        progress.message = message; progress.error = error
        tasks[id] = progress
    }

    @discardableResult
    public func cancel(_ id: UUID) -> Bool {
        guard var progress = tasks[id], progress.task.cancellable, progress.state == .running || progress.state == .queued else { return false }
        progress.state = .cancelled; progress.message = "Cancelled"; tasks[id] = progress; return true
    }

    public func progress(for id: UUID) -> PluginTaskProgress? { tasks[id] }
    public func all() -> [PluginTaskProgress] { Array(tasks.values) }
}

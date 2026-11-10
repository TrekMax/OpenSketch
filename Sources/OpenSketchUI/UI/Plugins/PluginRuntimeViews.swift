import SwiftUI
import OpenSketchCore

struct PluginTasksView: View {
    @Bindable var model: PluginManagerModel

    var body: some View {
        List {
            if model.tasks.isEmpty { Text(L10n.text("暂无任务记录")).foregroundStyle(.secondary) }
            ForEach(model.tasks, id: \.task.id) { progress in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.items.first { $0.id == progress.task.pluginID }?.manifest.name ?? progress.task.pluginID)
                        Spacer()
                        Text(progress.task.startedAt, style: .time).foregroundStyle(.secondary)
                        Text(taskState(progress.state))
                        if progress.task.cancellable && [.running, .queued].contains(progress.state) {
                            Button(L10n.text("取消")) { Task { await model.cancelTask(progress.task.id) } }
                        }
                    }
                    ProgressView(value: progress.fraction)
                    if let message = progress.message { Text(L10n.text(message)).foregroundStyle(.secondary) }
                    if let error = progress.error { Text(error).foregroundStyle(.red) }
                }.padding(.vertical, 6)
            }
        }
    }

    private func taskState(_ state: PluginTaskState) -> String {
        let key = switch state {
        case .queued: "等待中"
        case .running: "运行中"
        case .cancelling: "正在取消"
        case .completed: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
        return L10n.text(key)
    }
}

struct PluginAuditView: View {
    @Bindable var model: PluginManagerModel

    var body: some View {
        List {
            Text(L10n.text("当前打开文档的操作记录")).foregroundStyle(.secondary)
            if model.auditEvents.isEmpty { Text(L10n.text("暂无审计记录")).foregroundStyle(.secondary) }
            ForEach(Array(model.auditEvents.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.pluginID)
                        Spacer()
                        Text(L10n.text(event.approved ? "已批准" : "未执行"))
                    }
                    HStack {
                        Text(event.operation.rawValue)
                        Spacer()
                        Text(event.timestamp, style: .date)
                        Text(event.timestamp, style: .time)
                    }.foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PluginDevicesView: View {
    @Bindable var model: PluginManagerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("本地只读预览；同步当前页面快照。")).foregroundStyle(.secondary)
                ForEach(model.devices, id: \.device.id) { status in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(status.device.name, systemImage: "display")
                                Spacer()
                                Text(L10n.text(status.device.isConnected ? "已连接" : "已断开"))
                            }
                            HStack {
                                if status.device.isConnected {
                                    Button(L10n.text("断开")) { Task { await model.disconnectDevice(status.device.id) } }
                                    Button(L10n.text("同步当前页面")) { Task { await model.syncDevice(status.device.id) } }
                                        .disabled(model.deviceTasks[status.device.id] != nil)
                                } else {
                                    Button(L10n.text("连接设备")) { Task { await model.connectDevice(status.device.id) } }
                                }
                                if let taskID = model.deviceTasks[status.device.id] {
                                    Button(L10n.text("取消")) { Task { await model.cancelTask(taskID) } }
                                }
                            }
                            if let revision = status.lastRevision {
                                Text(L10n.text("快照版本") + ": " + revision.uuidString).font(.caption).textSelection(.enabled)
                            }
                            if let image = model.previewImages[status.device.id] {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                                    .accessibilityLabel(L10n.text("当前页面预览"))
                            }
                        }.padding(8)
                    }
                }
            }.padding()
        }
    }
}

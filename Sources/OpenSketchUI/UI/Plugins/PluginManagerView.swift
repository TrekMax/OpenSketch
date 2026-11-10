import SwiftUI
import OpenSketchCore

struct PluginManagerView: View {
    @Bindable var model: PluginManagerModel
    @State private var selectedID: String?
    @State private var tab = 0

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    Section {
                        ForEach(model.builtInItems) { item in itemRow(item) }
                    } header: {
                        Text(L10n.text("内建插件"))
                    }

                    Divider().padding(.vertical, 4)

                    Section {
                        if model.externalItems.isEmpty {
                            Text(L10n.text("暂无外部扩展插件"))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                                .accessibilityIdentifier("plugin.external.empty")
                        } else {
                            ForEach(model.externalItems) { item in itemRow(item) }
                        }
                    } header: {
                        Text(L10n.text("外部扩展插件"))
                    }
                }
                .listStyle(.sidebar)

                Divider()
                Button {
                    model.chooseAndInstall()
                } label: {
                    Label(L10n.text("导入插件…"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityIdentifier("plugin.import")
            }
            .navigationTitle(L10n.text("插件"))
        } detail: {
            VStack(spacing: 0) {
                if let error = model.lastError {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        Spacer()
                        Button(L10n.text("关闭")) { model.lastError = nil }
                    }.padding()
                }
                Picker(L10n.text("插件管理器"), selection: $tab) {
                    Text(L10n.text("插件信息")).tag(0)
                    Text(L10n.text("任务记录")).tag(1)
                    Text(L10n.text("审计记录")).tag(2)
                    Text(L10n.text("设备预览")).tag(3)
                }.pickerStyle(.segmented).padding()
                switch tab {
                case 1: PluginTasksView(model: model)
                case 2: PluginAuditView(model: model)
                case 3: PluginDevicesView(model: model)
                default: pluginDetail
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(L10n.text("安装插件"), systemImage: "plus") { model.chooseAndInstall() }
                    .accessibilityIdentifier("plugin.install")
                Button(L10n.text("刷新"), systemImage: "arrow.clockwise") {
                    Task { await model.refreshRuntime() }
                }
            }
        }
        .task { await model.refreshRuntime() }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder private var pluginDetail: some View {
        if let id = selectedID, let item = model.items.first(where: { $0.id == id }) {
            PluginDetailView(item: item, model: model)
        } else if let item = model.items.first {
            PluginDetailView(item: item, model: model)
        } else {
            Text(L10n.text("暂无插件"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PluginManagerModel.Item) -> some View {
        HStack {
            Label(item.manifest.name, systemImage: item.manifest.kind == .exporter ? "arrow.up.doc" : "puzzlepiece.extension")
            Spacer()
            Circle().fill(item.error != nil ? .red : item.enabled ? .green : .gray).frame(width: 7, height: 7)
        }
        .tag(item.id)
        .accessibilityIdentifier("plugin.\(item.id)")
    }
}

private struct PluginDetailView: View {
    let item: PluginManagerModel.Item
    @Bindable var model: PluginManagerModel

    var body: some View {
        Form {
            Section(L10n.text("插件信息")) {
                LabeledContent(L10n.text("名称"), value: item.manifest.name)
                LabeledContent(L10n.text("标识"), value: item.manifest.id)
                LabeledContent(L10n.text("版本"), value: item.manifest.version)
                LabeledContent(L10n.text("类型"), value: item.manifest.kind.rawValue)
                LabeledContent(L10n.text("API 版本"), value: String(item.manifest.apiVersion))
                Toggle(L10n.text("启用"), isOn: Binding(get: { item.enabled }, set: { model.setEnabled($0, id: item.id) }))
                    .disabled(item.manifest.kind == .documentFormat && item.packageURL == nil)
                if let error = item.error { Text(error).foregroundStyle(.red) }
                if item.packageURL != nil {
                    Text(L10n.text("已注册；外部代码执行尚未接入。")).foregroundStyle(.secondary)
                    Button(L10n.text("卸载插件"), role: .destructive) { model.uninstall(id: item.id) }
                }
            }
            Section(L10n.text("能力")) {
                ForEach(item.manifest.capabilities.sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { capability in
                    Label(capability.rawValue, systemImage: "checkmark.circle")
                }
            }
            Section(L10n.text("格式")) {
                ForEach(item.manifest.fileTypes, id: \.extensionName) { fileType in
                    Text(".\(fileType.extensionName)")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(item.manifest.name)
    }
}

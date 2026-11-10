import SwiftUI
import OpenSketchCore

struct PluginManagerView: View {
    @Bindable var model: PluginManagerModel
    @State private var selectedID: String?

    var body: some View {
        NavigationSplitView {
            List(model.items, selection: $selectedID) { item in
                HStack {
                    Label(item.manifest.name, systemImage: item.manifest.kind == .exporter ? "arrow.up.doc" : "puzzlepiece.extension")
                    Spacer()
                    Circle().fill(item.enabled ? .green : .gray).frame(width: 7, height: 7)
                }
                .tag(item.id)
                .accessibilityIdentifier("plugin.\(item.id)")
            }
            .navigationTitle(L10n.text("插件"))
        } detail: {
            if let id = selectedID, let item = model.items.first(where: { $0.id == id }) {
                PluginDetailView(item: item, model: model)
            } else if let item = model.items.first {
                PluginDetailView(item: item, model: model)
            } else {
                Text(L10n.text("暂无插件"))
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(L10n.text("安装插件"), systemImage: "plus") { model.chooseAndInstall() }
                    .accessibilityIdentifier("plugin.install")
            }
        }
        .frame(minWidth: 700, minHeight: 440)
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

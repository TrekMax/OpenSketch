import SwiftUI
import OpenSketchCore

struct PluginManagerView: View {
    let manifests: [PluginManifest]

    var body: some View {
        NavigationSplitView {
            List(manifests, id: \.id) { manifest in
                Label(manifest.name, systemImage: manifest.kind == .exporter ? "arrow.up.doc" : "puzzlepiece.extension")
                    .tag(manifest.id)
                    .accessibilityIdentifier("plugin.\(manifest.id)")
            }
            .navigationTitle(L10n.text("插件"))
        } detail: {
            if let manifest = manifests.first {
                PluginDetailView(manifest: manifest)
            } else {
                Text(L10n.text("暂无插件"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 440)
    }
}

private struct PluginDetailView: View {
    let manifest: PluginManifest

    var body: some View {
        Form {
            Section(L10n.text("插件信息")) {
                LabeledContent(L10n.text("名称"), value: manifest.name)
                LabeledContent(L10n.text("标识"), value: manifest.id)
                LabeledContent(L10n.text("版本"), value: manifest.version)
                LabeledContent(L10n.text("类型"), value: manifest.kind.rawValue)
                LabeledContent(L10n.text("API 版本"), value: String(manifest.apiVersion))
            }
            Section(L10n.text("能力")) {
                ForEach(manifest.capabilities.sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { capability in
                    Label(capability.rawValue, systemImage: "checkmark.circle")
                }
            }
            Section(L10n.text("格式")) {
                ForEach(manifest.fileTypes, id: \.extensionName) { fileType in
                    Text(".\(fileType.extensionName)")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(manifest.name)
    }
}

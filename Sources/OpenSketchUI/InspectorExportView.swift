import SwiftUI

struct InspectorExportView: View {
    @Bindable var session: EditorSession
    var export: (() -> Void)?

    private var preview: Result<PreparedExport, any Error> { Result { try session.prepareExport() } }
    private var scope: Binding<ExportScope> {
        Binding(get: { session.exportOptions.resolvedScope(selection: session.selection) },
                set: { session.exportOptions.scope = $0 })
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 10) {
            Text("导出").font(.system(size: 11, weight: .semibold))
            Picker("范围", selection: scope) {
                Text("当前选择").tag(ExportScope.selection).disabled(session.selection.isEmpty)
                Text("当前页面").tag(ExportScope.page)
            }.accessibilityIdentifier("export.scope")
            Picker("格式", selection: $session.exportOptions.format) {
                Text("PNG").tag(ExportFormat.png)
                Text("PDF").tag(ExportFormat.pdf)
            }.accessibilityIdentifier("export.format")
            if session.exportOptions.format == .png {
                Picker("倍率", selection: $session.exportOptions.scale) {
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("3×").tag(3.0)
                }.accessibilityIdentifier("export.scale")
            }
            switch preview {
            case .success(let prepared):
                let size = prepared.dimensions
                Text(prepared.options.format == .png
                     ? "\(size.width.formatted()) × \(size.height.formatted()) 像素"
                     : "\(size.width.formatted()) × \(size.height.formatted()) 点 · 1×")
                    .foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityIdentifier("export.dimensions")
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("export.error")
            }
            Button("导出…") { export?() }
                .frame(maxWidth: .infinity)
                .disabled(export == nil || (try? preview.get()) == nil)
                .accessibilityIdentifier("export.action")
        }
        .font(.system(size: 11)).controlSize(.small)
    }
}

import SwiftUI

struct InspectorExportView: View {
    @Bindable var session: EditorSession
    var export: (() -> Void)?

    private var preview: Result<PreparedExport, any Error> { Result { try session.prepareExport() } }
    private var scope: ExportScope { session.exportOptions.resolvedScope(selection: session.selection) }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("导出")).font(.system(size: 11, weight: .semibold))
            HStack {
                Text(L10n.text("范围"))
                // Use actions so the native menu receives each item’s disabled state.
                Menu {
                    Button(L10n.text("当前选择")) {
                        guard !session.selection.isEmpty else { return }
                        session.exportOptions.scope = .selection
                    }.disabled(session.selection.isEmpty)
                    Button(L10n.text("当前页面")) { session.exportOptions.scope = .page }
                } label: {
                    Text(scope == .selection ? L10n.text("当前选择") : L10n.text("当前页面"))
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.text("范围"))
                .accessibilityIdentifier("export.scope")
            }
            Picker(L10n.text("格式"), selection: $session.exportOptions.format) {
                Text("PNG").tag(ExportFormat.png)
                Text("PDF").tag(ExportFormat.pdf)
                Text("SVG").tag(ExportFormat.svg)
            }.accessibilityIdentifier("export.format")
            if session.exportOptions.format == .png {
                Picker(L10n.text("倍率"), selection: $session.exportOptions.scale) {
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("3×").tag(3.0)
                }.accessibilityIdentifier("export.scale")
            }
            switch preview {
            case .success(let prepared):
                let size = prepared.dimensions
                Text(prepared.options.format == .png
                     ? L10n.format("%@ × %@ 像素", Double(size.width).formatted(.number.locale(L10n.locale)), Double(size.height).formatted(.number.locale(L10n.locale)))
                     : L10n.format("%@ × %@ 点 · 1×", Double(size.width).formatted(.number.locale(L10n.locale)), Double(size.height).formatted(.number.locale(L10n.locale))))
                    .foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityIdentifier("export.dimensions")
            case .failure(let error):
                Text(L10n.errorDescription(error)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("export.error")
            }
            Button(L10n.text("导出…")) { export?() }
                .frame(maxWidth: .infinity)
                .disabled(export == nil || (try? preview.get()) == nil)
                .accessibilityIdentifier("export.action")
        }
        .font(.system(size: 11)).controlSize(.small)
    }
}

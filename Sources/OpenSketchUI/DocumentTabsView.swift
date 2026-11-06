import SwiftUI

struct DocumentTabsView: View {
    @Bindable var workspace: DocumentWorkspace
    var width: CGFloat
    var select: (UUID) -> Void
    var close: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(workspace.documents) { document in
                        HStack(spacing: 0) {
                            Button { select(document.id) } label: {
                                HStack(spacing: 6) {
                                    if document.session.isDirty {
                                        Circle().fill(.secondary).frame(width: 6, height: 6)
                                            .accessibilityHidden(true)
                                    }
                                    Text(document.title)
                                        .font(.system(size: 12, weight: workspace.currentID == document.id ? .semibold : .regular))
                                        .lineLimit(1).truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.leading, 10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("切换到“\(document.title)”")
                            .accessibilityValue(document.session.isDirty ? "未保存" : "已保存")
                            .accessibilityAddTraits(workspace.currentID == document.id ? .isSelected : [])
                            .accessibilityIdentifier("document.tab.switch.\(document.id)")
                            .help(document.session.url?.path ?? document.title)

                            Button { close(document.id) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 26, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("关闭“\(document.title)”")
                            .accessibilityIdentifier("document.tab.close.\(document.id)")
                            .help("关闭“\(document.session.url?.lastPathComponent ?? document.title)”")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(workspace.currentID == document.id ? EditorPalette.selectionForeground(colorScheme) : .primary)
                        .frame(width: 160, height: 28)
                        .background(workspace.currentID == document.id ? EditorPalette.selection(colorScheme) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tabBorder(selected: workspace.currentID == document.id), lineWidth: 1))
                        .id(document.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: workspace.currentID, initial: true) { _, id in
                proxy.scrollTo(id, anchor: .trailing)
            }
            .onChange(of: width) { _, _ in
                proxy.scrollTo(workspace.currentID, anchor: .trailing)
            }
            .onChange(of: workspace.documents.map(\.id)) { _, _ in
                proxy.scrollTo(workspace.currentID, anchor: .trailing)
            }
        }
        .frame(width: width, height: 32)
        .accessibilityIdentifier("document.tabs")
    }

    private func tabBorder(selected: Bool) -> Color {
        if colorScheme == .dark { return .primary.opacity(selected ? 0.18 : 0.07) }
        return selected ? Color(nsColor: EditorPalette.accent).opacity(0.2) : Color(nsColor: EditorPalette.separator)
    }
}

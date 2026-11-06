import SwiftUI

struct SidebarRenameSheet: View {
    let session: EditorSession
    let request: SidebarRenameRequest
    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(session: EditorSession, request: SidebarRenameRequest) {
        self.session = session
        self.request = request
        _name = State(initialValue: request.originalName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.target.title).font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .accessibilityIdentifier("rename.name")
                .onSubmit(save)
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rename.error")
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("rename.cancel")
                Button("重命名", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("rename.confirm")
            }
        }
        .padding(20).frame(width: 360)
        .onAppear { nameFocused = true }
        .onChange(of: name) { _, _ in errorMessage = nil }
    }

    private func save() {
        do {
            try session.commitSidebarRename(request, name: name)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

import AppKit
import SwiftUI

struct SidebarRenameField: NSViewRepresentable {
    let session: EditorSession
    let request: SidebarRenameRequest

    func makeNSView(context: Context) -> NativeSidebarRenameField {
        NativeSidebarRenameField(session: session, request: request)
    }
    func updateNSView(_ view: NativeSidebarRenameField, context: Context) {}
    static func dismantleNSView(_ view: NativeSidebarRenameField, coordinator: ()) { view.finish() }
}

/// Uses the native field editor for selection, clipboard, text undo and IME input.
@MainActor final class NativeSidebarRenameField: NSTextField, NSTextFieldDelegate {
    private weak var session: EditorSession?
    private let requestID: UUID

    init(session: EditorSession, request: SidebarRenameRequest) {
        self.session = session
        requestID = request.id
        super.init(frame: .zero)
        stringValue = request.originalName
        delegate = self
        isEditable = true; isSelectable = true
        isBezeled = true; bezelStyle = .roundedBezel
        focusRingType = .none
        font = .systemFont(ofSize: 12)
        textColor = .labelColor; backgroundColor = EditorPalette.inspectorControl
        usesSingleLineMode = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityIdentifier("rename.name")
        setAccessibilityLabel(request.target.title)
        if session.sidebarRename?.request.id == requestID {
            session.sidebarRenameText = { [weak self] in
                guard let self, self.session?.sidebarRename?.request.id == self.requestID else { return nil }
                return self.currentEditor()?.string ?? self.stringValue
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Wait for the context menu and SwiftUI row replacement to finish.
        Task { @MainActor [weak self] in
            guard let self, self.window != nil,
                  self.session?.sidebarRename?.request.id == self.requestID else { return }
            self.selectText(nil)
        }
    }
    func controlTextDidChange(_ notification: Notification) { updateDraft() }
    func controlTextDidEndEditing(_ notification: Notification) { finish() }

    private func updateDraft() {
        session?.updateSidebarRename(requestID, name: currentEditor()?.string ?? stringValue)
    }
    func finish(cancel: Bool = false) {
        if !cancel { updateDraft() }
        session?.finishSidebarRename(token: requestID, cancel: cancel)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        let cancel = commandSelector == #selector(NSResponder.cancelOperation(_:))
        guard cancel || commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        finish(cancel: cancel)
        if window?.firstResponder === textView { window?.makeFirstResponder(nil) }
        return true
    }
}

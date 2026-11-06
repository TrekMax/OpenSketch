import AppKit
import SwiftUI

struct InspectorNumberField: NSViewRepresentable {
    var session: EditorSession
    var nodeID: UUID
    var property: InspectorNumberProperty

    func makeNSView(context: Context) -> InspectorNumberControl { InspectorNumberControl(frame: .zero) }
    func updateNSView(_ view: InspectorNumberControl, context: Context) {
        // Observe the document so a scrub, undo or external edit refreshes the native field.
        _ = session.document; _ = session.selection
        view.configure(session: session, nodeID: nodeID, property: property)
    }
    static func dismantleNSView(_ view: InspectorNumberControl, coordinator: ()) { view.endInput() }
}

/// A native field editor beside a separately draggable label. It never captures the
/// AppKit event loop, so Escape, menus and window notifications remain responsive.
@MainActor final class InspectorNumberControl: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    let scrubLabel = InspectorScrubLabel(labelWithString: "")
    private weak var session: EditorSession?
    private var nodeID: UUID?
    private var property: InspectorNumberProperty = .x
    private var textToken: UUID?
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 6
        field.isBordered = false; field.drawsBackground = false
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.alignment = .right; field.focusRingType = .none
        field.delegate = self
        scrubLabel.font = .systemFont(ofSize: 11)
        scrubLabel.textColor = .secondaryLabelColor
        scrubLabel.owner = self
        addSubview(scrubLabel); addSubview(field)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 26) }
    override func layout() {
        super.layout()
        let labelWidth: CGFloat = property.label.count > 1 ? 30 : 18
        scrubLabel.frame = CGRect(x: 7, y: (bounds.height - 18) / 2, width: labelWidth, height: 18)
        field.frame = CGRect(x: labelWidth + 9, y: (bounds.height - 18) / 2,
                             width: max(20, bounds.width - labelWidth - 16), height: 18)
    }
    func configure(session: EditorSession, nodeID: UUID, property: InspectorNumberProperty) {
        if self.session !== session || self.nodeID != nodeID || self.property != property {
            endInput()
            // A reused representable must not keep the old node's field editor.
            if field.currentEditor() != nil { window?.makeFirstResponder(nil) }
            self.session = session; self.nodeID = nodeID; self.property = property
        }
        guard let node = session.document.node(id: nodeID) else { return }
        let editable = property.canEdit(node) && session.editable(nodeID)
        field.isEditable = editable; field.isSelectable = true
        field.textColor = editable ? .labelColor : .secondaryLabelColor
        scrubLabel.isScrubbable = editable
        scrubLabel.stringValue = property.label
        field.setAccessibilityIdentifier(property.identifier)
        field.setAccessibilityLabel(property.title)
        scrubLabel.setAccessibilityIdentifier(property.identifier + ".scrub")
        scrubLabel.setAccessibilityLabel("拖动调整" + property.title)
        scrubLabel.toolTip = editable ? "水平拖动调整\(property.title) · Shift ×10 · Option ×0.1 · Escape 取消" : "编组尺寸只读"
        if textToken == nil { refreshValue() }
        needsLayout = true
    }
    private func refreshValue() {
        guard let session, let nodeID, let node = session.document.node(id: nodeID) else { return }
        field.stringValue = formatter.string(from: NSNumber(value: property.value(in: node))) ?? ""
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = EditorPalette.inspectorControl.cgColor
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
            if let window { NotificationCenter.default.addObserver(self, selector: #selector(windowInputEnded(_:)), name: name, object: window) }
        }
        if window == nil { endInput() }
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { endInput() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    @objc private func windowInputEnded(_ notification: Notification) { endInput() }

    func controlTextDidBeginEditing(_ notification: Notification) { beginTextSegment() }
    func controlTextDidChange(_ notification: Notification) {
        // Resigning the key window commits the previous segment, but AppKit may
        // preserve the same field editor when the window becomes key again.
        if textToken == nil, field.currentEditor() != nil { beginTextSegment() }
    }
    private func beginTextSegment() {
        guard let session, let nodeID,
              let token = session.beginInspectorEdit(property, nodeID: nodeID) else { return }
        textToken = token
        session.finishInspectorText = { [weak self] in self?.finishText() }
    }
    func controlTextDidEndEditing(_ notification: Notification) { finishText() }
    private func finishText(cancel: Bool = false) {
        guard let token = textToken, let session else { return }
        textToken = nil
        if !cancel {
            let text = (field.currentEditor()?.string ?? field.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
            let decimal = formatter.decimalSeparator ?? "."
            if let value = Double(text.replacingOccurrences(of: decimal, with: ".")) { session.updateInspectorNumber(token, value: value) }
        }
        session.finishInspectorEdit(token, cancel: cancel)
        refreshValue()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        finishText(cancel: true)
        window?.makeFirstResponder(nil)
        return true
    }
    func endInput() {
        finishText(); scrubLabel.finishScrub()
        if let edit = session?.inspectorEdit, edit.nodeID == nodeID, edit.property == property {
            session?.finishInspectorEdit(edit.token)
        }
    }

    fileprivate func beginScrub() -> UUID? {
        guard let session, let nodeID else { return nil }
        return session.beginInspectorEdit(property, nodeID: nodeID)
    }
    fileprivate func scrub(_ token: UUID, translation: CGFloat, modifiers: NSEvent.ModifierFlags) {
        session?.scrubInspectorNumber(token, translation: Double(translation), modifiers: modifiers)
        refreshValue()
    }
    fileprivate func finishScrub(_ token: UUID, cancel: Bool) {
        session?.finishInspectorEdit(token, cancel: cancel)
        refreshValue()
    }
}

@MainActor final class InspectorScrubLabel: NSTextField {
    weak var owner: InspectorNumberControl?
    var isScrubbable = true
    private var origin: CGFloat?
    private var token: UUID?
    override var acceptsFirstResponder: Bool { isScrubbable }
    override func resetCursorRects() {
        if isScrubbable { addCursorRect(bounds, cursor: .resizeLeftRight) }
    }
    override func mouseDown(with event: NSEvent) {
        guard isScrubbable else { return }
        window?.makeFirstResponder(self)
        origin = event.locationInWindow.x
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        let translation = event.locationInWindow.x - origin
        if token == nil {
            guard abs(translation) >= 3 else { return }
            token = owner?.beginScrub()
            if token == nil { self.origin = nil; return }
        }
        if let token { owner?.scrub(token, translation: translation, modifiers: event.modifierFlags) }
    }
    override func mouseUp(with event: NSEvent) { finishScrub() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finishScrub(cancel: true) }
        else { super.keyDown(with: event) }
    }
    override func resignFirstResponder() -> Bool { finishScrub(); return super.resignFirstResponder() }
    func finishScrub(cancel: Bool = false) {
        let active = token
        token = nil; origin = nil
        if let active { owner?.finishScrub(active, cancel: cancel) }
    }
}

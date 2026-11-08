import AppKit
import SwiftUI
import Observation

/// Keep the workspace here: a toolbar outlives each document's canvas/session.
struct ZoomControlView: View {
    @Bindable var workspace: DocumentWorkspace

    var body: some View {
        let session = workspace.current.session
        ZoomControlsHost(workspace: workspace, zoom: session.zoom)
            .environment(\.locale, LanguageSettings.shared.locale)
            .frame(width: 176, height: 32)
    }
}

private struct ZoomControlsHost: NSViewRepresentable {
    @Environment(\.locale) private var locale
    let workspace: DocumentWorkspace
    let zoom: CGFloat

    func makeNSView(context: Context) -> ZoomControls {
        let controls = ZoomControls(frame: .zero)
        controls.bind(to: workspace, zoom: zoom)
        return controls
    }

    func updateNSView(_ controls: ZoomControls, context: Context) {
        _ = locale
        controls.bind(to: workspace, zoom: zoom)
    }

    static func dismantleNSView(_ controls: ZoomControls, coordinator: ()) {
        controls.slider.setEditing(false)
    }
}

/// Native controls share the slider's observation so the persistent percentage
/// and drag feedback always show the same value, including same-runloop changes.
@MainActor private final class ZoomControls: NSView {
    let slider = ZoomSlider(frame: CGRect(x: 0, y: 0, width: 96, height: 32))
    private let zoomMenu = ZoomMenuButton(frame: CGRect(x: 104, y: 3, width: 72, height: 26), pullsDown: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(slider)
        addSubview(zoomMenu)
        slider.percentageDidChange = { [weak zoomMenu] percentage in
            zoomMenu?.title = percentage
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func bind(to workspace: DocumentWorkspace, zoom: CGFloat) {
        zoomMenu.workspace = workspace
        zoomMenu.refreshLanguage()
        slider.setAccessibilityLabel(L10n.text("缩放"))
        slider.toolTip = L10n.text("画布缩放")
        slider.bind(to: workspace, zoom: zoom)
    }
}

@MainActor private final class ZoomMenuButton: NSPopUpButton {
    weak var workspace: DocumentWorkspace?

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        bezelStyle = .texturedRounded
        font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        setAccessibilityIdentifier("view.zoomMenu")
        setAccessibilityLabel(L10n.text("缩放比例"))
        toolTip = L10n.text("缩放比例与画布适合")
        let menu = NSMenu()
        // A pull-down uses its first item as the always-visible button title.
        menu.addItem(withTitle: "100%", action: nil, keyEquivalent: "")
        let fit = menu.addItem(withTitle: L10n.text("适合画布"), action: #selector(fitCanvas(_:)), keyEquivalent: "")
        fit.target = self
        addZoomItem(title: L10n.text("实际尺寸（100%）"), value: 1, to: menu)
        menu.addItem(.separator())
        for percent in [25, 50, 100, 200, 400, 800] {
            addZoomItem(title: "\(percent)%", value: Double(percent) / 100, to: menu)
        }
        self.menu = menu
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func refreshLanguage() {
        setAccessibilityLabel(L10n.text("缩放比例"))
        toolTip = L10n.text("缩放比例与画布适合")
        menu?.item(at: 1)?.title = L10n.text("适合画布")
        menu?.item(at: 2)?.title = L10n.text("实际尺寸（100%）")
    }

    private func addZoomItem(title: String, value: Double, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: #selector(setZoom(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = value
    }

    @objc private func fitCanvas(_ sender: NSMenuItem) {
        workspace?.current.session.fitCanvas?()
    }

    @objc private func setZoom(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        workspace?.current.session.setZoom(CGFloat(value))
    }
}

/// NSSlider supplies native continuous tracking; a nonactivating child panel lets
/// feedback escape the compact toolbar without taking focus or intercepting drag.
@MainActor final class ZoomSlider: NSSlider {
    private var onChange: ((CGFloat) -> Void)?
    var percentageDidChange: ((String) -> Void)?
    private var documentID: UUID?
    private weak var workspace: DocumentWorkspace?
    private(set) var isEditing = false
    private(set) var percentagePanel: NSPanel?
    private let percentageLabel = NSTextField(labelWithString: "100%")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ZoomSliderCell()
        minValue = log2(0.05)
        maxValue = 3
        isContinuous = true
        target = self
        action = #selector(valueChanged(_:))
        setAccessibilityIdentifier("view.zoomSlider")
        setAccessibilityLabel(L10n.text("缩放"))
        toolTip = L10n.text("画布缩放")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func bind(to workspace: DocumentWorkspace, zoom: CGFloat) {
        if self.workspace !== workspace {
            self.workspace = workspace
            observeZoom(in: workspace)
        } else {
            configure(zoom: zoom, documentID: workspace.currentID) { [weak workspace] value in
                workspace?.current.session.setZoom(value)
            }
        }
    }

    private func observeZoom(in workspace: DocumentWorkspace) {
        // Native tracking mutates the slider before SwiftUI renders. Observe the
        // model too, so a zoom that returns to its last rendered value still syncs.
        withObservationTracking {
            configure(zoom: workspace.current.session.zoom, documentID: workspace.currentID) { [weak workspace] value in
                workspace?.current.session.setZoom(value)
            }
        } onChange: { [weak self, weak workspace] in
            Task { @MainActor in
                guard let self, let workspace, self.workspace === workspace else { return }
                self.observeZoom(in: workspace)
            }
        }
    }

    func configure(zoom: CGFloat, documentID: UUID, onChange: @escaping (CGFloat) -> Void) {
        if self.documentID != documentID { setEditing(false) }
        self.documentID = documentID
        self.onChange = onChange
        doubleValue = log2(Double(min(8, max(0.05, zoom))))
        updatePercentage()
    }

    override func accessibilityValue() -> Any? { percentage }

    private var percentage: String { "\(Int((exp2(doubleValue) * 100).rounded()))%" }

    @objc private func valueChanged(_ sender: NSSlider) {
        onChange?(CGFloat(exp2(doubleValue)))
        updatePercentage()
    }

    override func mouseDown(with event: NSEvent) {
        setEditing(true)
        defer { setEditing(false) }
        super.mouseDown(with: event)
    }

    func setEditing(_ editing: Bool) {
        isEditing = editing
        if editing { showPercentage() }
        else if let panel = percentagePanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func updatePercentage() {
        percentageLabel.stringValue = percentage
        percentageDidChange?(percentage)
        if isEditing { positionPercentage() }
    }

    private func showPercentage() {
        guard let window else { return }
        let panel: NSPanel
        if let existing = percentagePanel { panel = existing }
        else {
            panel = ZoomPercentagePanel(contentRect: CGRect(x: 0, y: 0, width: 72, height: 30),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = true
            let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: panel.frame.size))
            background.material = .popover
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 7
            background.layer?.masksToBounds = true
            percentageLabel.frame = background.bounds.insetBy(dx: 4, dy: 6)
            percentageLabel.alignment = .center
            percentageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            background.addSubview(percentageLabel)
            panel.contentView = background
            percentagePanel = panel
        }
        panel.appearance = effectiveAppearance
        updatePercentage()
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    private func positionPercentage() {
        guard let window, let panel = percentagePanel else { return }
        let rect = window.convertToScreen(convert(bounds, to: nil))
        panel.setFrameOrigin(CGPoint(x: rect.midX - panel.frame.width / 2, y: rect.minY - panel.frame.height - 4))
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { setEditing(false) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(endZoomTracking(_:)), name: name, object: window)
            }
        }
    }

    @objc private func endZoomTracking(_ notification: Notification) { setEditing(false) }
}

@MainActor private final class ZoomSliderCell: NSSliderCell {
    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let started = super.startTracking(at: startPoint, in: controlView)
        if started { (controlView as? ZoomSlider)?.setEditing(true) }
        return started
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint,
                               in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        (controlView as? ZoomSlider)?.setEditing(false)
    }
}

@MainActor private final class ZoomPercentagePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

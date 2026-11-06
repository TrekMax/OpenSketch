import AppKit
import SwiftUI
import Observation

/// Keep the workspace here: a toolbar outlives each document's canvas/session.
struct ZoomControlView: View {
    @Bindable var workspace: DocumentWorkspace

    var body: some View {
        let session = workspace.current.session
        ZoomSliderHost(workspace: workspace, zoom: session.zoom)
            .frame(width: 160, height: 32)
    }
}

private struct ZoomSliderHost: NSViewRepresentable {
    let workspace: DocumentWorkspace
    let zoom: CGFloat

    func makeNSView(context: Context) -> ZoomSlider {
        let slider = ZoomSlider(frame: .zero)
        slider.bind(to: workspace, zoom: zoom)
        return slider
    }

    func updateNSView(_ slider: ZoomSlider, context: Context) {
        slider.bind(to: workspace, zoom: zoom)
    }

    static func dismantleNSView(_ slider: ZoomSlider, coordinator: ()) {
        slider.setEditing(false)
    }
}

/// NSSlider supplies native continuous tracking; a nonactivating child panel lets
/// feedback escape the compact toolbar without taking focus or intercepting drag.
@MainActor final class ZoomSlider: NSSlider {
    private var onChange: ((CGFloat) -> Void)?
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
        setAccessibilityLabel("缩放")
        toolTip = "画布缩放"
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

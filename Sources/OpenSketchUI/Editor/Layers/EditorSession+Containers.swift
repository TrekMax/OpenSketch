import CoreGraphics
import OpenSketchCore

extension EditorSession {
    /// Joins the current movement transaction; the canvas owns commit or cancellation.
    func applyContainerDrop(at point: CGPoint) {
        guard gestureStart != nil else { return }
        let target = ContainerEditing.dropTarget(in: page, selection: selection, at: point)
        do {
            document = try ContainerEditing.reparenting(document, pageID: pageID, selection: selection, to: target)
        } catch {
            let reason: String
            switch error {
            case LayerEditError.lockedOrHidden: reason = "所选图层或其祖先已锁定或隐藏"
            case LayerEditError.invalidGeometry: reason = "图层坐标无效或超出范围"
            case LayerEditError.invalidSelection: reason = "选择无效，请重新选择图层"
            case DocumentCodecError.limitExceeded: reason = "文档内容超出格式或大小限制"
            default: reason = "文档数据无效"
            }
            setMessage(.format("无法调整图层归属：%@", [.key(reason)]))
        }
    }
}

import AppKit

@MainActor final class NativeLayerOutline: NSOutlineView {
    var menuForItem: ((LayerTreeItem) -> NSMenu?)?
    var renameSelection: (() -> Void)?
    var deleteSelection: (() -> Void)?
    override func drawBackground(inClipRect clipRect: NSRect) {
        super.drawBackground(inClipRect: clipRect)
        let visibleRows = rows(in: clipRect)
        guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return }
        let guides = NSBezierPath()
        guides.lineWidth = 1
        for row in visibleRows.location..<min(NSMaxRange(visibleRows), numberOfRows) {
            guard let item = item(atRow: row) as? LayerTreeItem, item.id != nil else { continue }
            let rowRect = rect(ofRow: row)
            var ancestor = parent(forItem: item)
            while let parent = ancestor {
                let parentRow = self.row(forItem: parent)
                guard parentRow >= 0 else { break }
                // Align with the ancestor icon, spanning the complete child row and inter-row gap.
                let x = frameOfCell(atColumn: 0, row: parentRow).minX + LayerTreeCell.iconCenterX
                guides.move(to: NSPoint(x: x, y: rowRect.minY - intercellSpacing.height / 2))
                guides.line(to: NSPoint(x: x, y: rowRect.maxY + intercellSpacing.height / 2))
                ancestor = self.parent(forItem: parent)
            }
        }
        NSColor.separatorColor.setStroke()
        guides.stroke()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let item = item(atRow: row) as? LayerTreeItem else { return nil }
        return menuForItem?(item)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection?()
        } else if event.keyCode == 36 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            renameSelection?()
        } else { super.keyDown(with: event) }
    }
}

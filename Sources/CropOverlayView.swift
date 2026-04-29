import AppKit

// MARK: - CropOverlayView

class CropOverlayView: NSView {

    // Called with a normalized rect (0-1 in image space, y=0 at bottom) when user confirms.
    var onCropConfirmed: ((CGRect) -> Void)?
    var onCropCancelled: (() -> Void)?

    // imageDisplayRectProvider mirrors the one on AnnotationOverlay.
    var imageDisplayRectProvider: (() -> CGRect)?

    private enum CropDragState { case idle, dragging(start: CGPoint, current: CGPoint), selected(rect: CGRect) }
    private var dragState: CropDragState = .idle

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Public

    func reset() {
        dragState = .idle
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Only operate within the actual rendered image rect, not the full padded view.
        let imgRect = imageDisplayRect

        // Dim only the image area.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(imgRect)

        let selRect: CGRect?
        switch dragState {
        case .dragging(let s, let c):
            selRect = CGRect(origin: s, size: CGSize(width: c.x - s.x, height: c.y - s.y)).standardized
        case .selected(let r):
            selRect = r
        case .idle:
            selRect = nil
        }

        if let r = selRect {
            // Clear the selected area (restores the image underneath).
            ctx.clear(r)

            // Draw a bright border around the selection.
            let borderPath = NSBezierPath(rect: r)
            borderPath.lineWidth = 1.5
            NSColor.white.setStroke()
            borderPath.stroke()

            // Draw rule-of-thirds grid inside selection.
            NSColor.white.withAlphaComponent(0.3).setStroke()
            let thirdW = r.width / 3
            let thirdH = r.height / 3
            for i in 1...2 {
                let vLine = NSBezierPath()
                vLine.move(to: CGPoint(x: r.minX + thirdW * CGFloat(i), y: r.minY))
                vLine.line(to: CGPoint(x: r.minX + thirdW * CGFloat(i), y: r.maxY))
                vLine.lineWidth = 0.5
                vLine.stroke()
                let hLine = NSBezierPath()
                hLine.move(to: CGPoint(x: r.minX, y: r.minY + thirdH * CGFloat(i)))
                hLine.line(to: CGPoint(x: r.maxX, y: r.minY + thirdH * CGFloat(i)))
                hLine.lineWidth = 0.5
                hLine.stroke()
            }

            // Corner handles.
            let corners: [CGPoint] = [
                CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
            ]
            let handleLen: CGFloat = 12
            let handleW: CGFloat = 2.5
            NSColor.white.setStroke()
            for corner in corners {
                let hx = NSBezierPath()
                let dirX: CGFloat = corner.x == r.minX ? 1 : -1
                let dirY: CGFloat = corner.y == r.minY ? 1 : -1
                hx.move(to: corner)
                hx.line(to: CGPoint(x: corner.x + dirX * handleLen, y: corner.y))
                hx.lineWidth = handleW; hx.stroke()
                let hy = NSBezierPath()
                hy.move(to: corner)
                hy.line(to: CGPoint(x: corner.x, y: corner.y + dirY * handleLen))
                hy.lineWidth = handleW; hy.stroke()
            }

            // "Crop" / "Cancel" hint labels when selection is complete.
            if case .selected = dragState {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.white,
                ]
                let confirmStr = NSAttributedString(string: "↵ Crop   Esc Cancel", attributes: attrs)
                let sz = confirmStr.size()
                let labelPt = CGPoint(x: r.midX - sz.width / 2,
                                      y: r.minY - sz.height - 8)
                if labelPt.y > imgRect.minY + 4 {
                    confirmStr.draw(at: labelPt)
                } else {
                    confirmStr.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.maxY + 8))
                }
            }
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let loc = raw.clamped(to: imageDisplayRect)
        dragState = .dragging(start: loc, current: loc)
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let loc = raw.clamped(to: imageDisplayRect)
        if case .dragging(let s, _) = dragState {
            dragState = .dragging(start: s, current: loc)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let loc = raw.clamped(to: imageDisplayRect)
        if case .dragging(let s, _) = dragState {
            let r = CGRect(origin: s, size: CGSize(width: loc.x - s.x, height: loc.y - s.y)).standardized
            if r.width > 8 && r.height > 8 {
                dragState = .selected(rect: r)
            } else {
                dragState = .idle
            }
            needsDisplay = true
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return / Enter
            confirmCrop()
        case 53: // Escape
            onCropCancelled?()
        default:
            super.keyDown(with: event)
        }
    }

    private func confirmCrop() {
        guard case .selected(let viewRect) = dragState else { return }
        let imgRect = imageDisplayRect
        guard imgRect.width > 0, imgRect.height > 0 else { return }

        let clamped = viewRect.intersection(imgRect)
        guard clamped.width > 4, clamped.height > 4 else { return }

        let normX = (clamped.minX - imgRect.minX) / imgRect.width
        let normY = (clamped.minY - imgRect.minY) / imgRect.height
        let normW = clamped.width  / imgRect.width
        let normH = clamped.height / imgRect.height

        onCropConfirmed?(CGRect(x: normX, y: normY, width: normW, height: normH))
    }

    private var imageDisplayRect: CGRect {
        imageDisplayRectProvider?() ?? bounds
    }
}

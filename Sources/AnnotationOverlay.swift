import AppKit

struct Arrow {
    var id = UUID()
    var start: CGPoint  // normalized 0-1 relative to imageDisplayRect, y=0 at bottom
    var end: CGPoint
    var weight: CGFloat
    var color: NSColor
}

class AnnotationOverlay: NSView {
    var arrows: [Arrow] = []
    var currentWeight: CGFloat = 2
    var currentColor: NSColor = .systemRed

    // When false, mouse events are ignored (overlay is display-only).
    var isToolActive: Bool = false {
        didSet {
            window?.invalidateCursorRects(for: self)
            if !isToolActive { selectedArrowID = nil; needsDisplay = true }
        }
    }

    var imageDisplayRectProvider: (() -> CGRect)?
    var onCopy: (() -> Void)?
    var onChange: (() -> Void)?

    private var selectedArrowID: UUID?

    private enum DragState {
        case none
        case newArrow(start: CGPoint, current: CGPoint)
        case movingWhole(index: Int, lastLoc: CGPoint)
        case movingTail(index: Int)   // end (arrowhead) stays fixed; start (tail) follows cursor
    }
    private var dragState: DragState = .none

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    var imageDisplayRect: CGRect { imageDisplayRectProvider?() ?? bounds }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for arrow in arrows {
            renderArrow(from: toView(arrow.start), to: toView(arrow.end),
                        weight: arrow.weight, color: arrow.color)
        }
        if case .newArrow(let s, let c) = dragState {
            renderArrow(from: s, to: c, weight: currentWeight, color: currentColor)
        }
        // Draw tail handle on selected arrow
        if let selID = selectedArrowID, let arrow = arrows.first(where: { $0.id == selID }) {
            drawTailHandle(at: toView(arrow.start))
        }
    }

    func renderArrow(from: CGPoint, to: CGPoint, weight: CGFloat, color: NSColor) {
        guard hypot(to.x - from.x, to.y - from.y) > 3 else { return }

        let body = NSBezierPath()
        body.move(to: from); body.line(to: to)
        body.lineWidth = weight; body.lineCapStyle = .round
        color.setStroke(); body.stroke()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLen = max(weight * 3.5, 12.0)
        let head = NSBezierPath(); head.lineCapStyle = .round
        for sign: CGFloat in [-.pi/6, .pi/6] {
            head.move(to: to)
            head.line(to: CGPoint(x: to.x - headLen * cos(angle + sign),
                                  y: to.y - headLen * sin(angle + sign)))
        }
        head.lineWidth = weight; color.setStroke(); head.stroke()
    }

    private func drawTailHandle(at point: CGPoint) {
        let r: CGFloat = 7
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r*2, height: r*2)
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill(); circle.fill()
        NSColor.systemBlue.setStroke(); circle.lineWidth = 2; circle.stroke()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isToolActive ? .crosshair : .arrow)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard isToolActive else { return }
        let loc = convert(event.locationInWindow, from: nil)
        if let idx = tailIndex(near: loc) {
            dragState = .movingTail(index: idx)
            selectedArrowID = arrows[idx].id
        } else if let idx = arrowBodyIndex(near: loc) {
            dragState = .movingWhole(index: idx, lastLoc: loc)
            selectedArrowID = arrows[idx].id
        } else {
            dragState = .newArrow(start: loc, current: loc)
            selectedArrowID = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isToolActive else { return }
        let loc = convert(event.locationInWindow, from: nil)
        switch dragState {
        case .movingTail(let idx):
            arrows[idx].start = toNorm(loc)
            needsDisplay = true
        case .movingWhole(let idx, let last):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            let d = CGPoint(x: (loc.x - last.x) / r.width, y: (loc.y - last.y) / r.height)
            arrows[idx].start.x += d.x; arrows[idx].start.y += d.y
            arrows[idx].end.x   += d.x; arrows[idx].end.y   += d.y
            dragState = .movingWhole(index: idx, lastLoc: loc)
            needsDisplay = true
        case .newArrow(let s, _):
            dragState = .newArrow(start: s, current: loc)
            needsDisplay = true
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isToolActive else { return }
        let loc = convert(event.locationInWindow, from: nil)
        switch dragState {
        case .newArrow(let s, let c):
            if hypot(c.x - s.x, c.y - s.y) > 8 {
                let a = Arrow(start: toNorm(s), end: toNorm(c),
                              weight: currentWeight, color: currentColor)
                arrows.append(a)
                selectedArrowID = a.id
                onChange?()
            } else {
                selectedArrowID = nil   // tap on empty = deselect
            }
        case .movingTail, .movingWhole:
            onChange?()
        case .none: break
        }
        dragState = .none
        needsDisplay = true
        _ = loc  // suppress warning
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Backspace (51) or Forward Delete (117)
        if event.keyCode == 51 || event.keyCode == 117, let id = selectedArrowID {
            arrows.removeAll { $0.id == id }
            selectedArrowID = nil
            needsDisplay = true
            onChange?()
        }
    }

    // MARK: - Context menu (available regardless of tool state)

    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if isToolActive, let idx = (tailIndex(near: loc) ?? arrowBodyIndex(near: loc)) {
            let del = menu.addItem(withTitle: "Delete Arrow",
                                   action: #selector(menuDelete(_:)), keyEquivalent: "")
            del.target = self
            del.representedObject = arrows[idx].id
            menu.addItem(.separator())
        }
        let copy = menu.addItem(withTitle: "Copy Image",
                                action: #selector(menuCopy(_:)), keyEquivalent: "")
        copy.target = self
        return menu
    }

    @objc private func menuDelete(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        arrows.removeAll { $0.id == id }
        if selectedArrowID == id { selectedArrowID = nil }
        needsDisplay = true; onChange?()
    }

    @objc private func menuCopy(_ item: NSMenuItem) { onCopy?() }

    // MARK: - Update selected arrow

    func updateSelected(weight: CGFloat? = nil, color: NSColor? = nil) {
        guard let id = selectedArrowID,
              let idx = arrows.firstIndex(where: { $0.id == id }) else { return }
        if let w = weight { arrows[idx].weight = w }
        if let c = color  { arrows[idx].color  = c }
        needsDisplay = true
    }

    // MARK: - Coordinate helpers

    func toNorm(_ p: CGPoint) -> CGPoint {
        let r = imageDisplayRect
        guard r.width > 0, r.height > 0 else { return p }
        return CGPoint(x: (p.x - r.minX) / r.width, y: (p.y - r.minY) / r.height)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        let r = imageDisplayRect
        return CGPoint(x: p.x * r.width + r.minX, y: p.y * r.height + r.minY)
    }

    // MARK: - Hit testing

    // Returns index of arrow whose tail (start) is within 12 px.
    private func tailIndex(near point: CGPoint) -> Int? {
        arrows.indices.reversed().first { i in
            hypot(point.x - toView(arrows[i].start).x,
                  point.y - toView(arrows[i].start).y) < 12
        }
    }

    // Returns index of nearest arrow body (excluding tail hot-zone).
    private func arrowBodyIndex(near point: CGPoint) -> Int? {
        arrows.indices.reversed().first { i in
            let threshold = max(arrows[i].weight / 2 + 8, 12.0)
            return distToSeg(point, toView(arrows[i].start), toView(arrows[i].end)) < threshold
        }
    }

    private func distToSeg(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx*dx + dy*dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x)*dx + (p.y - a.y)*dy) / lenSq))
        return hypot(p.x - (a.x + t*dx), p.y - (a.y + t*dy))
    }
}

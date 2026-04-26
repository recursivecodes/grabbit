import AppKit

// MARK: - Tool

enum AnnotationTool { case none, arrow, text }

// MARK: - Arrow

struct Arrow {
    var id = UUID()
    var start: CGPoint  // normalized 0-1 relative to imageDisplayRect, y=0 at bottom
    var end: CGPoint
    var weight: CGFloat
    var color: NSColor
}

// MARK: - TextAnnotation

struct TextAnnotation {
    var id = UUID()
    var position: CGPoint   // normalized 0-1, y=0 at bottom; baseline-left of text in view coords
    var content: String
    var fontName: String
    var fontSize: CGFloat
    var fontColor: NSColor
    var outlineColor: NSColor
    var outlineWeight: CGFloat  // visible outer stroke width in points (0 = no outline)
}

// MARK: - Attributed string helper (internal so EditorWindowController can use it for export)

func makeTextAttrStr(_ content: String, font: NSFont,
                      fontColor: NSColor, outlineColor: NSColor,
                      outlineWeight: CGFloat, strokeOnly: Bool) -> NSAttributedString {
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if strokeOnly && outlineWeight > 0 {
        // Positive strokeWidth = stroke only, no fill. Value is % of font point size.
        let pct = (outlineWeight * 2.0 / font.pointSize) * 100.0
        attrs[.strokeColor]     = outlineColor
        attrs[.strokeWidth]     = pct
        attrs[.foregroundColor] = NSColor.clear
    } else {
        attrs[.foregroundColor] = fontColor
    }
    return NSAttributedString(string: content, attributes: attrs)
}

// MARK: - AnnotationOverlay

class AnnotationOverlay: NSView {

    // MARK: Arrow state
    var arrows: [Arrow] = []
    var currentWeight: CGFloat = 2
    var currentColor:  NSColor = .systemRed

    // MARK: Text state
    var textAnnotations: [TextAnnotation] = []
    var currentFontName:     String  = "Helvetica-Bold"
    var currentFontSize:     CGFloat = 24
    var currentFontColor:    NSColor = .white
    var currentOutlineColor: NSColor = .black
    var currentOutlineWeight: CGFloat = 2

    // MARK: Active tool
    var activeTool: AnnotationTool = .none {
        didSet {
            window?.invalidateCursorRects(for: self)
            if activeTool != .arrow { selectedArrowID = nil }
            if activeTool != .text  { finalizeEditing(); selectedTextID = nil }
            needsDisplay = true
        }
    }

    // Legacy shim for arrow-only callers.
    var isToolActive: Bool {
        get { activeTool == .arrow }
        set { activeTool = newValue ? .arrow : .none }
    }

    // MARK: Callbacks
    var imageDisplayRectProvider: (() -> CGRect)?
    var onCopy:   (() -> Void)?
    var onChange: (() -> Void)?
    var onTextSelectionChanged: ((TextAnnotation?) -> Void)?

    // MARK: Private state
    private var selectedArrowID: UUID?
    private var selectedTextID:  UUID? {
        didSet {
            let ann = selectedTextID.flatMap { id in textAnnotations.first { $0.id == id } }
            onTextSelectionChanged?(ann)
        }
    }

    private enum DragState {
        case none
        case newArrow(start: CGPoint, current: CGPoint)
        case movingArrowWhole(index: Int, lastLoc: CGPoint)
        case movingArrowTail(index: Int)
        case movingText(index: Int, lastLoc: CGPoint)
    }
    private var dragState: DragState = .none

    private var editingScrollView: NSScrollView?
    private var editingTextView:   NSTextView?
    private var editingField: NSTextField?   // unused – kept for ABI compat
    private var editingID:    UUID?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    var imageDisplayRect: CGRect { imageDisplayRectProvider?() ?? bounds }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Arrows
        for arrow in arrows {
            renderArrow(from: toView(arrow.start), to: toView(arrow.end),
                        weight: arrow.weight, color: arrow.color)
        }
        if case .newArrow(let s, let c) = dragState {
            renderArrow(from: s, to: c, weight: currentWeight, color: currentColor)
        }
        if let selID = selectedArrowID, let arrow = arrows.first(where: { $0.id == selID }) {
            drawArrowTailHandle(at: toView(arrow.start))
        }

        // Text annotations (skip the one currently being edited via inline field)
        for ann in textAnnotations {
            guard ann.id != editingID else { continue }
            drawTextAnnotation(ann, selected: ann.id == selectedTextID)
        }
    }

    private func drawTextAnnotation(_ ann: TextAnnotation, selected: Bool) {
        let pt = toView(ann.position)
        let font = NSFont(name: ann.fontName, size: ann.fontSize) ?? NSFont.boldSystemFont(ofSize: ann.fontSize)

        if !ann.content.isEmpty {
            // Two-pass: stroke outline first, fill on top.
            if ann.outlineWeight > 0 {
                makeTextAttrStr(ann.content, font: font,
                                fontColor: .clear, outlineColor: ann.outlineColor,
                                outlineWeight: ann.outlineWeight, strokeOnly: true)
                    .draw(at: pt)
            }
            makeTextAttrStr(ann.content, font: font,
                            fontColor: ann.fontColor, outlineColor: ann.outlineColor,
                            outlineWeight: ann.outlineWeight, strokeOnly: false)
                .draw(at: pt)
        }

        if selected {
            let size: CGSize
            if ann.content.isEmpty {
                size = CGSize(width: max(80, ann.fontSize * 4), height: ann.fontSize * 1.4)
            } else {
                size = makeTextAttrStr(ann.content, font: font,
                                       fontColor: ann.fontColor, outlineColor: ann.outlineColor,
                                       outlineWeight: ann.outlineWeight, strokeOnly: false).size()
            }
            let selRect = CGRect(x: pt.x - 4,
                                 y: pt.y - abs(font.descender) - 2,
                                 width: size.width + 8,
                                 height: size.height + 4)
            let path = NSBezierPath(rect: selRect)
            path.lineWidth = 1.5
            NSColor.selectedControlColor.withAlphaComponent(0.9).setStroke()
            path.setLineDash([5, 3], count: 2, phase: 0)
            path.stroke()
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

    private func drawArrowTailHandle(at point: CGPoint) {
        let r: CGFloat = 7
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r*2, height: r*2)
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill(); circle.fill()
        NSColor.systemBlue.setStroke(); circle.lineWidth = 2; circle.stroke()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        switch activeTool {
        case .arrow: cursor = .crosshair
        case .text:  cursor = .iBeam
        case .none:  cursor = .arrow
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        switch activeTool {

        case .arrow:
            if let idx = tailIndex(near: loc) {
                dragState = .movingArrowTail(index: idx)
                selectedArrowID = arrows[idx].id
            } else if let idx = arrowBodyIndex(near: loc) {
                dragState = .movingArrowWhole(index: idx, lastLoc: loc)
                selectedArrowID = arrows[idx].id
            } else {
                dragState = .newArrow(start: loc, current: loc)
                selectedArrowID = nil
            }
            needsDisplay = true

        case .text:
            let wasEditing = editingID != nil
            _ = commitEdit()

            if let idx = textIndex(near: loc) {
                selectedTextID = textAnnotations[idx].id
                needsDisplay = true
                if event.clickCount >= 2 {
                    beginEditing(index: idx)
                } else if !wasEditing {
                    // Only start a drag if we weren't just finishing an edit.
                    dragState = .movingText(index: idx, lastLoc: loc)
                }
            } else if !wasEditing {
                // Create new text annotation at click location.
                let ann = TextAnnotation(
                    position: toNorm(loc), content: "",
                    fontName: currentFontName,
                    fontSize: currentFontSize,
                    fontColor: currentFontColor,
                    outlineColor: currentOutlineColor,
                    outlineWeight: currentOutlineWeight
                )
                textAnnotations.append(ann)
                selectedTextID = ann.id
                needsDisplay = true
                beginEditing(index: textAnnotations.count - 1)
            } else {
                selectedTextID = nil
                needsDisplay = true
            }

        case .none: break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        switch dragState {
        case .movingArrowTail(let idx):
            arrows[idx].start = toNorm(loc); needsDisplay = true
        case .movingArrowWhole(let idx, let last):
            let r = imageDisplayRect; guard r.width > 0, r.height > 0 else { break }
            let d = CGPoint(x: (loc.x - last.x) / r.width, y: (loc.y - last.y) / r.height)
            arrows[idx].start.x += d.x; arrows[idx].start.y += d.y
            arrows[idx].end.x   += d.x; arrows[idx].end.y   += d.y
            dragState = .movingArrowWhole(index: idx, lastLoc: loc); needsDisplay = true
        case .newArrow(let s, _):
            dragState = .newArrow(start: s, current: loc); needsDisplay = true
        case .movingText(let idx, let last):
            let r = imageDisplayRect; guard r.width > 0, r.height > 0 else { break }
            let d = CGPoint(x: (loc.x - last.x) / r.width, y: (loc.y - last.y) / r.height)
            textAnnotations[idx].position.x += d.x
            textAnnotations[idx].position.y += d.y
            dragState = .movingText(index: idx, lastLoc: loc); needsDisplay = true
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        switch dragState {
        case .newArrow(let s, let c):
            if hypot(c.x - s.x, c.y - s.y) > 8 {
                let a = Arrow(start: toNorm(s), end: toNorm(c),
                              weight: currentWeight, color: currentColor)
                arrows.append(a); selectedArrowID = a.id; onChange?()
            } else {
                selectedArrowID = nil
            }
        case .movingArrowTail, .movingArrowWhole, .movingText:
            onChange?()
        case .none: break
        }
        dragState = .none; needsDisplay = true; _ = loc
    }

    // MARK: - Inline text editing

    private func beginEditing(index: Int) {
        guard index < textAnnotations.count else { return }
        let ann  = textAnnotations[index]
        let pt   = toView(ann.position)
        let font = NSFont(name: ann.fontName, size: ann.fontSize) ?? NSFont.boldSystemFont(ofSize: ann.fontSize)

        // Initial width: enough for ~12 chars or the existing content, whichever is wider.
        let minW: CGFloat = max(160, ann.fontSize * 8)
        let contentW = ann.content.isEmpty ? 0 :
            NSAttributedString(string: ann.content, attributes: [.font: font]).size().width
        let initW = max(minW, contentW + 32)

        // Build a borderless NSTextView inside a scroll view so text wraps freely.
        let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: initW, height: ann.fontSize * 1.6))
        textView.font                  = font
        textView.textColor             = .labelColor
        textView.backgroundColor       = NSColor.windowBackgroundColor.withAlphaComponent(0.85)
        textView.isEditable            = true
        textView.isRichText            = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView  = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding  = 4
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.string = ann.content
        textView.delegate = self

        // Wrap in a scroll view so the container clips properly.
        let scrollView = NSScrollView(frame: CGRect(x: pt.x, y: pt.y,
                                                    width: initW,
                                                    height: ann.fontSize * 1.6 + 8))
        scrollView.documentView        = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .bezelBorder
        scrollView.wantsLayer          = true
        scrollView.layer?.cornerRadius = 4

        addSubview(scrollView)
        editingScrollView = scrollView
        editingTextView   = textView
        editingID         = ann.id

        window?.makeFirstResponder(textView)
        textView.selectAll(nil)

        // Size to fit existing content immediately.
        resizeEditingView()
    }

    /// Resize the editing scroll view to wrap all current text content.
    private func resizeEditingView() {
        guard let sv = editingScrollView, let tv = editingTextView, let id = editingID,
              let ann = textAnnotations.first(where: { $0.id == id }) else { return }

        let font   = tv.font ?? NSFont(name: ann.fontName, size: ann.fontSize) ?? NSFont.boldSystemFont(ofSize: ann.fontSize)
        let lineH  = font.ascender - font.descender + font.leading
        let inset  = tv.textContainerInset
        let padding = tv.textContainer?.lineFragmentPadding ?? 4

        // Measure the natural size of the text.
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let usedRect = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero

        let newW = max(160, usedRect.width + padding * 2 + inset.width * 2 + 8)
        let newH = max(lineH + inset.height * 2 + 8, usedRect.height + inset.height * 2 + 8)

        let pt = toView(ann.position)
        sv.frame = CGRect(x: pt.x, y: pt.y, width: newW, height: newH)
        tv.frame = CGRect(x: 0, y: 0, width: newW - 4, height: newH - 4)
        tv.textContainer?.containerSize = CGSize(width: newW - 4, height: CGFloat.greatestFiniteMagnitude)
    }

    @discardableResult
    private func commitEdit() -> Bool {
        guard let sv = editingScrollView, let tv = editingTextView, let id = editingID else { return false }
        editingScrollView = nil
        editingTextView = nil
        editingID = nil
        let text = tv.string
        sv.removeFromSuperview()
        if let idx = textAnnotations.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                textAnnotations.remove(at: idx)
                selectedTextID = nil
            } else {
                textAnnotations[idx].content = text
            }
            onChange?()
        }
        needsDisplay = true
        return true
    }

    // Called before copy/save so the export captures any in-progress edit.
    func finalizeEditing() { _ = commitEdit() }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 51 || event.keyCode == 117 else {
            super.keyDown(with: event); return
        }
        if activeTool == .arrow, let id = selectedArrowID {
            arrows.removeAll { $0.id == id }
            selectedArrowID = nil
            needsDisplay = true; onChange?()
        } else if activeTool == .text, let id = selectedTextID, editingID == nil {
            textAnnotations.removeAll { $0.id == id }
            selectedTextID = nil
            needsDisplay = true; onChange?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if activeTool == .arrow, let idx = tailIndex(near: loc) ?? arrowBodyIndex(near: loc) {
            let item = menu.addItem(withTitle: "Delete Arrow",
                                    action: #selector(menuDeleteArrow(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = arrows[idx].id
            menu.addItem(.separator())
        }
        if activeTool == .text, let idx = textIndex(near: loc) {
            let item = menu.addItem(withTitle: "Delete Text",
                                    action: #selector(menuDeleteText(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = textAnnotations[idx].id
            menu.addItem(.separator())
        }
        let copy = menu.addItem(withTitle: "Copy Image",
                                action: #selector(menuCopy(_:)), keyEquivalent: "")
        copy.target = self
        return menu
    }

    @objc private func menuDeleteArrow(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        arrows.removeAll { $0.id == id }
        if selectedArrowID == id { selectedArrowID = nil }
        needsDisplay = true; onChange?()
    }

    @objc private func menuDeleteText(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        textAnnotations.removeAll { $0.id == id }
        if selectedTextID == id { selectedTextID = nil }
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

    // MARK: - Update selected text

    func updateSelectedText(fontName: String? = nil,
                            fontSize: CGFloat? = nil,
                            fontColor: NSColor? = nil,
                            outlineColor: NSColor? = nil,
                            outlineWeight: CGFloat? = nil) {
        guard let id = selectedTextID,
              let idx = textAnnotations.firstIndex(where: { $0.id == id }) else { return }
        if let v = fontName      { textAnnotations[idx].fontName      = v }
        if let v = fontSize      { textAnnotations[idx].fontSize      = v }
        if let v = fontColor     { textAnnotations[idx].fontColor     = v }
        if let v = outlineColor  { textAnnotations[idx].outlineColor  = v }
        if let v = outlineWeight { textAnnotations[idx].outlineWeight = v }
        if let tv = editingTextView, editingID == id {
            if let name = fontName, let size = fontSize {
                tv.font = NSFont(name: name, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            } else if let name = fontName {
                let size = textAnnotations[idx].fontSize
                tv.font = NSFont(name: name, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            } else if let size = fontSize {
                let name = textAnnotations[idx].fontName
                tv.font = NSFont(name: name, size: size) ?? NSFont.boldSystemFont(ofSize: size)
            }
            if let v = fontColor { tv.textColor = v }
            resizeEditingView()
        }
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

    private func tailIndex(near point: CGPoint) -> Int? {
        arrows.indices.reversed().first { i in
            hypot(point.x - toView(arrows[i].start).x,
                  point.y - toView(arrows[i].start).y) < 12
        }
    }

    private func arrowBodyIndex(near point: CGPoint) -> Int? {
        arrows.indices.reversed().first { i in
            distToSeg(point, toView(arrows[i].start), toView(arrows[i].end))
                < max(arrows[i].weight / 2 + 8, 12.0)
        }
    }

    private func textIndex(near point: CGPoint) -> Int? {
        textAnnotations.indices.reversed().first { i in
            let ann = textAnnotations[i]
            guard ann.id != editingID else { return false }
            let pt   = toView(ann.position)
            let font = NSFont(name: ann.fontName, size: ann.fontSize) ?? NSFont.boldSystemFont(ofSize: ann.fontSize)
            let sz: CGSize
            if ann.content.isEmpty {
                // Empty annotation: use a fixed placeholder size so it's clickable.
                sz = CGSize(width: max(80, ann.fontSize * 4), height: ann.fontSize * 1.4)
            } else {
                sz = NSAttributedString(string: ann.content, attributes: [.font: font]).size()
            }
            let rect = CGRect(x: pt.x - 6,
                              y: pt.y - abs(font.descender) - 4,
                              width: sz.width + 12,
                              height: sz.height + 8)
            return rect.contains(point)
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

// MARK: - NSTextViewDelegate

extension AnnotationOverlay: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = editingTextView, let id = editingID else { return }
        // Update annotation content live.
        if let idx = textAnnotations.firstIndex(where: { $0.id == id }) {
            textAnnotations[idx].content = tv.string
        }
        // Resize the editing view to fit the new content.
        resizeEditingView()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        return false
    }

    private func finishEditing() {
        guard let sv = editingScrollView, let tv = editingTextView, let id = editingID else { return }
        editingScrollView = nil
        editingTextView = nil
        editingID = nil
        let text = tv.string
        sv.removeFromSuperview()
        if let idx = textAnnotations.firstIndex(where: { $0.id == id }) {
            if text.isEmpty {
                textAnnotations.remove(at: idx)
                selectedTextID = nil
            } else {
                textAnnotations[idx].content = text
            }
            onChange?()
        }
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func cancelEditing() {
        guard let sv = editingScrollView, let tv = editingTextView, let id = editingID else { return }
        editingScrollView = nil
        editingTextView = nil
        editingID = nil
        let text = tv.string
        sv.removeFromSuperview()
        if text.isEmpty, let idx = textAnnotations.firstIndex(where: { $0.id == id }) {
            textAnnotations.remove(at: idx)
            selectedTextID = nil
        }
        needsDisplay = true
        window?.makeFirstResponder(self)
    }
}

import AppKit

// MARK: - Tool

enum AnnotationTool { case none, arrow, text, shape, blur, highlight, ocr }

// MARK: - ShapeType

enum ShapeType {
    case circle
    case rectangle
    case roundedRectangle
}

// MARK: - Shape

struct Shape {
    var id = UUID()
    var zOrder: Int = 0
    var rect: CGRect      // normalized 0-1 relative to imageDisplayRect, y=0 at bottom
    var shapeType: ShapeType
    var borderWeight: CGFloat
    var borderColor: NSColor
    var fillColor: NSColor
}

// MARK: - BlurRegion

enum BlurStyle { case blur, pixelate }

struct BlurRegion {
    var id = UUID()
    var zOrder: Int = 0
    var rect: CGRect      // normalized 0-1 relative to imageDisplayRect, y=0 at bottom
    var intensity: CGFloat // 0-100
    var style: BlurStyle
}

// MARK: - Highlight

struct Highlight {
    var id = UUID()
    var zOrder: Int = 0
    var rect: CGRect      // normalized 0-1 relative to imageDisplayRect, y=0 at bottom
    var color: NSColor
    var opacity: CGFloat  // 0-1
}

// MARK: - Arrow

struct Arrow {
    var id = UUID()
    var zOrder: Int = 0
    var start: CGPoint  // normalized 0-1 relative to imageDisplayRect, y=0 at bottom
    var end: CGPoint
    var weight: CGFloat
    var color: NSColor
}

// MARK: - TextAnnotation

struct TextAnnotation {
    var id = UUID()
    var zOrder: Int = 0
    var position: CGPoint   // normalized 0-1, y=0 at bottom; baseline-left of text
    var content: String
    var fontName: String
    var fontSize: CGFloat
    var fontColor: NSColor
    var outlineColor: NSColor
    var outlineWeight: CGFloat
}

// MARK: - Attributed string helper

func makeTextAttrStr(_ content: String, font: NSFont,
                      fontColor: NSColor, outlineColor: NSColor,
                      outlineWeight: CGFloat, strokeOnly: Bool) -> NSAttributedString {
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if strokeOnly && outlineWeight > 0 {
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
//
// Pure view — owns no model state. All annotation data is read from `document`
// and all mutations go through document methods (which register undo).

class AnnotationOverlay: NSView {

    // MARK: Document reference
    weak var document: GrabbitDocument?

    var arrows:          [Arrow]          { document?.arrows          ?? [] }
    var textAnnotations: [TextAnnotation] { document?.textAnnotations ?? [] }
    var shapes:          [Shape]          { document?.shapes          ?? [] }
    var blurRegions:     [BlurRegion]     { document?.blurRegions     ?? [] }
    var highlights:      [Highlight]      { document?.highlights      ?? [] }

    // MARK: Current tool defaults (set by EditorWindowController from sidebar)
    var currentWeight:        CGFloat   = 2
    var currentColor:         NSColor   = .systemRed
    var currentFontName:      String    = "Helvetica-Bold"
    var currentFontSize:      CGFloat   = 24
    var currentFontColor:     NSColor   = .white
    var currentOutlineColor:  NSColor   = .black
    var currentOutlineWeight: CGFloat   = 2
    var currentShapeType:     ShapeType = .rectangle
    var currentBorderWeight:  CGFloat   = 2
    var currentBorderColor:   NSColor   = .black
    var currentFillColor:     NSColor   = .clear
    var currentBlurIntensity: CGFloat   = 80
    var currentBlurStyle:     BlurStyle = .blur
    var currentHighlightColor:   NSColor = NSColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0)
    var currentHighlightOpacity: CGFloat = 0.4

    // MARK: Active tool
    var activeTool: AnnotationTool = .none {
        didSet {
            window?.invalidateCursorRects(for: self)
            if activeTool != .arrow     { selectedArrowID = nil }
            if activeTool != .text      { finalizeEditing(); selectedTextID = nil }
            if activeTool != .shape     { selectedShapeID = nil }
            if activeTool != .blur      { selectedBlurID = nil }
            if activeTool != .highlight { selectedHighlightID = nil }
            needsDisplay = true
        }
    }

    // MARK: Callbacks
    var imageDisplayRectProvider: (() -> CGRect)?
    var onCopy:                   (() -> Void)?
    var onTextSelectionChanged:   ((TextAnnotation?) -> Void)?
    var onActivateTool:           ((AnnotationTool) -> Void)?
    var onSelectionChanged:       ((AnnotationTool) -> Void)?  // fires when a hit-test selects an annotation
    var imageProvider:            (() -> NSImage?)?
    /// Fires with a normalized (0-1) rect when the user finishes dragging an OCR region.
    var onOCRRegionSelected:      ((CGRect) -> Void)?

    // MARK: Selection state (view-only, not model)
    private var selectedArrowID: UUID?
    private var selectedTextID:  UUID? {
        didSet {
            let ann = selectedTextID.flatMap { id in textAnnotations.first { $0.id == id } }
            onTextSelectionChanged?(ann)
        }
    }
    private var selectedShapeID:     UUID?
    private var selectedBlurID:      UUID?
    private var selectedHighlightID: UUID?

    enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

    fileprivate enum DragState {
        case none
        case newArrow(start: CGPoint, current: CGPoint)
        case movingArrowWhole(id: UUID, origStart: CGPoint, origEnd: CGPoint, lastLoc: CGPoint)
        case movingArrowTail(id: UUID, origStart: CGPoint)
        case movingText(id: UUID, origPos: CGPoint, lastLoc: CGPoint)
        case newShape(start: CGPoint, current: CGPoint)
        case movingShapeWhole(id: UUID, origRect: CGRect, lastLoc: CGPoint)
        case resizingShape(id: UUID, corner: ResizeCorner, originalRect: CGRect)
        case newBlur(start: CGPoint, current: CGPoint)
        case movingBlurWhole(id: UUID, origRect: CGRect, lastLoc: CGPoint)
        case resizingBlur(id: UUID, corner: ResizeCorner, originalRect: CGRect)
        case newHighlight(start: CGPoint, current: CGPoint)
        case movingHighlightWhole(id: UUID, origRect: CGRect, lastLoc: CGPoint)
        case resizingHighlight(id: UUID, corner: ResizeCorner, originalRect: CGRect)
        case newOCR(start: CGPoint, current: CGPoint)
    }
    private var dragState: DragState = .none

    // Live drag scratch vars — updated each mouseDragged tick, committed at mouseUp.
    private var liveDragArrowStart: CGPoint?
    private var liveDragArrowEnd:   CGPoint?
    private var liveDragRect:       CGRect?
    private var liveDragTextPos:    CGPoint?   // for text move preview
    // Anchor point (view coords) captured at mouseDown for whole-move drags.
    private var dragAnchor:         CGPoint = .zero

    // Inline text editing
    private var editingScrollView: NSScrollView?
    private var editingTextView:   EscapableTextView?
    private var editingID:         UUID?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    var imageDisplayRect: CGRect { imageDisplayRectProvider?() ?? bounds }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        struct DrawItem { let zOrder: Int; let draw: () -> Void }
        var items: [DrawItem] = []

        for arrow in arrows {
            let a = arrow
            let drawStart: CGPoint
            let drawEnd:   CGPoint
            if (dragState.isMovingArrow(id: a.id) || dragState.isMovingArrowTail(id: a.id)),
               let ls = liveDragArrowStart, let le = liveDragArrowEnd {
                drawStart = toView(ls); drawEnd = toView(le)
            } else {
                drawStart = toView(a.start); drawEnd = toView(a.end)
            }
            items.append(DrawItem(zOrder: a.zOrder) {
                self.renderArrow(from: drawStart, to: drawEnd, weight: a.weight, color: a.color)
                if self.selectedArrowID == a.id {
                    self.drawArrowTailHandle(at: drawStart)
                }
            })
        }

        for ann in textAnnotations {
            let a = ann
            guard a.id != editingID else { continue }
            items.append(DrawItem(zOrder: a.zOrder) {
                var drawAnn = a
                if case .movingText(let id, _, _) = self.dragState,
                   id == a.id, let lp = self.liveDragTextPos {
                    drawAnn.position = lp
                }
                self.drawTextAnnotation(drawAnn, selected: self.selectedTextID == a.id)
            })
        }

        for shape in shapes {
            let s = shape
            let drawRect: CGRect
            if dragState.isMovingOrResizingShape(id: s.id), let lr = liveDragRect {
                drawRect = lr
            } else {
                let viewOrigin = toView(s.rect.origin)
                let viewSize = CGSize(width: s.rect.width * imageDisplayRect.width,
                                     height: s.rect.height * imageDisplayRect.height)
                drawRect = CGRect(origin: viewOrigin, size: viewSize)
            }
            items.append(DrawItem(zOrder: s.zOrder) {
                self.drawShapeRect(drawRect.standardized, shapeType: s.shapeType,
                                   borderWeight: s.borderWeight, borderColor: s.borderColor,
                                   fillColor: s.fillColor, selected: self.selectedShapeID == s.id)
                if self.selectedShapeID == s.id {
                    self.drawCornerHandles(for: drawRect.standardized)
                }
            })
        }

        for region in blurRegions {
            let r = region
            let drawRect: CGRect
            let sampleRect: CGRect  // normalized rect used to sample pixels from the source image
            if dragState.isMovingOrResizingBlur(id: r.id), let lr = liveDragRect {
                drawRect   = lr
                sampleRect = viewRectToNorm(lr.standardized)
            } else {
                let viewOrigin = toView(r.rect.origin)
                let viewSize = CGSize(width: r.rect.width * imageDisplayRect.width,
                                     height: r.rect.height * imageDisplayRect.height)
                drawRect   = CGRect(origin: viewOrigin, size: viewSize)
                sampleRect = r.rect
            }
            items.append(DrawItem(zOrder: r.zOrder) {
                var drawRegion = r
                drawRegion.rect = sampleRect
                self.drawBlurRegion(drawRegion, viewRect: drawRect.standardized,
                                    selected: self.selectedBlurID == r.id)
            })
        }

        for highlight in highlights {
            let h = highlight
            let drawRect: CGRect
            if dragState.isMovingOrResizingHighlight(id: h.id), let lr = liveDragRect {
                drawRect = lr
            } else {
                let viewOrigin = toView(h.rect.origin)
                let viewSize = CGSize(width: h.rect.width * imageDisplayRect.width,
                                     height: h.rect.height * imageDisplayRect.height)
                drawRect = CGRect(origin: viewOrigin, size: viewSize)
            }
            items.append(DrawItem(zOrder: h.zOrder) {
                self.drawHighlightRect(drawRect.standardized, color: h.color,
                                       opacity: h.opacity,
                                       selected: self.selectedHighlightID == h.id)
                if self.selectedHighlightID == h.id {
                    self.drawCornerHandles(for: drawRect.standardized)
                }
            })
        }

        items.sorted { $0.zOrder < $1.zOrder }.forEach { $0.draw() }

        // In-progress new annotations drawn on top.
        if case .newArrow(let s, let c) = dragState {
            renderArrow(from: s, to: c, weight: currentWeight, color: currentColor)
        }
        if case .newShape(let s, let c) = dragState {
            let rect = CGRect(origin: s, size: CGSize(width: c.x-s.x, height: c.y-s.y)).standardized
            drawShapeRect(rect, shapeType: currentShapeType,
                         borderWeight: currentBorderWeight, borderColor: currentBorderColor,
                         fillColor: currentFillColor, selected: false)
        }
        if case .newBlur(let s, let c) = dragState {
            let rect = CGRect(origin: s, size: CGSize(width: c.x-s.x, height: c.y-s.y)).standardized
            drawBlurRegionBorder(rect, selected: false)
        }
        if case .newHighlight(let s, let c) = dragState {
            let rect = CGRect(origin: s, size: CGSize(width: c.x-s.x, height: c.y-s.y)).standardized
            drawHighlightRect(rect, color: currentHighlightColor,
                              opacity: currentHighlightOpacity, selected: false)
        }
        if case .newOCR(let s, let c) = dragState {
            let rect = CGRect(origin: s, size: CGSize(width: c.x-s.x, height: c.y-s.y)).standardized
            drawOCRRegion(rect)
        }
    }

    // MARK: - Draw helpers

    private func drawTextAnnotation(_ ann: TextAnnotation, selected: Bool) {
        let pt = toView(ann.position)
        let font = NSFont(name: ann.fontName, size: ann.fontSize)
                   ?? NSFont.boldSystemFont(ofSize: ann.fontSize)
        if !ann.content.isEmpty {
            if ann.outlineWeight > 0 {
                makeTextAttrStr(ann.content, font: font, fontColor: .clear,
                                outlineColor: ann.outlineColor,
                                outlineWeight: ann.outlineWeight, strokeOnly: true).draw(at: pt)
            }
            makeTextAttrStr(ann.content, font: font, fontColor: ann.fontColor,
                            outlineColor: ann.outlineColor,
                            outlineWeight: ann.outlineWeight, strokeOnly: false).draw(at: pt)
        }
        if selected {
            let size: CGSize = ann.content.isEmpty
                ? CGSize(width: max(80, ann.fontSize * 4), height: ann.fontSize * 1.4)
                : makeTextAttrStr(ann.content, font: font, fontColor: ann.fontColor,
                                  outlineColor: ann.outlineColor,
                                  outlineWeight: ann.outlineWeight, strokeOnly: false).size()
            let selRect = CGRect(x: pt.x-4, y: pt.y - abs(font.descender) - 2,
                                 width: size.width+8, height: size.height+4)
            let path = NSBezierPath(rect: selRect)
            path.lineWidth = 1.5
            NSColor.selectedControlColor.withAlphaComponent(0.9).setStroke()
            path.setLineDash([5, 3], count: 2, phase: 0); path.stroke()
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
            head.line(to: CGPoint(x: to.x - headLen * cos(angle+sign),
                                  y: to.y - headLen * sin(angle+sign)))
        }
        head.lineWidth = weight; color.setStroke(); head.stroke()
    }

    private func drawArrowTailHandle(at point: CGPoint) {
        let r: CGFloat = 7
        let circle = NSBezierPath(ovalIn: CGRect(x: point.x-r, y: point.y-r,
                                                  width: r*2, height: r*2))
        NSColor.white.setFill(); circle.fill()
        NSColor.systemBlue.setStroke(); circle.lineWidth = 2; circle.stroke()
    }

    private func drawShapeRect(_ rect: CGRect, shapeType: ShapeType,
                               borderWeight: CGFloat, borderColor: NSColor,
                               fillColor: NSColor, selected: Bool) {
        let r = rect.standardized
        let path = NSBezierPath()
        switch shapeType {
        case .circle:           path.appendOval(in: r)
        case .rectangle:        path.appendRect(r)
        case .roundedRectangle: path.appendRoundedRect(r, xRadius: 10, yRadius: 10)
        }
        if fillColor.alphaComponent > 0 { fillColor.setFill(); path.fill() }
        borderColor.setStroke(); path.lineWidth = borderWeight; path.stroke()
        if selected {
            let selPath = NSBezierPath(rect: CGRect(x: r.minX-4, y: r.minY-4,
                                                    width: r.width+8, height: r.height+8))
            selPath.lineWidth = 1.5
            NSColor.selectedControlColor.withAlphaComponent(0.9).setStroke()
            selPath.setLineDash([5, 3], count: 2, phase: 0); selPath.stroke()
        }
    }

    private func drawResizeHandle(at point: CGPoint) {
        let r: CGFloat = 5
        let circle = NSBezierPath(ovalIn: CGRect(x: point.x-r, y: point.y-r,
                                                  width: r*2, height: r*2))
        NSColor.white.setFill(); circle.fill()
        NSColor.systemBlue.setStroke(); circle.lineWidth = 2; circle.stroke()
    }

    private func drawCornerHandles(for viewRect: CGRect) {
        let r = viewRect.standardized
        drawResizeHandle(at: CGPoint(x: r.minX, y: r.minY))
        drawResizeHandle(at: CGPoint(x: r.maxX, y: r.minY))
        drawResizeHandle(at: CGPoint(x: r.minX, y: r.maxY))
        drawResizeHandle(at: CGPoint(x: r.maxX, y: r.maxY))
    }

    private func drawBlurRegion(_ region: BlurRegion, viewRect: CGRect, selected: Bool) {
        if let image = imageProvider?(),
           let baseCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let cgW = CGFloat(baseCG.width), cgH = CGFloat(baseCG.height)
            let pixelRect = CGRect(x: region.rect.origin.x * cgW,
                                   y: region.rect.origin.y * cgH,
                                   width: region.rect.width * cgW,
                                   height: region.rect.height * cgH).standardized
            if pixelRect.width > 1, pixelRect.height > 1,
               let offCtx = CGContext(data: nil, width: Int(cgW), height: Int(cgH),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                offCtx.draw(baseCG, in: CGRect(x: 0, y: 0, width: cgW, height: cgH))
                let ciCtx = CIContext(cgContext: offCtx, options: nil)
                if let filtered = blurFilter(ciImage: CIImage(cgImage: baseCG),
                                             pixelRect: pixelRect, style: region.style,
                                             intensity: region.intensity,
                                             imageSize: CGSize(width: cgW, height: cgH)) {
                    ciCtx.draw(filtered, in: pixelRect, from: pixelRect)
                }
                if let resultCG = offCtx.makeImage() {
                    let resultNS = NSImage(cgImage: resultCG,
                                          size: NSSize(width: cgW, height: cgH))
                    resultNS.draw(in: viewRect, from: pixelRect,
                                  operation: .sourceOver, fraction: 1.0)
                    drawBlurRegionBorder(viewRect, selected: selected)
                    if selected { drawCornerHandles(for: viewRect) }
                    return
                }
            }
        }
        drawBlurRegionBorder(viewRect, selected: selected)
        if selected { drawCornerHandles(for: viewRect) }
    }

    private func drawBlurRegionBorder(_ rect: CGRect, selected: Bool) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = selected ? 2 : 1.5
        (selected ? NSColor.selectedControlColor
                  : NSColor.white.withAlphaComponent(0.6)).setStroke()
        path.setLineDash([6, 3], count: 2, phase: 0); path.stroke()
    }

    private func drawHighlightRect(_ rect: CGRect, color: NSColor,
                                    opacity: CGFloat, selected: Bool) {
        color.withAlphaComponent(min(max(opacity, 0.05), 0.85)).setFill()
        NSBezierPath(rect: rect).fill()
        if selected {
            let selPath = NSBezierPath(rect: CGRect(x: rect.minX-4, y: rect.minY-4,
                                                    width: rect.width+8, height: rect.height+8))
            selPath.lineWidth = 1.5
            NSColor.selectedControlColor.withAlphaComponent(0.9).setStroke()
            selPath.setLineDash([5, 3], count: 2, phase: 0); selPath.stroke()
        }
    }

    private func drawOCRRegion(_ rect: CGRect) {
        // Semi-transparent teal fill to distinguish from other tools.
        NSColor.systemTeal.withAlphaComponent(0.15).setFill()
        NSBezierPath(rect: rect).fill()
        // Dashed teal border.
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        NSColor.systemTeal.withAlphaComponent(0.9).setStroke()
        border.setLineDash([6, 3], count: 2, phase: 0)
        border.stroke()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        // Base cursor for the active tool — overridden dynamically in mouseMoved.
        let cursor: NSCursor
        switch activeTool {
        case .arrow, .shape, .blur, .highlight, .ocr: cursor = .crosshair
        case .text:  cursor = .iBeam
        case .none:  cursor = .arrow
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if let cursor = resizeCursor(at: loc) {
            cursor.set()
        } else {
            // Restore the tool's default cursor.
            switch activeTool {
            case .arrow, .shape, .blur, .highlight, .ocr: NSCursor.crosshair.set()
            case .text:  NSCursor.iBeam.set()
            case .none:  NSCursor.arrow.set()
            }
        }
    }

    /// Returns the appropriate resize cursor if `pt` is over a corner handle
    /// of any selected rect-based annotation, otherwise nil.
    private func resizeCursor(at pt: CGPoint) -> NSCursor? {
        // Collect all rect-based annotations that have a selected state.
        var rects: [(CGRect, UUID)] = []
        if let id = selectedShapeID,
           let s = shapes.first(where: { $0.id == id }) {
            rects.append((viewRect(for: s.rect), id))
        }
        if let id = selectedBlurID,
           let r = blurRegions.first(where: { $0.id == id }) {
            rects.append((viewRect(for: r.rect), id))
        }
        if let id = selectedHighlightID,
           let h = highlights.first(where: { $0.id == id }) {
            rects.append((viewRect(for: h.rect), id))
        }

        for (vr, _) in rects {
            guard let corner = hitCorner(of: vr, at: pt) else { continue }
            let r = vr.standardized
            // Determine which diagonal the corner sits on.
            // Top-right / bottom-left → NE-SW resize (↗)
            // Top-left / bottom-right → NW-SE resize (↖)
            switch corner {
            case .topRight, .bottomLeft:
                return nesw()
            case .topLeft, .bottomRight:
                return nwse()
            }
        }

        // Also show a move cursor when hovering over any annotation body.
        let allAnnotations: [(CGRect?)] = shapes.map { viewRect(for: $0.rect) }
            + blurRegions.map { viewRect(for: $0.rect) }
            + highlights.map  { viewRect(for: $0.rect) }
        for vr in allAnnotations {
            if let vr, vr.standardized.contains(pt) { return .openHand }
        }
        return nil
    }

    /// Fallback: draw a simple diagonal arrow cursor at `angle` radians.
    private func resizeCursorFallback(angle: CGFloat) -> NSCursor {
        // Use the system's built-in resize cursors via private names as a last resort.
        // In practice the named cursor lookup above should always succeed on macOS 10.15+.
        return .arrow
    }

    // macOS doesn't expose diagonal resize cursors publicly. We load them from
    // the system cursor bundle, which has shipped since at least macOS 10.15.
    private func nesw() -> NSCursor {
        // NE-SW diagonal (↗↙) — used for top-right and bottom-left corners.
        if let c = loadSystemCursor("resizenortheastsouthwest") { return c }
        return .resizeLeftRight   // reasonable fallback
    }
    private func nwse() -> NSCursor {
        // NW-SE diagonal (↖↘) — used for top-left and bottom-right corners.
        if let c = loadSystemCursor("resizenorthwestsoutheast") { return c }
        return .resizeLeftRight
    }
    private func loadSystemCursor(_ name: String) -> NSCursor? {
        let url = URL(fileURLWithPath:
            "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/" +
            "Frameworks/HIServices.framework/Versions/A/Resources/cursors/\(name)/cursor.pdf")
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }

    // MARK: - Coordinate helpers
    // All stored coordinates are normalized (0-1) with y=0 at the bottom of the
    // image rect (matching Core Graphics / image pixel convention).
    // View coordinates have y=0 at the top (NSView is not flipped here).

    /// Convert a normalized image-space point to view coordinates.
    func toView(_ norm: CGPoint) -> CGPoint {
        let r = imageDisplayRect
        // norm.y=0 is the bottom of the image; in view coords bottom = r.minY
        return CGPoint(x: r.minX + norm.x * r.width,
                       y: r.minY + norm.y * r.height)
    }

    /// Convert a view-space point to normalized image coordinates.
    func toNorm(_ view: CGPoint) -> CGPoint {
        let r = imageDisplayRect
        guard r.width > 0, r.height > 0 else { return .zero }
        return CGPoint(x: (view.x - r.minX) / r.width,
                       y: (view.y - r.minY) / r.height)
    }

    /// Convert a normalized rect to view coordinates.
    private func normRectToView(_ norm: CGRect) -> CGRect {
        let origin = toView(norm.origin)
        let r = imageDisplayRect
        return CGRect(origin: origin,
                      size: CGSize(width: norm.width * r.width,
                                   height: norm.height * r.height))
    }

    /// Convert a view-space rect to normalized image coordinates.
    private func viewRectToNorm(_ viewRect: CGRect) -> CGRect {
        let r = imageDisplayRect
        guard r.width > 0, r.height > 0 else { return .zero }
        return CGRect(x: (viewRect.minX - r.minX) / r.width,
                      y: (viewRect.minY - r.minY) / r.height,
                      width: viewRect.width  / r.width,
                      height: viewRect.height / r.height)
    }

    // MARK: - Hit testing

    private let handleRadius: CGFloat = 8

    /// Returns the arrow whose tail handle is within handleRadius of `pt`, or nil.
    /// Checks in descending z-order so the topmost arrow wins.
    private func hitArrowTail(at pt: CGPoint) -> UUID? {
        for arrow in arrows.sorted(by: { $0.zOrder > $1.zOrder }) {
            let tail = toView(arrow.start)
            if hypot(pt.x - tail.x, pt.y - tail.y) <= handleRadius { return arrow.id }
        }
        return nil
    }

    /// Returns the arrow whose body is within a few points of `pt`, or nil.
    /// Checks in descending z-order so the topmost arrow wins.
    private func hitArrowBody(at pt: CGPoint) -> UUID? {
        for arrow in arrows.sorted(by: { $0.zOrder > $1.zOrder }) {
            let s = toView(arrow.start), e = toView(arrow.end)
            let len = hypot(e.x - s.x, e.y - s.y)
            guard len > 0 else { continue }
            let t = ((pt.x - s.x) * (e.x - s.x) + (pt.y - s.y) * (e.y - s.y)) / (len * len)
            let tc = max(0, min(1, t))
            let closest = CGPoint(x: s.x + tc * (e.x - s.x), y: s.y + tc * (e.y - s.y))
            if hypot(pt.x - closest.x, pt.y - closest.y) <= max(arrow.weight / 2 + 4, 8) {
                return arrow.id
            }
        }
        return nil
    }

    /// Returns the corner being hit for a view-space rect, or nil.
    private func hitCorner(of viewRect: CGRect, at pt: CGPoint) -> ResizeCorner? {
        let r = viewRect.standardized
        let corners: [(CGPoint, ResizeCorner)] = [
            (CGPoint(x: r.minX, y: r.minY), .bottomLeft),
            (CGPoint(x: r.maxX, y: r.minY), .bottomRight),
            (CGPoint(x: r.minX, y: r.maxY), .topLeft),
            (CGPoint(x: r.maxX, y: r.maxY), .topRight),
        ]
        for (corner, which) in corners {
            if hypot(pt.x - corner.x, pt.y - corner.y) <= handleRadius { return which }
        }
        return nil
    }

    private func viewRect(for normRect: CGRect) -> CGRect {
        normRectToView(normRect)
    }

    // MARK: - Universal hit-test

    /// Checks all annotation types for a hit at `loc`. If found, selects the
    /// annotation, sets up the appropriate drag state, and returns true.
    /// Returns false if nothing was hit (caller should proceed with tool logic).
    @discardableResult
    private func hitTestAndStartDrag(at loc: CGPoint, clickCount: Int = 1) -> Bool {
        // Arrow tail handle (only when an arrow is already selected).
        if let selID = selectedArrowID, hitArrowTail(at: loc) == selID,
           let arrow = arrows.first(where: { $0.id == selID }) {
            dragState = .movingArrowTail(id: selID, origStart: arrow.start)
            liveDragArrowStart = arrow.start
            liveDragArrowEnd   = arrow.end
            dragAnchor = loc
            return true
        }

        // Build a unified list of all annotations sorted by descending z-order
        // so the topmost-drawn annotation wins the hit-test.
        enum AnyAnnotation {
            case arrow(Arrow), text(TextAnnotation), shape(Shape)
            case blur(BlurRegion), highlight(Highlight)
            var zOrder: Int {
                switch self {
                case .arrow(let a):     return a.zOrder
                case .text(let t):      return t.zOrder
                case .shape(let s):     return s.zOrder
                case .blur(let b):      return b.zOrder
                case .highlight(let h): return h.zOrder
                }
            }
        }
        var all: [AnyAnnotation] = []
        arrows.forEach          { all.append(.arrow($0)) }
        textAnnotations.forEach { all.append(.text($0)) }
        shapes.forEach          { all.append(.shape($0)) }
        blurRegions.forEach     { all.append(.blur($0)) }
        highlights.forEach      { all.append(.highlight($0)) }
        all.sort { $0.zOrder > $1.zOrder }

        for item in all {
            switch item {
            case .arrow(let arrow):
                let s = toView(arrow.start), e = toView(arrow.end)
                let len = hypot(e.x - s.x, e.y - s.y)
                guard len > 0 else { continue }
                let t = ((loc.x-s.x)*(e.x-s.x) + (loc.y-s.y)*(e.y-s.y)) / (len*len)
                let tc = max(0, min(1, t))
                let closest = CGPoint(x: s.x + tc*(e.x-s.x), y: s.y + tc*(e.y-s.y))
                if hypot(loc.x-closest.x, loc.y-closest.y) <= max(arrow.weight/2+4, 8) {
                    clearAllSelections()
                    selectedArrowID = arrow.id
                    dragState = .movingArrowWhole(id: arrow.id, origStart: arrow.start,
                                                  origEnd: arrow.end, lastLoc: loc)
                    liveDragArrowStart = arrow.start
                    liveDragArrowEnd   = arrow.end
                    dragAnchor = loc; needsDisplay = true
                    notifySelection(.arrow)
                    return true
                }

            case .text(let ann):
                if editingID == ann.id { return false }
                let pt = toView(ann.position)
                let font = NSFont(name: ann.fontName, size: ann.fontSize)
                           ?? NSFont.boldSystemFont(ofSize: ann.fontSize)
                let size: CGSize = ann.content.isEmpty
                    ? CGSize(width: max(80, ann.fontSize*4), height: ann.fontSize*1.4)
                    : makeTextAttrStr(ann.content, font: font, fontColor: ann.fontColor,
                                      outlineColor: ann.outlineColor,
                                      outlineWeight: ann.outlineWeight, strokeOnly: false).size()
                let hitRect = CGRect(x: pt.x-4, y: pt.y - abs(font.descender) - 2,
                                     width: size.width+8, height: size.height+4)
                if hitRect.contains(loc) {
                    clearAllSelections()
                    if clickCount >= 2 {
                        selectedTextID = ann.id; beginEditing(ann)
                    } else {
                        selectedTextID = ann.id
                        dragState = .movingText(id: ann.id, origPos: ann.position, lastLoc: loc)
                        dragAnchor = loc; needsDisplay = true
                    }
                    notifySelection(.text)
                    return true
                }

            case .shape(let shape):
                let vr = viewRect(for: shape.rect)
                if let corner = hitCorner(of: vr, at: loc) {
                    clearAllSelections()
                    selectedShapeID = shape.id
                    dragState = .resizingShape(id: shape.id, corner: corner,
                                               originalRect: shape.rect)
                    liveDragRect = vr; needsDisplay = true
                    notifySelection(.shape)
                    return true
                }
                if vr.standardized.contains(loc) {
                    clearAllSelections()
                    selectedShapeID = shape.id
                    dragState = .movingShapeWhole(id: shape.id, origRect: shape.rect, lastLoc: loc)
                    liveDragRect = vr; dragAnchor = loc; needsDisplay = true
                    notifySelection(.shape)
                    return true
                }

            case .blur(let region):
                let vr = viewRect(for: region.rect)
                if let corner = hitCorner(of: vr, at: loc) {
                    clearAllSelections()
                    selectedBlurID = region.id
                    dragState = .resizingBlur(id: region.id, corner: corner,
                                              originalRect: region.rect)
                    liveDragRect = vr; needsDisplay = true
                    notifySelection(.blur)
                    return true
                }
                if vr.standardized.contains(loc) {
                    clearAllSelections()
                    selectedBlurID = region.id
                    dragState = .movingBlurWhole(id: region.id, origRect: region.rect, lastLoc: loc)
                    liveDragRect = vr; dragAnchor = loc; needsDisplay = true
                    notifySelection(.blur)
                    return true
                }

            case .highlight(let h):
                let vr = viewRect(for: h.rect)
                if let corner = hitCorner(of: vr, at: loc) {
                    clearAllSelections()
                    selectedHighlightID = h.id
                    dragState = .resizingHighlight(id: h.id, corner: corner,
                                                   originalRect: h.rect)
                    liveDragRect = vr; needsDisplay = true
                    notifySelection(.highlight)
                    return true
                }
                if vr.standardized.contains(loc) {
                    clearAllSelections()
                    selectedHighlightID = h.id
                    dragState = .movingHighlightWhole(id: h.id, origRect: h.rect, lastLoc: loc)
                    liveDragRect = vr; dragAnchor = loc; needsDisplay = true
                    notifySelection(.highlight)
                    return true
                }
            }
        }
        return false
    }

    /// Clears all selection IDs. Safe to call before setting a new selection.
    private func clearAllSelections() {
        selectedArrowID     = nil
        selectedTextID      = nil
        selectedShapeID     = nil
        selectedBlurID      = nil
        selectedHighlightID = nil
    }

    /// Call after setting a new selection to notify the window controller.
    private func notifySelection(_ tool: AnnotationTool) {
        onSelectionChanged?(tool)
    }

    // MARK: - Mouse down

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let imgRect = imageDisplayRect

        // ── Universal hit-test: clicking any existing annotation always wins,
        //    regardless of which tool is active. ─────────────────────────────────
        if hitTestAndStartDrag(at: loc, clickCount: event.clickCount) { return }

        // If we were editing text and clicked somewhere that didn't hit the text
        // view, finalize the edit before proceeding.
        if editingID != nil { finalizeEditing() }

        // Clicking empty space clears all selections.
        clearAllSelections()
        // Only reset the toolbar highlight if no tool is currently active.
        if activeTool == .none { notifySelection(.none) }

        switch activeTool {

        // ── Arrow ────────────────────────────────────────────────────────────────
        case .arrow:
            // No existing annotation was hit — start a new arrow.
            if imgRect.contains(loc) {
                selectedArrowID = nil
                dragState = .newArrow(start: loc, current: loc)
                needsDisplay = true
            }

        // ── Text ─────────────────────────────────────────────────────────────────
        case .text:
            let hadSelection = selectedTextID != nil
            // Missed all annotations (hitTestAndStartDrag returned false).
            if editingID != nil {
                finalizeEditing()
            } else if hadSelection {
                // already cleared by clearAllSelections above
            } else if imgRect.contains(loc) {
                let norm = toNorm(loc)
                let newAnn = TextAnnotation(
                    id: UUID(), zOrder: document?.nextZOrder() ?? 0,
                    position: norm, content: "",
                    fontName: currentFontName, fontSize: currentFontSize,
                    fontColor: currentFontColor, outlineColor: currentOutlineColor,
                    outlineWeight: currentOutlineWeight)
                document?.addTextAnnotation(newAnn)
                selectedTextID = newAnn.id
                beginEditing(newAnn)
            }

        // ── Shape ────────────────────────────────────────────────────────────────
        case .shape:
            // No existing annotation hit — start a new shape.
            if imgRect.contains(loc) {
                selectedShapeID = nil
                dragState = .newShape(start: loc, current: loc)
                needsDisplay = true
            }

        // ── Blur ─────────────────────────────────────────────────────────────────
        case .blur:
            // No existing annotation hit — start a new blur region.
            if imgRect.contains(loc) {
                selectedBlurID = nil
                dragState = .newBlur(start: loc, current: loc)
                needsDisplay = true
            }

        // ── Highlight ────────────────────────────────────────────────────────────
        case .highlight:
            // No existing annotation hit — start a new highlight.
            if imgRect.contains(loc) {
                selectedHighlightID = nil
                dragState = .newHighlight(start: loc, current: loc)
                needsDisplay = true
            }

        // ── OCR ──────────────────────────────────────────────────────────────────
        case .ocr:
            if imgRect.contains(loc) {
                dragState = .newOCR(start: loc, current: loc)
                needsDisplay = true
            }

        case .none:
            break
        }
    }

    // MARK: - Mouse dragged

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let imgRect = imageDisplayRect
        // Clamp to image bounds so annotations can't be dragged outside.
        let clamped = loc.clamped(to: imgRect)
        let shiftDown = event.modifierFlags.contains(.shift)

        switch dragState {

        case .newArrow(let start, _):
            var end = clamped
            if shiftDown {
                let dx = end.x - start.x, dy = end.y - start.y
                if abs(dx) > abs(dy) { end.y = start.y } else { end.x = start.x }
            }
            dragState = .newArrow(start: start, current: end)

        case .movingArrowWhole(let id, let origStart, let origEnd, let lastLoc):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            _ = lastLoc
            let totalDX = (loc.x - dragAnchor.x) / r.width
            let totalDY = (loc.y - dragAnchor.y) / r.height
            liveDragArrowStart = CGPoint(x: origStart.x + totalDX, y: origStart.y + totalDY)
            liveDragArrowEnd   = CGPoint(x: origEnd.x   + totalDX, y: origEnd.y   + totalDY)
            dragState = .movingArrowWhole(id: id, origStart: origStart,
                                          origEnd: origEnd, lastLoc: loc)

        case .movingArrowTail(let id, let origStart):
            _ = origStart
            liveDragArrowStart = toNorm(clamped)

        case .movingText(let id, let origPos, let lastLoc):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            _ = lastLoc
            let totalDX = (loc.x - dragAnchor.x) / r.width
            let totalDY = (loc.y - dragAnchor.y) / r.height
            // Update position live for visual feedback without registering undo each tick.
            // The document commit (with undo) happens at mouseUp.
            liveDragTextPos = CGPoint(x: origPos.x + totalDX, y: origPos.y + totalDY)
            dragState = .movingText(id: id, origPos: origPos, lastLoc: loc)

        case .newShape(let start, _):
            var end = clamped
            if shiftDown {
                let side = min(abs(end.x - start.x), abs(end.y - start.y))
                end.x = start.x + (end.x >= start.x ? side : -side)
                end.y = start.y + (end.y >= start.y ? side : -side)
            }
            dragState = .newShape(start: start, current: end)

        case .movingShapeWhole(let id, let origRect, let lastLoc):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            // Accumulate total offset from the drag-start position stored in origRect,
            // using the anchor point captured at mouseDown (lastLoc holds drag-start).
            _ = lastLoc
            let totalDX = (loc.x - dragAnchor.x) / r.width
            let totalDY = (loc.y - dragAnchor.y) / r.height
            let newRect = CGRect(x: origRect.minX + totalDX, y: origRect.minY + totalDY,
                                 width: origRect.width, height: origRect.height)
            liveDragRect = viewRect(for: newRect)
            dragState = .movingShapeWhole(id: id, origRect: origRect, lastLoc: loc)

        case .resizingShape(let id, let corner, let originalRect):
            liveDragRect = resizedViewRect(originalRect: originalRect, corner: corner,
                                           currentLoc: clamped, shift: shiftDown)

        case .newBlur(let start, _):
            var end = clamped
            if shiftDown {
                let side = min(abs(end.x - start.x), abs(end.y - start.y))
                end.x = start.x + (end.x >= start.x ? side : -side)
                end.y = start.y + (end.y >= start.y ? side : -side)
            }
            dragState = .newBlur(start: start, current: end)

        case .movingBlurWhole(let id, let origRect, let lastLoc):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            _ = lastLoc
            let totalDX = (loc.x - dragAnchor.x) / r.width
            let totalDY = (loc.y - dragAnchor.y) / r.height
            let newRect = CGRect(x: origRect.minX + totalDX, y: origRect.minY + totalDY,
                                 width: origRect.width, height: origRect.height)
            liveDragRect = viewRect(for: newRect)
            dragState = .movingBlurWhole(id: id, origRect: origRect, lastLoc: loc)

        case .resizingBlur(let id, let corner, let originalRect):
            liveDragRect = resizedViewRect(originalRect: originalRect, corner: corner,
                                           currentLoc: clamped, shift: shiftDown)

        case .newHighlight(let start, _):
            var end = clamped
            if shiftDown {
                let side = min(abs(end.x - start.x), abs(end.y - start.y))
                end.x = start.x + (end.x >= start.x ? side : -side)
                end.y = start.y + (end.y >= start.y ? side : -side)
            }
            dragState = .newHighlight(start: start, current: end)

        case .movingHighlightWhole(let id, let origRect, let lastLoc):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            _ = lastLoc
            let totalDX = (loc.x - dragAnchor.x) / r.width
            let totalDY = (loc.y - dragAnchor.y) / r.height
            let newRect = CGRect(x: origRect.minX + totalDX, y: origRect.minY + totalDY,
                                 width: origRect.width, height: origRect.height)
            liveDragRect = viewRect(for: newRect)
            dragState = .movingHighlightWhole(id: id, origRect: origRect, lastLoc: loc)

        case .resizingHighlight(let id, let corner, let originalRect):
            liveDragRect = resizedViewRect(originalRect: originalRect, corner: corner,
                                           currentLoc: clamped, shift: shiftDown)

        case .newOCR(let start, _):
            var end = clamped
            if shiftDown {
                let side = min(abs(end.x - start.x), abs(end.y - start.y))
                end.x = start.x + (end.x >= start.x ? side : -side)
                end.y = start.y + (end.y >= start.y ? side : -side)
            }
            dragState = .newOCR(start: start, current: end)

        case .none:
            break
        }
        needsDisplay = true
    }

    /// Compute the new view-space rect while resizing a corner handle.
    private func resizedViewRect(originalRect: CGRect, corner: ResizeCorner,
                                  currentLoc: CGPoint, shift: Bool) -> CGRect {
        let orig = viewRect(for: originalRect)
        var minX = orig.minX, minY = orig.minY
        var maxX = orig.maxX, maxY = orig.maxY
        switch corner {
        case .bottomLeft:  minX = currentLoc.x; minY = currentLoc.y
        case .bottomRight: maxX = currentLoc.x; minY = currentLoc.y
        case .topLeft:     minX = currentLoc.x; maxY = currentLoc.y
        case .topRight:    maxX = currentLoc.x; maxY = currentLoc.y
        }
        if shift {
            let w = abs(maxX - minX), h = abs(maxY - minY)
            let side = min(w, h)
            switch corner {
            case .bottomLeft:  minX = maxX - side; minY = maxY - side
            case .bottomRight: maxX = minX + side; minY = maxY - side
            case .topLeft:     minX = maxX - side; maxY = minY + side
            case .topRight:    maxX = minX + side; maxY = minY + side
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Mouse up

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let clamped = loc.clamped(to: imageDisplayRect)

        switch dragState {

        case .newArrow(let start, let current):
            let s = toNorm(start), e = toNorm(current)
            if hypot(e.x - s.x, e.y - s.y) > 0.005 {
                let arrow = Arrow(id: UUID(), zOrder: document?.nextZOrder() ?? 0,
                                  start: s, end: e,
                                  weight: currentWeight, color: currentColor)
                document?.addArrow(arrow)
                selectedArrowID = arrow.id
            }

        case .movingArrowWhole(let id, let origStart, let origEnd, _):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            let totalDX = (clamped.x - dragAnchor.x) / r.width
            let totalDY = (clamped.y - dragAnchor.y) / r.height
            document?.updateArrow(id: id,
                start: CGPoint(x: origStart.x + totalDX, y: origStart.y + totalDY),
                end:   CGPoint(x: origEnd.x   + totalDX, y: origEnd.y   + totalDY))

        case .movingArrowTail(let id, _):
            if let ls = liveDragArrowStart, let le = liveDragArrowEnd {
                document?.updateArrow(id: id, start: ls, end: le)
            }

        case .movingText(let id, let origPos, _):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            let totalDX = (clamped.x - dragAnchor.x) / r.width
            let totalDY = (clamped.y - dragAnchor.y) / r.height
            let newPos = CGPoint(x: origPos.x + totalDX, y: origPos.y + totalDY)
            document?.updateTextAnnotation(id: id, position: newPos)

        case .newShape(let start, let current):
            let normRect = viewRectToNorm(
                CGRect(origin: start,
                       size: CGSize(width: current.x - start.x,
                                    height: current.y - start.y)).standardized)
            if normRect.width > 0.005, normRect.height > 0.005 {
                let shape = Shape(id: UUID(), zOrder: document?.nextZOrder() ?? 0,
                                  rect: normRect, shapeType: currentShapeType,
                                  borderWeight: currentBorderWeight,
                                  borderColor: currentBorderColor,
                                  fillColor: currentFillColor)
                document?.addShape(shape)
                selectedShapeID = shape.id
            }

        case .movingShapeWhole(let id, let origRect, _):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            let totalDX = (clamped.x - dragAnchor.x) / r.width
            let totalDY = (clamped.y - dragAnchor.y) / r.height
            let newRect = CGRect(x: origRect.minX + totalDX, y: origRect.minY + totalDY,
                                 width: origRect.width, height: origRect.height)
            document?.updateShape(id: id, rect: newRect)

        case .resizingShape(let id, _, _):
            if let lr = liveDragRect {
                document?.updateShape(id: id, rect: viewRectToNorm(lr.standardized))
            }

        case .newBlur(let start, let current):
            let normRect = viewRectToNorm(
                CGRect(origin: start,
                       size: CGSize(width: current.x - start.x,
                                    height: current.y - start.y)).standardized)
            if normRect.width > 0.005, normRect.height > 0.005 {
                let region = BlurRegion(id: UUID(), zOrder: document?.nextZOrder() ?? 0,
                                        rect: normRect, intensity: currentBlurIntensity,
                                        style: currentBlurStyle)
                document?.addBlurRegion(region)
                selectedBlurID = region.id
            }

        case .movingBlurWhole(let id, let origRect, _):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            let totalDX = (clamped.x - dragAnchor.x) / r.width
            let totalDY = (clamped.y - dragAnchor.y) / r.height
            let newRect = CGRect(x: origRect.minX + totalDX, y: origRect.minY + totalDY,
                                 width: origRect.width, height: origRect.height)
            document?.updateBlurRegion(id: id, rect: newRect)

        case .resizingBlur(let id, _, _):
            if let lr = liveDragRect {
                document?.updateBlurRegion(id: id, rect: viewRectToNorm(lr.standardized))
            }

        case .newHighlight(let start, let current):
            let normRect = viewRectToNorm(
                CGRect(origin: start,
                       size: CGSize(width: current.x - start.x,
                                    height: current.y - start.y)).standardized)
            if normRect.width > 0.005, normRect.height > 0.005 {
                let h = Highlight(id: UUID(), zOrder: document?.nextZOrder() ?? 0,
                                  rect: normRect, color: currentHighlightColor,
                                  opacity: currentHighlightOpacity)
                document?.addHighlight(h)
                selectedHighlightID = h.id
            }

        case .movingHighlightWhole(let id, let origRect, _):
            let r = imageDisplayRect
            guard r.width > 0, r.height > 0 else { break }
            let totalDX = (clamped.x - dragAnchor.x) / r.width
            let totalDY = (clamped.y - dragAnchor.y) / r.height
            let newRect = CGRect(x: origRect.minX + totalDX, y: origRect.minY + totalDY,
                                 width: origRect.width, height: origRect.height)
            document?.updateHighlight(id: id, rect: newRect)

        case .resizingHighlight(let id, _, _):
            if let lr = liveDragRect {
                document?.updateHighlight(id: id, rect: viewRectToNorm(lr.standardized))
            }

        case .newOCR(let start, let current):
            let normRect = viewRectToNorm(
                CGRect(origin: start,
                       size: CGSize(width: current.x - start.x,
                                    height: current.y - start.y)).standardized)
            if normRect.width > 0.005, normRect.height > 0.005 {
                onOCRRegionSelected?(normRect)
            }

        case .none:
            break
        }

        dragState = .none
        liveDragArrowStart = nil
        liveDragArrowEnd   = nil
        liveDragRect       = nil
        liveDragTextPos    = nil
        needsDisplay = true
        // Restore default cursor after drag ends.
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Delete / Backspace — remove selected annotation.
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelected(); return
        }
        // Escape — deselect / cancel drag.
        if event.keyCode == 53 {
            dragState = .none
            liveDragArrowStart = nil; liveDragArrowEnd = nil; liveDragRect = nil
            selectedArrowID = nil; selectedTextID = nil
            selectedShapeID = nil; selectedBlurID = nil; selectedHighlightID = nil
            needsDisplay = true; return
        }
        super.keyDown(with: event)
    }

    private func deleteSelected() {
        if let id = selectedArrowID     { document?.removeArrow(id: id);          selectedArrowID = nil }
        if let id = selectedTextID      { document?.removeTextAnnotation(id: id); selectedTextID  = nil }
        if let id = selectedShapeID     { document?.removeShape(id: id);          selectedShapeID = nil }
        if let id = selectedBlurID      { document?.removeBlurRegion(id: id);     selectedBlurID  = nil }
        if let id = selectedHighlightID { document?.removeHighlight(id: id);      selectedHighlightID = nil }
        needsDisplay = true
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()

        // Arrow hit?
        if let id = hitArrowBody(at: loc) ?? hitArrowTail(at: loc) {
            selectedArrowID = id; needsDisplay = true
            let del = NSMenuItem(title: "Delete Arrow", action: #selector(deleteSelectedItem(_:)),
                                 keyEquivalent: "")
            del.target = self; menu.addItem(del)
            addArrangeItems(to: menu)
            return menu
        }
        // Text hit?
        for ann in textAnnotations.reversed() {
            let pt = toView(ann.position)
            let font = NSFont(name: ann.fontName, size: ann.fontSize)
                       ?? NSFont.boldSystemFont(ofSize: ann.fontSize)
            let size: CGSize = ann.content.isEmpty
                ? CGSize(width: max(80, ann.fontSize * 4), height: ann.fontSize * 1.4)
                : makeTextAttrStr(ann.content, font: font, fontColor: ann.fontColor,
                                  outlineColor: ann.outlineColor,
                                  outlineWeight: ann.outlineWeight, strokeOnly: false).size()
            let hitRect = CGRect(x: pt.x-4, y: pt.y - abs(font.descender) - 2,
                                 width: size.width+8, height: size.height+4)
            if hitRect.contains(loc) {
                selectedTextID = ann.id; needsDisplay = true
                let edit = NSMenuItem(title: "Edit Text", action: #selector(editSelectedText(_:)),
                                      keyEquivalent: "")
                edit.target = self; menu.addItem(edit)
                let del = NSMenuItem(title: "Delete Text", action: #selector(deleteSelectedItem(_:)),
                                     keyEquivalent: "")
                del.target = self; menu.addItem(del)
                addArrangeItems(to: menu)
                return menu
            }
        }
        // Shape / blur / highlight hit?
        for shape in shapes.sorted(by: { $0.zOrder > $1.zOrder }) {
            if viewRect(for: shape.rect).standardized.contains(loc) {
                selectedShapeID = shape.id; needsDisplay = true
                let del = NSMenuItem(title: "Delete Shape", action: #selector(deleteSelectedItem(_:)),
                                     keyEquivalent: "")
                del.target = self; menu.addItem(del)
                addArrangeItems(to: menu)
                return menu
            }
        }
        for region in blurRegions.sorted(by: { $0.zOrder > $1.zOrder }) {
            if viewRect(for: region.rect).standardized.contains(loc) {
                selectedBlurID = region.id; needsDisplay = true
                let del = NSMenuItem(title: "Delete Blur", action: #selector(deleteSelectedItem(_:)),
                                     keyEquivalent: "")
                del.target = self; menu.addItem(del)
                addArrangeItems(to: menu)
                return menu
            }
        }
        for h in highlights.sorted(by: { $0.zOrder > $1.zOrder }) {
            if viewRect(for: h.rect).standardized.contains(loc) {
                selectedHighlightID = h.id; needsDisplay = true
                let del = NSMenuItem(title: "Delete Highlight", action: #selector(deleteSelectedItem(_:)),
                                     keyEquivalent: "")
                del.target = self; menu.addItem(del)
                addArrangeItems(to: menu)
                return menu
            }
        }
        // Generic copy option.
        let copy = NSMenuItem(title: "Copy Image", action: #selector(copyImageAction(_:)),
                              keyEquivalent: "")
        copy.target = self; menu.addItem(copy)
        return menu
    }

    @objc private func deleteSelectedItem(_ sender: Any?) { deleteSelected() }
    @objc private func copyImageAction(_ sender: Any?)    { onCopy?() }
    @objc private func editSelectedText(_ sender: Any?) {
        guard let id = selectedTextID,
              let ann = textAnnotations.first(where: { $0.id == id }) else { return }
        beginEditing(ann)
    }

    // MARK: - Z-order actions

    private func selectedAnnotationID() -> UUID? {
        selectedArrowID ?? selectedTextID ?? selectedShapeID
            ?? selectedBlurID ?? selectedHighlightID
    }

    private func addArrangeItems(to menu: NSMenu) {
        menu.addItem(.separator())
        let fwd  = NSMenuItem(title: "Bring Forward",  action: #selector(bringForward(_:)),  keyEquivalent: "")
        let back = NSMenuItem(title: "Send Backward",  action: #selector(sendBackward(_:)),  keyEquivalent: "")
        let top  = NSMenuItem(title: "Bring to Front", action: #selector(bringToFront(_:)),  keyEquivalent: "")
        let bot  = NSMenuItem(title: "Send to Back",   action: #selector(sendToBack(_:)),    keyEquivalent: "")
        for item in [fwd, back, top, bot] { item.target = self; menu.addItem(item) }
    }

    @objc private func bringForward(_ sender: Any?) {
        guard let id = selectedAnnotationID(), let doc = document else { return }
        var pairs = doc.allZOrderPairs()
        guard let idx = pairs.firstIndex(where: { $0.id == id }), idx < pairs.count - 1 else { return }
        pairs.swapAt(idx, idx + 1)
        doc.setZOrders(pairs.enumerated().map { (id: $0.element.id, z: $0.offset) })
    }

    @objc private func sendBackward(_ sender: Any?) {
        guard let id = selectedAnnotationID(), let doc = document else { return }
        var pairs = doc.allZOrderPairs()
        guard let idx = pairs.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        pairs.swapAt(idx, idx - 1)
        doc.setZOrders(pairs.enumerated().map { (id: $0.element.id, z: $0.offset) })
    }

    @objc private func bringToFront(_ sender: Any?) {
        guard let id = selectedAnnotationID(), let doc = document else { return }
        var pairs = doc.allZOrderPairs()
        guard let idx = pairs.firstIndex(where: { $0.id == id }) else { return }
        let item = pairs.remove(at: idx)
        pairs.append(item)
        doc.setZOrders(pairs.enumerated().map { (id: $0.element.id, z: $0.offset) })
    }

    @objc private func sendToBack(_ sender: Any?) {
        guard let id = selectedAnnotationID(), let doc = document else { return }
        var pairs = doc.allZOrderPairs()
        guard let idx = pairs.firstIndex(where: { $0.id == id }) else { return }
        let item = pairs.remove(at: idx)
        pairs.insert(item, at: 0)
        doc.setZOrders(pairs.enumerated().map { (id: $0.element.id, z: $0.offset) })
    }

    // MARK: - Inline text editing

    func beginEditing(_ ann: TextAnnotation) {
        finalizeEditing()
        editingID = ann.id

        let pt = toView(ann.position)
        let font = NSFont(name: ann.fontName, size: ann.fontSize)
                   ?? NSFont.boldSystemFont(ofSize: ann.fontSize)

        let tv = EscapableTextView(frame: CGRect(x: pt.x, y: pt.y - ann.fontSize * 0.2,
                                                  width: max(120, ann.fontSize * 8),
                                                  height: ann.fontSize * 2))
        tv.onEscape = { [weak self] in self?.finalizeEditing() }
        tv.font = font
        tv.textColor = ann.fontColor
        tv.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.allowsUndo = false   // let the document's undo manager handle it
        tv.string = ann.content
        tv.selectAll(nil)

        let sv = NSScrollView(frame: tv.frame)
        sv.documentView = tv
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.drawsBackground = false
        sv.borderType = .noBorder
        addSubview(sv)

        editingScrollView = sv
        editingTextView   = tv
        window?.makeFirstResponder(tv)
        needsDisplay = true
    }

    func finalizeEditing() {
        guard let id = editingID, let tv = editingTextView else { return }
        let content = tv.string
        document?.updateTextAnnotation(id: id, content: content)
        // Remove empty annotations that were never given content.
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document?.removeTextAnnotation(id: id)
            if selectedTextID == id { selectedTextID = nil }
        }
        editingScrollView?.removeFromSuperview()
        editingScrollView = nil
        editingTextView   = nil
        editingID         = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - updateSelected* (called by EditorWindowController sidebar actions)

    /// Update the currently selected arrow's weight and/or color.
    func updateSelected(weight: CGFloat? = nil, color: NSColor? = nil) {
        guard let id = selectedArrowID else { return }
        document?.updateArrow(id: id, weight: weight, color: color)
    }

    /// Update the currently selected text annotation's properties.
    func updateSelectedText(fontName: String? = nil, fontSize: CGFloat? = nil,
                             fontColor: NSColor? = nil, outlineColor: NSColor? = nil,
                             outlineWeight: CGFloat? = nil) {
        guard let id = selectedTextID else { return }
        document?.updateTextAnnotation(id: id, fontName: fontName, fontSize: fontSize,
                                        fontColor: fontColor, outlineColor: outlineColor,
                                        outlineWeight: outlineWeight)
    }

    /// Update the currently selected shape's properties.
    func updateSelectedShape(shapeType: ShapeType? = nil, borderWeight: CGFloat? = nil,
                              borderColor: NSColor? = nil, fillColor: NSColor? = nil) {
        guard let id = selectedShapeID else { return }
        document?.updateShape(id: id, shapeType: shapeType, borderWeight: borderWeight,
                               borderColor: borderColor, fillColor: fillColor)
    }

    /// Update the currently selected blur region's properties.
    func updateSelectedBlur(intensity: CGFloat? = nil, style: BlurStyle? = nil) {
        guard let id = selectedBlurID else { return }
        document?.updateBlurRegion(id: id, intensity: intensity, style: style)
    }

    /// Update the currently selected highlight's properties.
    func updateSelectedHighlight(color: NSColor? = nil, opacity: CGFloat? = nil) {
        guard let id = selectedHighlightID else { return }
        document?.updateHighlight(id: id, color: color, opacity: opacity)
    }
}

// MARK: - DragState helpers

fileprivate extension AnnotationOverlay.DragState {
    func isMovingArrow(id: UUID) -> Bool {
        if case .movingArrowWhole(let aid, _, _, _) = self { return aid == id }
        return false
    }
    func isMovingArrowTail(id: UUID) -> Bool {
        if case .movingArrowTail(let aid, _) = self { return aid == id }
        return false
    }
    func isMovingOrResizingShape(id: UUID) -> Bool {
        if case .movingShapeWhole(let sid, _, _) = self { return sid == id }
        if case .resizingShape(let sid, _, _) = self { return sid == id }
        return false
    }
    func isMovingOrResizingBlur(id: UUID) -> Bool {
        if case .movingBlurWhole(let bid, _, _) = self { return bid == id }
        if case .resizingBlur(let bid, _, _) = self { return bid == id }
        return false
    }
    func isMovingOrResizingHighlight(id: UUID) -> Bool {
        if case .movingHighlightWhole(let hid, _, _) = self { return hid == id }
        if case .resizingHighlight(let hid, _, _) = self { return hid == id }
        return false
    }
}

// MARK: - EscapableTextView

/// NSTextView subclass that calls `onEscape` when the user presses Escape,
/// allowing the annotation overlay to finalize editing and reclaim focus.
fileprivate class EscapableTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

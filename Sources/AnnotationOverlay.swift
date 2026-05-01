import AppKit

// MARK: - Tool

enum AnnotationTool { case none, arrow, text, shape, blur }

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

    // MARK: Shape state
    var shapes: [Shape] = []
    var currentShapeType:     ShapeType = .rectangle
    var currentBorderWeight:  CGFloat = 2
    var currentBorderColor:   NSColor = .black
    var currentFillColor:     NSColor = .clear

    // MARK: Blur state
    var blurRegions: [BlurRegion] = []
    var currentBlurIntensity: CGFloat = 80
    var currentBlurStyle: BlurStyle = .blur

    // MARK: Z-order counter — incremented each time a new annotation is added.
    private var zOrderCounter: Int = 0
    private func nextZOrder() -> Int { zOrderCounter += 1; return zOrderCounter }

    // MARK: Active tool
    var activeTool: AnnotationTool = .none {
        didSet {
            window?.invalidateCursorRects(for: self)
            if activeTool != .arrow { selectedArrowID = nil }
            if activeTool != .text  { finalizeEditing(); selectedTextID = nil }
            if activeTool != .shape { finalizeShape(); selectedShapeID = nil }
            if activeTool != .blur  { selectedBlurID = nil }
            needsDisplay = true
        }
    }

    // Legacy shim for arrow-only callers.
    var isToolActive: Bool {
        get { activeTool == .arrow }
        set { activeTool = newValue ? .arrow : .none }
    }

    // Callbacks
    var imageDisplayRectProvider: (() -> CGRect)?
    var onCopy:   (() -> Void)?
    var onChange: (() -> Void)?
    var onTextSelectionChanged: ((TextAnnotation?) -> Void)?
    // Called when a click in .none mode hits an annotation — activates the
    // matching tool and selects the item so the sidebar shows its properties.
    var onActivateTool: ((AnnotationTool) -> Void)?
    // Provides the current source image for live blur preview.
    var imageProvider: (() -> NSImage?)?

    // MARK: Private state
    private var selectedArrowID: UUID?
    private var selectedTextID:  UUID? {
        didSet {
            let ann = selectedTextID.flatMap { id in textAnnotations.first { $0.id == id } }
            onTextSelectionChanged?(ann)
        }
    }
    private var selectedShapeID: UUID?
    private var selectedBlurID:  UUID?

    private enum DragState {
        case none
        case newArrow(start: CGPoint, current: CGPoint)
        case movingArrowWhole(index: Int, lastLoc: CGPoint)
        case movingArrowTail(index: Int)
        case movingText(index: Int, lastLoc: CGPoint)
        case newShape(start: CGPoint, current: CGPoint)
        case movingShapeWhole(index: Int, lastLoc: CGPoint)
        case resizingShape(index: Int, start: CGPoint, originalRect: CGRect)
        case newBlur(start: CGPoint, current: CGPoint)
        case movingBlurWhole(index: Int, lastLoc: CGPoint)
        case resizingBlur(index: Int, start: CGPoint, originalRect: CGRect)
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
        // Build a unified draw list sorted by zOrder so layering is respected.
        struct DrawItem { let zOrder: Int; let draw: () -> Void }
        var items: [DrawItem] = []

        for arrow in arrows {
            let a = arrow
            items.append(DrawItem(zOrder: a.zOrder) {
                self.renderArrow(from: self.toView(a.start), to: self.toView(a.end),
                                 weight: a.weight, color: a.color)
                if self.selectedArrowID == a.id {
                    self.drawArrowTailHandle(at: self.toView(a.start))
                }
            })
        }
        for ann in textAnnotations {
            let a = ann
            guard a.id != editingID else { continue }
            items.append(DrawItem(zOrder: a.zOrder) {
                self.drawTextAnnotation(a, selected: self.selectedTextID == a.id)
            })
        }
        for shape in shapes {
            let s = shape
            items.append(DrawItem(zOrder: s.zOrder) {
                self.drawShape(s, selected: self.selectedShapeID == s.id)
                if self.selectedShapeID == s.id {
                    self.drawShapeResizeHandle(at: self.toView(s.rect.origin))
                    let brPoint = self.toView(CGPoint(x: s.rect.origin.x + s.rect.width,
                                                     y: s.rect.origin.y))
                    self.drawShapeResizeHandleBottomRight(at: brPoint)
                }
            })
        }
        for region in blurRegions {
            let r = region
            items.append(DrawItem(zOrder: r.zOrder) {
                self.drawBlurRegion(r, selected: self.selectedBlurID == r.id)
            })
        }

        items.sorted { $0.zOrder < $1.zOrder }.forEach { $0.draw() }

        // In-progress new annotations drawn on top of everything.
        if case .newArrow(let s, let c) = dragState {
            renderArrow(from: s, to: c, weight: currentWeight, color: currentColor)
        }
        if case .newShape(let s, let c) = dragState {
            var rect = CGRect(origin: s, size: CGSize(width: c.x - s.x, height: c.y - s.y))
            rect = rect.standardized
            drawShapeRect(rect, shapeType: currentShapeType,
                         borderWeight: currentBorderWeight, borderColor: currentBorderColor,
                         fillColor: currentFillColor, selected: false)
        }
        if case .newBlur(let s, let c) = dragState {
            var rect = CGRect(origin: s, size: CGSize(width: c.x - s.x, height: c.y - s.y))
            rect = rect.standardized
            drawBlurRegionBorder(rect, selected: false)
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

    private func drawShape(_ shape: Shape, selected: Bool) {
        let viewRect = toView(shape.rect.origin)
        let viewSize = CGSize(width: shape.rect.width * imageDisplayRect.width,
                             height: shape.rect.height * imageDisplayRect.height)
        var viewRectFinal = CGRect(origin: viewRect, size: viewSize)
        viewRectFinal = viewRectFinal.standardized
        drawShapeRect(viewRectFinal, shapeType: shape.shapeType,
                     borderWeight: shape.borderWeight, borderColor: shape.borderColor,
                     fillColor: shape.fillColor, selected: selected)
    }

    private func drawShapeRect(_ rect: CGRect, shapeType: ShapeType,
                               borderWeight: CGFloat, borderColor: NSColor,
                               fillColor: NSColor, selected: Bool) {
        let path = NSBezierPath()
        let r = rect.standardized

        switch shapeType {
        case .circle:
            path.appendOval(in: r)
        case .rectangle:
            path.appendRect(r)
        case .roundedRectangle:
            path.appendRoundedRect(r, xRadius: 10, yRadius: 10)
        }

        // Fill
        if fillColor.alphaComponent > 0 {
            fillColor.setFill()
            path.fill()
        }

        // Stroke
        borderColor.setStroke()
        path.lineWidth = borderWeight
        path.stroke()

        // Selection outline
        if selected {
            let selRect = CGRect(x: r.origin.x - 4, y: r.origin.y - 4,
                                width: r.width + 8, height: r.height + 8)
            let selPath = NSBezierPath(rect: selRect)
            selPath.lineWidth = 1.5
            NSColor.selectedControlColor.withAlphaComponent(0.9).setStroke()
            selPath.setLineDash([5, 3], count: 2, phase: 0)
            selPath.stroke()
        }
    }

    private func drawShapeResizeHandle(at point: CGPoint) {
        let r: CGFloat = 7
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r*2, height: r*2)
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill(); circle.fill()
        NSColor.systemBlue.setStroke(); circle.lineWidth = 2; circle.stroke()
    }

    private func drawShapeResizeHandleBottomRight(at point: CGPoint) {
        let r: CGFloat = 7
        let rect = CGRect(x: point.x - r, y: point.y - r, width: r*2, height: r*2)
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.white.setFill(); circle.fill()
        NSColor.systemBlue.setStroke(); circle.lineWidth = 2; circle.stroke()
    }

    private func drawBlurRegion(_ region: BlurRegion, selected: Bool) {
        let viewOrigin = toView(region.rect.origin)
        let viewSize = CGSize(width: region.rect.width * imageDisplayRect.width,
                              height: region.rect.height * imageDisplayRect.height)
        let viewRect = CGRect(origin: viewOrigin, size: viewSize).standardized

        if let image = imageProvider?(),
           let baseCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {

            // Use actual CGImage pixel dimensions — may differ from image.size (points)
            // on Retina displays where the CGImage is 2x.
            let cgW = CGFloat(baseCG.width)
            let cgH = CGFloat(baseCG.height)

            // Pixel rect in CGImage space (y=0 at bottom).
            let pixelRect = CGRect(
                x: region.rect.origin.x * cgW,
                y: region.rect.origin.y * cgH,
                width:  region.rect.width  * cgW,
                height: region.rect.height * cgH
            ).standardized

            if pixelRect.width > 1, pixelRect.height > 1,
               let offCtx = CGContext(
                   data: nil,
                   width: Int(cgW), height: Int(cgH),
                   bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {

                offCtx.draw(baseCG, in: CGRect(x: 0, y: 0, width: cgW, height: cgH))

                let ciImage = CIImage(cgImage: baseCG)
                let ciCtx   = CIContext(cgContext: offCtx, options: nil)
                if let filtered = blurFilter(ciImage: ciImage, pixelRect: pixelRect,
                                             style: region.style,
                                             intensity: region.intensity,
                                             imageSize: CGSize(width: cgW, height: cgH)) {
                    ciCtx.draw(filtered, in: pixelRect, from: pixelRect)
                }

                if let resultCG = offCtx.makeImage() {
                    // NSImage backed by CGImage uses y=0 at bottom for `from:`,
                    // matching CGImage/CI pixel space — no flip needed.
                    let resultNS = NSImage(cgImage: resultCG,
                                          size: NSSize(width: cgW, height: cgH))
                    resultNS.draw(in: viewRect, from: pixelRect,
                                  operation: .sourceOver, fraction: 1.0)

                    drawBlurRegionBorder(viewRect, selected: selected)
                    if selected {
                        let br = CGPoint(x: viewRect.maxX, y: viewRect.minY)
                        drawShapeResizeHandleBottomRight(at: br)
                    }
                    return
                }
            }
        }

        drawBlurRegionBorder(viewRect, selected: selected)
        if selected {
            let br = CGPoint(x: viewRect.maxX, y: viewRect.minY)
            drawShapeResizeHandleBottomRight(at: br)
        }
    }

    private func drawBlurRegionBorder(_ rect: CGRect, selected: Bool) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = selected ? 2 : 1.5
        if selected {
            NSColor.selectedControlColor.setStroke()
        } else {
            NSColor.white.withAlphaComponent(0.6).setStroke()
        }
        path.setLineDash([6, 3], count: 2, phase: 0)
        path.stroke()
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        switch activeTool {
        case .arrow: cursor = .crosshair
        case .text:  cursor = .iBeam
        case .shape: cursor = .crosshair
        case .blur:  cursor = .crosshair
        case .none:  cursor = .arrow
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Mouse

    // Returns the tool type and index if the point hits any annotation,
    // regardless of which tool is currently active.
    private func hitTestAny(at loc: CGPoint) -> (AnnotationTool, Int)? {
        if let idx = tailIndex(near: loc) ?? arrowBodyIndex(near: loc) { return (.arrow, idx) }
        if let idx = textIndex(near: loc)  { return (.text,  idx) }
        if let idx = shapeIndex(near: loc) { return (.shape, idx) }
        if let idx = blurIndex(near: loc)  { return (.blur,  idx) }
        return nil
    }

    // Selects the annotation at (tool, idx) and fires onActivateTool if the
    // tool differs from the current one.
    private func selectAnnotation(tool: AnnotationTool, index idx: Int) {
        switch tool {
        case .arrow: selectedArrowID = arrows[idx].id
        case .text:  selectedTextID  = textAnnotations[idx].id
        case .shape: selectedShapeID = shapes[idx].id
        case .blur:  selectedBlurID  = blurRegions[idx].id
        case .none:  break
        }
        if tool != activeTool {
            onActivateTool?(tool)
        }
        needsDisplay = true
    }

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
            } else if let (tool, idx) = hitTestAny(at: loc) {
                // Clicked a different annotation type — switch to it.
                selectAnnotation(tool: tool, index: idx)
            } else {
                // Empty space — start a new arrow.
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
                    dragState = .movingText(index: idx, lastLoc: loc)
                }
            } else if let (tool, idx) = hitTestAny(at: loc), tool != .text {
                // Clicked a different annotation type — switch to it.
                selectAnnotation(tool: tool, index: idx)
            } else if !wasEditing {
                // Empty space — create a new text annotation.
                var ann = TextAnnotation(
                    position: toNorm(loc), content: "",
                    fontName: currentFontName,
                    fontSize: currentFontSize,
                    fontColor: currentFontColor,
                    outlineColor: currentOutlineColor,
                    outlineWeight: currentOutlineWeight
                )
                ann.zOrder = nextZOrder()
                textAnnotations.append(ann)
                selectedTextID = ann.id
                needsDisplay = true
                beginEditing(index: textAnnotations.count - 1)
            } else {
                selectedTextID = nil
                needsDisplay = true
            }

        case .shape:
            // Check resize handle of selected shape first.
            if let selID = selectedShapeID,
               let selIdx = shapes.firstIndex(where: { $0.id == selID }) {
                let shape = shapes[selIdx]
                let brPoint = toView(CGPoint(x: shape.rect.origin.x + shape.rect.width,
                                            y: shape.rect.origin.y))
                let handleRect = CGRect(x: brPoint.x - 7, y: brPoint.y - 7, width: 14, height: 14)
                if handleRect.contains(loc) {
                    dragState = .resizingShape(index: selIdx, start: loc, originalRect: shape.rect)
                    needsDisplay = true
                    break
                }
            }
            if let idx = shapeIndex(near: loc) {
                selectedShapeID = shapes[idx].id
                dragState = .movingShapeWhole(index: idx, lastLoc: loc)
                needsDisplay = true
            } else if let (tool, idx) = hitTestAny(at: loc), tool != .shape {
                // Clicked a different annotation type — switch to it.
                selectAnnotation(tool: tool, index: idx)
            } else {
                // Empty space — start a new shape.
                dragState = .newShape(start: loc, current: loc)
                selectedShapeID = nil
                needsDisplay = true
            }

        case .blur:
            // Check resize handle of selected blur region first.
            if let selID = selectedBlurID,
               let selIdx = blurRegions.firstIndex(where: { $0.id == selID }) {
                let region = blurRegions[selIdx]
                let viewOrigin = toView(region.rect.origin)
                let viewSize = CGSize(width: region.rect.width * imageDisplayRect.width,
                                     height: region.rect.height * imageDisplayRect.height)
                let viewRect = CGRect(origin: viewOrigin, size: viewSize).standardized
                let br = CGPoint(x: viewRect.maxX, y: viewRect.minY)
                let handleRect = CGRect(x: br.x - 7, y: br.y - 7, width: 14, height: 14)
                if handleRect.contains(loc) {
                    dragState = .resizingBlur(index: selIdx, start: loc, originalRect: region.rect)
                    needsDisplay = true
                    break
                }
            }
            if let idx = blurIndex(near: loc) {
                selectedBlurID = blurRegions[idx].id
                dragState = .movingBlurWhole(index: idx, lastLoc: loc)
                needsDisplay = true
            } else if let (tool, idx) = hitTestAny(at: loc), tool != .blur {
                selectAnnotation(tool: tool, index: idx)
            } else {
                dragState = .newBlur(start: loc, current: loc)
                selectedBlurID = nil
                needsDisplay = true
            }

        case .none:
            // No tool active — clicking any annotation activates its tool.
            if let (tool, idx) = hitTestAny(at: loc) {
                selectAnnotation(tool: tool, index: idx)
            }
            needsDisplay = true
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
        case .movingShapeWhole(let idx, let last):
            let r = imageDisplayRect; guard r.width > 0, r.height > 0 else { break }
            let d = CGPoint(x: (loc.x - last.x) / r.width, y: (loc.y - last.y) / r.height)
            shapes[idx].rect.origin.x += d.x
            shapes[idx].rect.origin.y += d.y
            dragState = .movingShapeWhole(index: idx, lastLoc: loc); needsDisplay = true
        case .newShape(let s, _):
            dragState = .newShape(start: s, current: loc); needsDisplay = true
        case .resizingShape(let idx, _, let origRect):
            let r = imageDisplayRect; guard r.width > 0, r.height > 0 else { break }
            let origBR = toView(CGPoint(x: origRect.origin.x + origRect.width,
                                       y: origRect.origin.y))
            let dx = (loc.x - origBR.x) / r.width
            let dy = (loc.y - origBR.y) / r.height
            var newRect = origRect
            newRect.size.width += dx
            newRect.size.height += dy
            // Clamp to minimum size
            if newRect.size.width < 0.02 { newRect.size.width = 0.02 }
            if newRect.size.height < 0.02 { newRect.size.height = 0.02 }
            shapes[idx].rect = newRect
            needsDisplay = true
        case .movingBlurWhole(let idx, let last):
            let r = imageDisplayRect; guard r.width > 0, r.height > 0 else { break }
            let d = CGPoint(x: (loc.x - last.x) / r.width, y: (loc.y - last.y) / r.height)
            blurRegions[idx].rect.origin.x += d.x
            blurRegions[idx].rect.origin.y += d.y
            dragState = .movingBlurWhole(index: idx, lastLoc: loc); needsDisplay = true
        case .newBlur(let s, _):
            dragState = .newBlur(start: s, current: loc); needsDisplay = true
        case .resizingBlur(let idx, _, let origRect):
            let r = imageDisplayRect; guard r.width > 0, r.height > 0 else { break }
            let origViewRect = CGRect(
                origin: toView(origRect.origin),
                size: CGSize(width: origRect.width * r.width, height: origRect.height * r.height)
            ).standardized
            let origBR = CGPoint(x: origViewRect.maxX, y: origViewRect.minY)
            let dx = (loc.x - origBR.x) / r.width
            let dy = (loc.y - origBR.y) / r.height
            var newRect = origRect
            newRect.size.width  = max(0.02, origRect.width  + dx)
            newRect.size.height = max(0.02, origRect.height - dy)
            blurRegions[idx].rect = newRect
            needsDisplay = true
        case .none: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        switch dragState {
        case .newArrow(let s, let c):
            if hypot(c.x - s.x, c.y - s.y) > 8 {
                var a = Arrow(start: toNorm(s), end: toNorm(c),
                              weight: currentWeight, color: currentColor)
                a.zOrder = nextZOrder()
                arrows.append(a); selectedArrowID = a.id; onChange?()
            } else {
                selectedArrowID = nil
            }
        case .newShape(let s, let c):
            let size = CGSize(width: c.x - s.x, height: c.y - s.y)
            if abs(size.width) > 8 || abs(size.height) > 8 {
                var rect = CGRect(origin: s, size: size)
                rect = rect.standardized
                let normOrigin = toNorm(rect.origin)
                let normRect = CGRect(x: normOrigin.x,
                                     y: normOrigin.y,
                                     width: rect.size.width / imageDisplayRect.width,
                                     height: rect.size.height / imageDisplayRect.height)
                var shape = Shape(rect: normRect, shapeType: currentShapeType,
                                 borderWeight: currentBorderWeight,
                                 borderColor: currentBorderColor,
                                 fillColor: currentFillColor)
                shape.zOrder = nextZOrder()
                shapes.append(shape); selectedShapeID = shape.id; onChange?()
            } else {
                selectedShapeID = nil
            }
        case .newBlur(let s, let c):
            let size = CGSize(width: c.x - s.x, height: c.y - s.y)
            if abs(size.width) > 8 || abs(size.height) > 8 {
                var rect = CGRect(origin: s, size: size)
                rect = rect.standardized
                let normOrigin = toNorm(rect.origin)
                let normRect = CGRect(x: normOrigin.x,
                                     y: normOrigin.y,
                                     width: rect.size.width / imageDisplayRect.width,
                                     height: rect.size.height / imageDisplayRect.height)
                var region = BlurRegion(rect: normRect,
                                        intensity: currentBlurIntensity,
                                        style: currentBlurStyle)
                region.zOrder = nextZOrder()
                blurRegions.append(region); selectedBlurID = region.id; onChange?()
            } else {
                selectedBlurID = nil
            }
        case .movingArrowTail, .movingArrowWhole, .movingText, .movingShapeWhole, .resizingShape,
             .movingBlurWhole, .resizingBlur:
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

    private func finalizeShape() {
        selectedShapeID = nil
    }

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
        } else if activeTool == .shape, let id = selectedShapeID {
            shapes.removeAll { $0.id == id }
            selectedShapeID = nil
            needsDisplay = true; onChange?()
        } else if activeTool == .blur, let id = selectedBlurID {
            blurRegions.removeAll { $0.id == id }
            selectedBlurID = nil
            needsDisplay = true; onChange?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()

        // Determine what was right-clicked.
        enum HitItem {
            case arrow(UUID)
            case text(UUID)
            case shape(UUID)
            case blur(UUID)
        }
        var hit: HitItem?
        if let idx = tailIndex(near: loc) ?? arrowBodyIndex(near: loc) {
            hit = .arrow(arrows[idx].id)
        } else if let idx = textIndex(near: loc) {
            hit = .text(textAnnotations[idx].id)
        } else if let idx = shapeIndex(near: loc) {
            hit = .shape(shapes[idx].id)
        } else if let idx = blurIndex(near: loc) {
            hit = .blur(blurRegions[idx].id)
        }

        if let hit {
            let id: UUID
            let deleteTitle: String
            switch hit {
            case .arrow(let u):  id = u; deleteTitle = "Delete Arrow"
            case .text(let u):   id = u; deleteTitle = "Delete Text"
            case .shape(let u):  id = u; deleteTitle = "Delete Shape"
            case .blur(let u):   id = u; deleteTitle = "Delete Blur"
            }

            // Layering submenu
            let layerMenu = NSMenu(title: "Arrange")
            func layerItem(_ title: String, _ sel: Selector) -> NSMenuItem {
                let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                item.target = self; item.representedObject = id; return item
            }
            layerMenu.addItem(layerItem("Bring to Front",  #selector(menuBringToFront(_:))))
            layerMenu.addItem(layerItem("Bring Forward",   #selector(menuBringForward(_:))))
            layerMenu.addItem(layerItem("Send Backward",   #selector(menuSendBackward(_:))))
            layerMenu.addItem(layerItem("Send to Back",    #selector(menuSendToBack(_:))))

            let arrangeItem = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: "")
            arrangeItem.submenu = layerMenu
            menu.addItem(arrangeItem)
            menu.addItem(.separator())

            let del = menu.addItem(withTitle: deleteTitle, action: #selector(menuDeleteAny(_:)), keyEquivalent: "")
            del.target = self; del.representedObject = id
            menu.addItem(.separator())
        }

        let copy = menu.addItem(withTitle: "Copy Image", action: #selector(menuCopy(_:)), keyEquivalent: "")
        copy.target = self
        return menu
    }

    // MARK: Layering helpers

    // Returns the current zOrder for any annotation ID.
    private func zOrder(for id: UUID) -> Int? {
        if let a = arrows.first(where: { $0.id == id })            { return a.zOrder }
        if let t = textAnnotations.first(where: { $0.id == id })   { return t.zOrder }
        if let s = shapes.first(where: { $0.id == id })            { return s.zOrder }
        if let b = blurRegions.first(where: { $0.id == id })       { return b.zOrder }
        return nil
    }

    private func setZOrder(_ z: Int, for id: UUID) {
        if let i = arrows.firstIndex(where: { $0.id == id })          { arrows[i].zOrder = z }
        if let i = textAnnotations.firstIndex(where: { $0.id == id }) { textAnnotations[i].zOrder = z }
        if let i = shapes.firstIndex(where: { $0.id == id })          { shapes[i].zOrder = z }
        if let i = blurRegions.firstIndex(where: { $0.id == id })     { blurRegions[i].zOrder = z }
    }

    private func allZOrders() -> [(id: UUID, z: Int)] {
        var all: [(UUID, Int)] = []
        arrows.forEach          { all.append(($0.id, $0.zOrder)) }
        textAnnotations.forEach { all.append(($0.id, $0.zOrder)) }
        shapes.forEach          { all.append(($0.id, $0.zOrder)) }
        blurRegions.forEach     { all.append(($0.id, $0.zOrder)) }
        return all.sorted { $0.1 < $1.1 }
    }

    // Renormalises all z-orders to 1…n to keep them tidy after reordering.
    private func compactZOrders() {
        let sorted = allZOrders()
        for (rank, item) in sorted.enumerated() {
            setZOrder(rank + 1, for: item.id)
        }
        zOrderCounter = sorted.count
    }

    @objc private func menuBringToFront(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        compactZOrders()
        setZOrder(zOrderCounter + 1, for: id)
        compactZOrders()
        needsDisplay = true; onChange?()
    }

    @objc private func menuSendToBack(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        compactZOrders()
        setZOrder(0, for: id)
        compactZOrders()
        needsDisplay = true; onChange?()
    }

    @objc private func menuBringForward(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              let currentZ = zOrder(for: id) else { return }
        // Find the next item above and swap z-orders.
        let sorted = allZOrders()
        if let next = sorted.first(where: { $0.z > currentZ }) {
            setZOrder(next.z, for: id)
            setZOrder(currentZ, for: next.id)
        }
        needsDisplay = true; onChange?()
    }

    @objc private func menuSendBackward(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID,
              let currentZ = zOrder(for: id) else { return }
        // Find the next item below and swap z-orders.
        let sorted = allZOrders()
        if let prev = sorted.last(where: { $0.z < currentZ }) {
            setZOrder(prev.z, for: id)
            setZOrder(currentZ, for: prev.id)
        }
        needsDisplay = true; onChange?()
    }

    @objc private func menuDeleteAny(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        arrows.removeAll          { $0.id == id }
        textAnnotations.removeAll { $0.id == id }
        shapes.removeAll          { $0.id == id }
        blurRegions.removeAll     { $0.id == id }
        if selectedArrowID == id { selectedArrowID = nil }
        if selectedTextID  == id { selectedTextID  = nil }
        if selectedShapeID == id { selectedShapeID = nil }
        if selectedBlurID  == id { selectedBlurID  = nil }
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

    // MARK: - Update selected shape

    func updateSelectedShape(shapeType: ShapeType? = nil,
                             borderWeight: CGFloat? = nil,
                             borderColor: NSColor? = nil,
                             fillColor: NSColor? = nil) {
        guard let id = selectedShapeID,
              let idx = shapes.firstIndex(where: { $0.id == id }) else { return }
        if let v = shapeType     { shapes[idx].shapeType     = v }
        if let v = borderWeight  { shapes[idx].borderWeight  = v }
        if let v = borderColor   { shapes[idx].borderColor   = v }
        if let v = fillColor     { shapes[idx].fillColor     = v }
        needsDisplay = true
    }

    // MARK: - Update selected blur

    func updateSelectedBlur(intensity: CGFloat? = nil, style: BlurStyle? = nil) {
        guard let id = selectedBlurID,
              let idx = blurRegions.firstIndex(where: { $0.id == id }) else { return }
        if let v = intensity { blurRegions[idx].intensity = v }
        if let v = style     { blurRegions[idx].style     = v }
        needsDisplay = true; onChange?()
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
        // Return the topmost (highest zOrder) matching arrow.
        arrows.indices
            .filter { hypot(point.x - toView(arrows[$0].start).x,
                            point.y - toView(arrows[$0].start).y) < 12 }
            .max(by: { arrows[$0].zOrder < arrows[$1].zOrder })
    }

    private func arrowBodyIndex(near point: CGPoint) -> Int? {
        arrows.indices
            .filter { distToSeg(point, toView(arrows[$0].start), toView(arrows[$0].end))
                        < max(arrows[$0].weight / 2 + 8, 12.0) }
            .max(by: { arrows[$0].zOrder < arrows[$1].zOrder })
    }

    private func textIndex(near point: CGPoint) -> Int? {
        textAnnotations.indices
            .filter { i in
                let ann = textAnnotations[i]
                guard ann.id != editingID else { return false }
                let pt   = toView(ann.position)
                let font = NSFont(name: ann.fontName, size: ann.fontSize)
                    ?? NSFont.boldSystemFont(ofSize: ann.fontSize)
                let sz: CGSize = ann.content.isEmpty
                    ? CGSize(width: max(80, ann.fontSize * 4), height: ann.fontSize * 1.4)
                    : NSAttributedString(string: ann.content, attributes: [.font: font]).size()
                let rect = CGRect(x: pt.x - 6, y: pt.y - abs(font.descender) - 4,
                                  width: sz.width + 12, height: sz.height + 8)
                return rect.contains(point)
            }
            .max(by: { textAnnotations[$0].zOrder < textAnnotations[$1].zOrder })
    }

    private func shapeIndex(near point: CGPoint) -> Int? {
        shapes.indices
            .filter { i in
                let shape = shapes[i]
                let viewRect = toView(shape.rect.origin)
                let viewSize = CGSize(width: shape.rect.width * imageDisplayRect.width,
                                     height: shape.rect.height * imageDisplayRect.height)
                return CGRect(origin: viewRect, size: viewSize).contains(point)
            }
            .max(by: { shapes[$0].zOrder < shapes[$1].zOrder })
    }

    private func blurIndex(near point: CGPoint) -> Int? {
        blurRegions.indices
            .filter { i in
                let region = blurRegions[i]
                let viewOrigin = toView(region.rect.origin)
                let viewSize = CGSize(width: region.rect.width * imageDisplayRect.width,
                                     height: region.rect.height * imageDisplayRect.height)
                return CGRect(origin: viewOrigin, size: viewSize).standardized.contains(point)
            }
            .max(by: { blurRegions[$0].zOrder < blurRegions[$1].zOrder })
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

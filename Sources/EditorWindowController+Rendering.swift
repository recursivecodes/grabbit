import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Shared blur filter (used by both export rendering and live overlay preview)

func blurFilter(ciImage: CIImage, pixelRect: CGRect,
                style: BlurStyle, intensity: CGFloat,
                imageSize: CGSize) -> CIImage? {
    let t = max(0.01, intensity / 100.0)

    switch style {
    case .blur:
        let shortSide = min(pixelRect.width, pixelRect.height)
        let radius = t * shortSide * 0.45
        guard let clampFilter = CIFilter(name: "CIAffineClamp") else { return nil }
        clampFilter.setValue(ciImage, forKey: kCIInputImageKey)
        clampFilter.setValue(CGAffineTransform.identity, forKey: "inputTransform")
        guard let clamped = clampFilter.outputImage else { return nil }
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(clamped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius,  forKey: kCIInputRadiusKey)
        return blurFilter.outputImage?.cropped(to: pixelRect)

    case .pixelate:
        let shortSide = min(pixelRect.width, pixelRect.height)
        let pixelSize = max(1.0, t * shortSide * 0.1)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage.cropped(to: pixelRect), forKey: kCIInputImageKey)
        filter.setValue(pixelSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(cgPoint: CGPoint(x: pixelRect.minX, y: pixelRect.minY)),
                        forKey: kCIInputCenterKey)
        return filter.outputImage?.cropped(to: pixelRect)
    }
}

// MARK: - CGContext drawing helper
//
// All rendering uses CGContext directly so output pixel dimensions are exactly
// NSImage.size (which we keep == pixel dimensions throughout the pipeline).
// lockFocus() must NOT be used for export rendering because on a Retina display
// it creates a 2× backing store, doubling the output pixel count.

private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

/// Draws `base` into a new CGContext of the same pixel size, then calls `draw`
/// with an NSGraphicsContext wrapping that CGContext so AppKit drawing APIs
/// (NSBezierPath, NSAttributedString, etc.) work at 1 pt = 1 px.
/// Returns an NSImage whose size == pixel dimensions.
private func drawOverBase(_ base: NSImage, draw: (CGSize) -> Void) -> NSImage {
    let w = Int(base.size.width), h = Int(base.size.height)
    guard w > 0, h > 0,
          let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = makeBitmapContext(width: w, height: h)
    else { return base }

    // Draw the base image.
    ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Push an NSGraphicsContext so AppKit drawing APIs work in this CGContext.
    // scaleFactor:1 means 1 pt == 1 px — no Retina doubling.
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    draw(CGSize(width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()

    guard let result = ctx.makeImage() else { return base }
    return NSImage(cgImage: result, size: base.size)
}

// MARK: - GrabbitDocument rendering

extension GrabbitDocument {

    // MARK: - Full render pipeline

    /// Renders the document to a flat NSImage suitable for export or clipboard.
    /// `displayWidth` is the width of the image as shown in the editor (points),
    /// used to compute the pixel-to-display scale for stroke weights.
    func rendered(displayWidth: CGFloat = 0) -> NSImage {
        var img = (borderEnabled && borderWeight > 0) ? withBorder(currentImage) : currentImage
        img = withBlurRegions(img)
        img = withHighlights(img)
        img = withSpotlights(img)
        img = withArrows(img, displayWidth: displayWidth)
        img = withTexts(img, displayWidth: displayWidth)
        img = withShapes(img, displayWidth: displayWidth)
        if shadowEnabled && shadowOpacity > 0 { img = withShadow(img) }
        return img
    }

    func withBorder(_ base: NSImage) -> NSImage {
        let bw = borderWeight
        let outW = Int(base.size.width  + bw * 2)
        let outH = Int(base.size.height + bw * 2)
        guard outW > 0, outH > 0,
              let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = makeBitmapContext(width: outW, height: outH)
        else { return base }

        // Fill border color.
        if let cgColor = borderColor.cgColor as CGColor? {
            ctx.setFillColor(cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
        }
        // Draw base image inset by border width.
        ctx.draw(baseCG, in: CGRect(x: bw, y: bw,
                                    width: base.size.width, height: base.size.height))
        guard let result = ctx.makeImage() else { return base }
        return NSImage(cgImage: result,
                       size: NSSize(width: outW, height: outH))
    }

    private func withArrows(_ base: NSImage, displayWidth: CGFloat) -> NSImage {
        guard !arrows.isEmpty else { return base }
        return drawOverBase(base) { size in
            let scale = displayWidth > 0 ? size.width / displayWidth : 1
            for arrow in arrows {
                let s = CGPoint(x: arrow.start.x * size.width,  y: arrow.start.y * size.height)
                let e = CGPoint(x: arrow.end.x   * size.width,  y: arrow.end.y   * size.height)
                renderArrowIntoContext(from: s, to: e,
                                       weight: arrow.weight * scale, color: arrow.color)
            }
        }
    }

    private func withTexts(_ base: NSImage, displayWidth: CGFloat) -> NSImage {
        let texts = textAnnotations.filter { !$0.content.isEmpty }
        guard !texts.isEmpty else { return base }
        return drawOverBase(base) { size in
            let scale = displayWidth > 0 ? size.width / displayWidth : 1
            for ann in texts {
                let pt   = CGPoint(x: ann.position.x * size.width,
                                   y: ann.position.y * size.height)
                let font = NSFont.boldSystemFont(ofSize: ann.fontSize * scale)
                if ann.outlineWeight > 0 {
                    makeTextAttrStr(ann.content, font: font,
                                    fontColor: .clear, outlineColor: ann.outlineColor,
                                    outlineWeight: ann.outlineWeight * scale, strokeOnly: true)
                        .draw(at: pt)
                }
                makeTextAttrStr(ann.content, font: font,
                                fontColor: ann.fontColor, outlineColor: ann.outlineColor,
                                outlineWeight: ann.outlineWeight * scale, strokeOnly: false)
                    .draw(at: pt)
            }
        }
    }

    private func withShapes(_ base: NSImage, displayWidth: CGFloat) -> NSImage {
        guard !shapes.isEmpty else { return base }
        return drawOverBase(base) { size in
            let scale = displayWidth > 0 ? size.width / displayWidth : 1
            for shape in shapes {
                let origin = CGPoint(x: shape.rect.origin.x * size.width,
                                     y: shape.rect.origin.y * size.height)
                let sz     = CGSize(width:  shape.rect.size.width  * size.width,
                                    height: shape.rect.size.height * size.height)
                let rect   = CGRect(origin: origin, size: sz).standardized
                let path   = NSBezierPath()
                switch shape.shapeType {
                case .circle:           path.appendOval(in: rect)
                case .rectangle:        path.appendRect(rect)
                case .roundedRectangle: path.appendRoundedRect(rect,
                                            xRadius: 10 * scale, yRadius: 10 * scale)
                }
                if shape.fillColor.alphaComponent > 0 {
                    shape.fillColor.setFill(); path.fill()
                }
                shape.borderColor.setStroke()
                path.lineWidth = shape.borderWeight * scale
                path.stroke()
            }
        }
    }

    func withShadow(_ base: NSImage) -> NSImage {
        let blur = shadowBlur
        let pad  = blur * 2 + max(abs(shadowOffsetX), abs(shadowOffsetY)) + 8
        let outW = Int(base.size.width  + pad * 2)
        let outH = Int(base.size.height + pad * 2)
        guard outW > 0, outH > 0,
              let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = makeBitmapContext(width: outW, height: outH)
        else { return base }

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let sh = NSShadow()
        sh.shadowBlurRadius = blur
        sh.shadowOffset     = NSSize(width: shadowOffsetX, height: shadowOffsetY)
        sh.shadowColor      = shadowColor.withAlphaComponent(shadowOpacity)
        sh.set()

        // Draw base image into the padded canvas.
        let baseImg = NSImage(cgImage: baseCG, size: base.size)
        baseImg.draw(in: NSRect(x: pad, y: pad,
                                width: base.size.width, height: base.size.height))

        NSGraphicsContext.restoreGraphicsState()
        guard let result = ctx.makeImage() else { return base }
        return NSImage(cgImage: result,
                       size: NSSize(width: outW, height: outH))
    }

    // MARK: - Blur regions

    func withBlurRegions(_ base: NSImage) -> NSImage {
        guard !blurRegions.isEmpty else { return base }
        guard let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return base }
        let w = CGFloat(baseCG.width), h = CGFloat(baseCG.height)
        guard let ctx = makeBitmapContext(width: Int(w), height: Int(h)) else { return base }
        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: w, height: h))
        let ciContext = CIContext(cgContext: ctx, options: nil)
        let ciBase = CIImage(cgImage: baseCG)
        for region in blurRegions.sorted(by: { $0.zOrder < $1.zOrder }) {
            let pixelRect = CGRect(
                x: region.rect.origin.x * w, y: region.rect.origin.y * h,
                width: region.rect.width * w, height: region.rect.height * h
            ).standardized
            guard pixelRect.width > 1, pixelRect.height > 1 else { continue }
            if let filtered = blurFilter(ciImage: ciBase, pixelRect: pixelRect,
                                         style: region.style, intensity: region.intensity,
                                         imageSize: CGSize(width: w, height: h)) {
                ciContext.draw(filtered, in: pixelRect, from: pixelRect)
            }
        }
        guard let resultCG = ctx.makeImage() else { return base }
        return NSImage(cgImage: resultCG, size: base.size)
    }

    // MARK: - Highlights

    func withHighlights(_ base: NSImage) -> NSImage {
        guard !highlights.isEmpty else { return base }
        return drawOverBase(base) { size in
            for h in highlights.sorted(by: { $0.zOrder < $1.zOrder }) {
                let origin = CGPoint(x: h.rect.origin.x * size.width,
                                     y: h.rect.origin.y * size.height)
                let sz     = CGSize(width:  h.rect.size.width  * size.width,
                                    height: h.rect.size.height * size.height)
                let rect   = CGRect(origin: origin, size: sz).standardized
                h.color.withAlphaComponent(min(max(h.opacity, 0.05), 0.85)).setFill()
                NSBezierPath(rect: rect).fill()
            }
        }
    }

    // MARK: - Spotlights

    func withSpotlights(_ base: NSImage) -> NSImage {
        guard !spotlights.isEmpty else { return base }
        return drawOverBase(base) { size in
            for s in self.spotlights.sorted(by: { $0.zOrder < $1.zOrder }) {
                let origin = CGPoint(x: s.rect.origin.x * size.width,
                                     y: s.rect.origin.y * size.height)
                let sz = CGSize(width: s.rect.width * size.width,
                                height: s.rect.height * size.height)
                let spotRect = CGRect(origin: origin, size: sz).standardized
                let outer = NSBezierPath(rect: CGRect(origin: .zero, size: size))
                switch s.shapeType {
                case .rectangle:        outer.appendRect(spotRect)
                case .circle:           outer.appendOval(in: spotRect)
                case .roundedRectangle: outer.appendRoundedRect(spotRect, xRadius: 10, yRadius: 10)
                }
                outer.windingRule = .evenOdd
                s.overlayColor.withAlphaComponent(min(max(s.overlayOpacity, 0.05), 0.95)).setFill()
                outer.fill()
            }
        }
    }

    // MARK: - Arrow drawing helper (used by both rendering and overlay preview)

    func renderArrowIntoContext(from: CGPoint, to: CGPoint, weight: CGFloat, color: NSColor) {
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
}

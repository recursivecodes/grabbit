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
        // Key insight: blur the FULL image (clamped to avoid transparent edges),
        // then crop — this gives clean, fully-opaque edges with no halo artifacts.
        // Radius scales with the region's shorter side so content is always
        // fully obliterated at high intensity regardless of region size.
        // At t=0.01 (intensity=1) the radius is ~0.45% of shortSide — nearly readable.
        // At t=1.0 (intensity=100) the radius is 45% of shortSide — fully obliterated.
        let shortSide = min(pixelRect.width, pixelRect.height)
        let radius = t * shortSide * 0.45

        // CIAffineClamp extends edge pixels infinitely so the blur has real
        // source data at every sample point — no transparent bleed-in.
        guard let clampFilter = CIFilter(name: "CIAffineClamp") else { return nil }
        clampFilter.setValue(ciImage, forKey: kCIInputImageKey)
        clampFilter.setValue(CGAffineTransform.identity, forKey: "inputTransform")
        guard let clamped = clampFilter.outputImage else { return nil }

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(clamped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius,  forKey: kCIInputRadiusKey)
        // Crop to the region after blurring — edges are now clean and opaque.
        return blurFilter.outputImage?.cropped(to: pixelRect)

    case .pixelate:
        // Pixellate the full image then crop — same clamp-free approach works
        // here since CIPixellate doesn't sample outside its input.
        // Block size: at t=1.0 each block is ~1/10 of the shorter dimension.
        let shortSide = min(pixelRect.width, pixelRect.height)
        let pixelSize = max(1.0, t * shortSide * 0.1)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage.cropped(to: pixelRect), forKey: kCIInputImageKey)
        filter.setValue(pixelSize, forKey: kCIInputScaleKey)
        // Align the pixel grid to the region origin so blocks don't look offset.
        filter.setValue(CIVector(cgPoint: CGPoint(x: pixelRect.minX, y: pixelRect.minY)),
                        forKey: kCIInputCenterKey)
        return filter.outputImage?.cropped(to: pixelRect)
    }
}

extension EditorWindowController {

    // MARK: - Rendering

    func rendered() -> NSImage {
        var img = (borderEnabled && borderWeight > 0) ? withBorder(currentImage) : currentImage
        img = withBlurRegions(img)
        img = withHighlights(img)
        img = withArrows(img)
        img = withTexts(img)
        img = withShapes(img)
        if shadowEnabled && shadowOpacity > 0 { img = withShadow(img) }
        return img
    }

    func withBorder(_ base: NSImage) -> NSImage {
        let w = borderWeight
        let out = NSImage(size: NSSize(width: base.size.width + w*2, height: base.size.height + w*2))
        out.lockFocus()
        borderColor.setFill()
        NSRect(origin: .zero, size: out.size).fill()
        base.draw(in: NSRect(x: w, y: w, width: base.size.width, height: base.size.height))
        out.unlockFocus()
        return out
    }

    private func withArrows(_ base: NSImage) -> NSImage {
        guard !annotationOverlay.arrows.isEmpty else { return base }
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        let displayW = annotationOverlay.imageDisplayRect.width
        let scale = displayW > 0 ? base.size.width / displayW : 1
        for arrow in annotationOverlay.arrows {
            let s = CGPoint(x: arrow.start.x * base.size.width,  y: arrow.start.y * base.size.height)
            let e = CGPoint(x: arrow.end.x   * base.size.width,  y: arrow.end.y   * base.size.height)
            annotationOverlay.renderArrow(from: s, to: e,
                                          weight: arrow.weight * scale, color: arrow.color)
        }
        out.unlockFocus()
        return out
    }

    private func withTexts(_ base: NSImage) -> NSImage {
        let texts = annotationOverlay.textAnnotations.filter { !$0.content.isEmpty }
        guard !texts.isEmpty else { return base }
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        let displayW = annotationOverlay.imageDisplayRect.width
        let scale = displayW > 0 ? base.size.width / displayW : 1
        for ann in texts {
            let pt   = CGPoint(x: ann.position.x * base.size.width,
                               y: ann.position.y * base.size.height)
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
        out.unlockFocus()
        return out
    }

    private func withShapes(_ base: NSImage) -> NSImage {
        let shapes = annotationOverlay.shapes
        guard !shapes.isEmpty else { return base }
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        let displayW = annotationOverlay.imageDisplayRect.width
        let scale = displayW > 0 ? base.size.width / displayW : 1
        for shape in shapes {
            let origin = CGPoint(x: shape.rect.origin.x * base.size.width,
                                y: shape.rect.origin.y * base.size.height)
            let size = CGSize(width: shape.rect.size.width * base.size.width,
                             height: shape.rect.size.height * base.size.height)
            var rect = CGRect(origin: origin, size: size)
            rect = rect.standardized
            let path = NSBezierPath()
            switch shape.shapeType {
            case .circle:
                path.appendOval(in: rect)
            case .rectangle:
                path.appendRect(rect)
            case .roundedRectangle:
                path.appendRoundedRect(rect, xRadius: 10 * scale, yRadius: 10 * scale)
            }
            if shape.fillColor.alphaComponent > 0 {
                shape.fillColor.setFill()
                path.fill()
            }
            shape.borderColor.setStroke()
            path.lineWidth = shape.borderWeight * scale
            path.stroke()
        }
        out.unlockFocus()
        return out
    }

    func withShadow(_ base: NSImage) -> NSImage {
        let blur = shadowBlur
        let pad  = blur * 2 + max(abs(shadowOffsetX), abs(shadowOffsetY)) + 8
        let out  = NSImage(size: NSSize(width: base.size.width + pad*2, height: base.size.height + pad*2))
        out.lockFocus()
        let sh = NSShadow()
        sh.shadowBlurRadius = blur
        sh.shadowOffset     = NSSize(width: shadowOffsetX, height: shadowOffsetY)
        sh.shadowColor      = shadowColor.withAlphaComponent(shadowOpacity)
        sh.set()
        base.draw(in: NSRect(x: pad, y: pad, width: base.size.width, height: base.size.height))
        out.unlockFocus()
        return out
    }

    // MARK: - Blur regions

    func withBlurRegions(_ base: NSImage) -> NSImage {
        let regions = annotationOverlay.blurRegions
        guard !regions.isEmpty else { return base }

        guard let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return base }

        // Use actual CGImage pixel dimensions — on Retina these differ from base.size (points).
        let w = CGFloat(baseCG.width), h = CGFloat(baseCG.height)

        guard let ctx = CGContext(
            data: nil,
            width: Int(w), height: Int(h),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        ctx.draw(baseCG, in: CGRect(x: 0, y: 0, width: w, height: h))

        let ciContext = CIContext(cgContext: ctx, options: nil)
        let ciBase = CIImage(cgImage: baseCG)

        for region in regions.sorted(by: { $0.zOrder < $1.zOrder }) {
            let pixelRect = CGRect(
                x: region.rect.origin.x * w,
                y: region.rect.origin.y * h,
                width:  region.rect.width  * w,
                height: region.rect.height * h
            ).standardized
            guard pixelRect.width > 1, pixelRect.height > 1 else { continue }

            let filtered = applyBlurFilter(to: ciBase, in: pixelRect,
                                           style: region.style, intensity: region.intensity,
                                           imageSize: CGSize(width: w, height: h))
            guard let filteredCI = filtered else { continue }
            ciContext.draw(filteredCI, in: pixelRect, from: pixelRect)
        }

        guard let resultCG = ctx.makeImage() else { return base }
        // Return at the original point size so downstream rendering stays consistent.
        return NSImage(cgImage: resultCG, size: base.size)
    }

    /// Shared blur/pixelate filter logic used by both export rendering and live preview.
    func applyBlurFilter(to ciImage: CIImage, in pixelRect: CGRect,
                         style: BlurStyle, intensity: CGFloat,
                         imageSize: CGSize) -> CIImage? {
        return blurFilter(ciImage: ciImage, pixelRect: pixelRect,
                          style: style, intensity: intensity, imageSize: imageSize)
    }

    // MARK: - Highlights

    func withHighlights(_ base: NSImage) -> NSImage {
        let hs = annotationOverlay.highlights
        guard !hs.isEmpty else { return base }
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        for h in hs.sorted(by: { $0.zOrder < $1.zOrder }) {
            let origin = CGPoint(x: h.rect.origin.x * base.size.width,
                                 y: h.rect.origin.y * base.size.height)
            let size   = CGSize(width:  h.rect.size.width  * base.size.width,
                                height: h.rect.size.height * base.size.height)
            let rect   = CGRect(origin: origin, size: size).standardized
            let clampedOpacity = min(max(h.opacity, 0.05), 0.85)
            h.color.withAlphaComponent(clampedOpacity).setFill()
            NSBezierPath(rect: rect).fill()
        }
        out.unlockFocus()
        return out
    }
}

import AppKit

extension EditorWindowController {

    // MARK: - Rendering

    func rendered() -> NSImage {
        var img = (borderEnabled && borderWeight > 0) ? withBorder(currentImage) : currentImage
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
}

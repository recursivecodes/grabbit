import AppKit

// MARK: - Codable wrappers for AppKit / CoreGraphics types

struct CodableColor: Codable {
    let r, g, b, a: Double
    init(_ color: NSColor) {
        // NSColor.usingColorSpace returns nil for dynamic/semantic colors (.systemRed, .black, etc.).
        // Calling getRed on such a color raises an ObjC exception.
        // color.cgColor always resolves dynamic colors using the current appearance, giving a
        // concrete CGColor that can be safely converted to deviceRGB.
        let space = CGColorSpaceCreateDeviceRGB()
        if let cg = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
           let c = cg.components, c.count >= 4 {
            r = Double(c[0]); g = Double(c[1]); b = Double(c[2]); a = Double(c[3])
        } else if let cg = color.cgColor.components, cg.count >= 2 {
            // Grayscale + alpha (e.g. white, black in calibratedWhite space)
            r = Double(cg[0]); g = Double(cg[0]); b = Double(cg[0]); a = Double(cg[cg.count - 1])
        } else {
            r = 0; g = 0; b = 0; a = 1
        }
    }
    var nsColor: NSColor { NSColor(deviceRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}

struct CodablePoint: Codable {
    let x, y: Double
    init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct CodableRect: Codable {
    let x, y, w, h: Double
    init(_ r: CGRect) { x = Double(r.origin.x); y = Double(r.origin.y); w = Double(r.width); h = Double(r.height) }
    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

enum CodableShapeType: String, Codable {
    case circle, rectangle, roundedRectangle
    init(_ t: ShapeType) {
        switch t {
        case .circle:           self = .circle
        case .rectangle:        self = .rectangle
        case .roundedRectangle: self = .roundedRectangle
        }
    }
    var shapeType: ShapeType {
        switch self {
        case .circle:           return .circle
        case .rectangle:        return .rectangle
        case .roundedRectangle: return .roundedRectangle
        }
    }
}

enum CodableBlurStyle: String, Codable {
    case blur, pixelate
    init(_ s: BlurStyle) { self = s == .blur ? .blur : .pixelate }
    var blurStyle: BlurStyle { self == .blur ? .blur : .pixelate }
}

// MARK: - Codable annotation types

struct CodableArrow: Codable {
    let id: UUID; let zOrder: Int
    let start, end: CodablePoint
    let weight: Double; let color: CodableColor
    init(_ a: Arrow) {
        id = a.id; zOrder = a.zOrder
        start = CodablePoint(a.start); end = CodablePoint(a.end)
        weight = Double(a.weight); color = CodableColor(a.color)
    }
    var arrow: Arrow {
        Arrow(id: id, zOrder: zOrder, start: start.cgPoint, end: end.cgPoint,
              weight: CGFloat(weight), color: color.nsColor)
    }
}

struct CodableTextAnnotation: Codable {
    let id: UUID; let zOrder: Int
    let position: CodablePoint; let content: String
    let fontName: String; let fontSize: Double
    let fontColor: CodableColor; let outlineColor: CodableColor; let outlineWeight: Double
    init(_ t: TextAnnotation) {
        id = t.id; zOrder = t.zOrder
        position = CodablePoint(t.position); content = t.content
        fontName = t.fontName; fontSize = Double(t.fontSize)
        fontColor = CodableColor(t.fontColor); outlineColor = CodableColor(t.outlineColor)
        outlineWeight = Double(t.outlineWeight)
    }
    var textAnnotation: TextAnnotation {
        TextAnnotation(id: id, zOrder: zOrder, position: position.cgPoint, content: content,
                       fontName: fontName, fontSize: CGFloat(fontSize),
                       fontColor: fontColor.nsColor, outlineColor: outlineColor.nsColor,
                       outlineWeight: CGFloat(outlineWeight))
    }
}

struct CodableShape: Codable {
    let id: UUID; let zOrder: Int
    let rect: CodableRect; let shapeType: CodableShapeType
    let borderWeight: Double; let borderColor: CodableColor; let fillColor: CodableColor
    init(_ s: Shape) {
        id = s.id; zOrder = s.zOrder
        rect = CodableRect(s.rect); shapeType = CodableShapeType(s.shapeType)
        borderWeight = Double(s.borderWeight)
        borderColor = CodableColor(s.borderColor); fillColor = CodableColor(s.fillColor)
    }
    var shape: Shape {
        Shape(id: id, zOrder: zOrder, rect: rect.cgRect, shapeType: shapeType.shapeType,
              borderWeight: CGFloat(borderWeight), borderColor: borderColor.nsColor,
              fillColor: fillColor.nsColor)
    }
}

struct CodableBlurRegion: Codable {
    let id: UUID; let zOrder: Int
    let rect: CodableRect; let intensity: Double; let style: CodableBlurStyle
    init(_ b: BlurRegion) {
        id = b.id; zOrder = b.zOrder
        rect = CodableRect(b.rect); intensity = Double(b.intensity); style = CodableBlurStyle(b.style)
    }
    var blurRegion: BlurRegion {
        BlurRegion(id: id, zOrder: zOrder, rect: rect.cgRect,
                   intensity: CGFloat(intensity), style: style.blurStyle)
    }
}

struct CodableHighlight: Codable {
    let id: UUID; let zOrder: Int
    let rect: CodableRect; let color: CodableColor; let opacity: Double
    init(_ h: Highlight) {
        id = h.id; zOrder = h.zOrder
        rect = CodableRect(h.rect); color = CodableColor(h.color); opacity = Double(h.opacity)
    }
    var highlight: Highlight {
        Highlight(id: id, zOrder: zOrder, rect: rect.cgRect,
                  color: color.nsColor, opacity: CGFloat(opacity))
    }
}

struct CodableSpotlight: Codable {
    let id: UUID; let zOrder: Int
    let rect: CodableRect
    let overlayColor: CodableColor; let overlayOpacity: Double
    let shapeType: CodableShapeType
    init(_ s: Spotlight) {
        id = s.id; zOrder = s.zOrder
        rect = CodableRect(s.rect)
        overlayColor = CodableColor(s.overlayColor); overlayOpacity = Double(s.overlayOpacity)
        shapeType = CodableShapeType(s.shapeType)
    }
    var spotlight: Spotlight {
        Spotlight(id: id, zOrder: zOrder, rect: rect.cgRect,
                  overlayColor: overlayColor.nsColor, overlayOpacity: CGFloat(overlayOpacity),
                  shapeType: shapeType.shapeType)
    }
}

struct CodableStepBadge: Codable {
    let id: UUID; let zOrder: Int
    let center: CodablePoint; let number: Int; let diameter: Double
    let fillColor: CodableColor; let textColor: CodableColor
    init(_ s: StepBadge) {
        id = s.id; zOrder = s.zOrder
        center = CodablePoint(s.center); number = s.number; diameter = Double(s.diameter)
        fillColor = CodableColor(s.fillColor); textColor = CodableColor(s.textColor)
    }
    var stepBadge: StepBadge {
        StepBadge(id: id, zOrder: zOrder, center: center.cgPoint, number: number,
                  diameter: CGFloat(diameter), fillColor: fillColor.nsColor, textColor: textColor.nsColor)
    }
}

// MARK: - Root document data structure

struct GrabbitDocumentData: Codable {
    var version: Int = 1
    var capturedAt: Date
    // Border
    var borderWeight: Double
    var borderColor: CodableColor
    var borderEnabled: Bool
    // Shadow
    var shadowOffsetX, shadowOffsetY, shadowBlur: Double
    var shadowColor: CodableColor
    var shadowOpacity: Double
    var shadowEnabled: Bool
    // Arrow defaults
    var arrowWeight: Double
    var arrowColor: CodableColor
    // Text defaults
    var textFontName: String
    var textFontSize: Double
    var textFontColor: CodableColor
    var textOutlineColor: CodableColor
    var textOutlineWeight: Double
    // Shape defaults
    var shapeBorderWeight: Double
    var shapeBorderColor: CodableColor
    var shapeFillColor: CodableColor
    // Highlight defaults
    var highlightColor: CodableColor
    var highlightOpacity: Double
    // Spotlight defaults
    var spotlightOverlayColor: CodableColor
    var spotlightOverlayOpacity: Double
    var spotlightShapeType: CodableShapeType
    // Step defaults
    var stepDiameter: Double
    var stepFillColor: CodableColor
    var stepTextColor: CodableColor
    // Annotations
    var arrows: [CodableArrow]
    var textAnnotations: [CodableTextAnnotation]
    var shapes: [CodableShape]
    var blurRegions: [CodableBlurRegion]
    var highlights: [CodableHighlight]
    var spotlights: [CodableSpotlight]
    var stepBadges: [CodableStepBadge]
    var zOrderCounter: Int
}

// MARK: - GrabbitDocument encode

extension GrabbitDocument {
    func encodeAnnotations(capturedAt: Date = Date()) -> GrabbitDocumentData {
        GrabbitDocumentData(
            capturedAt: capturedAt,
            borderWeight: Double(borderWeight),
            borderColor: CodableColor(borderColor),
            borderEnabled: borderEnabled,
            shadowOffsetX: Double(shadowOffsetX),
            shadowOffsetY: Double(shadowOffsetY),
            shadowBlur: Double(shadowBlur),
            shadowColor: CodableColor(shadowColor),
            shadowOpacity: Double(shadowOpacity),
            shadowEnabled: shadowEnabled,
            arrowWeight: Double(arrowWeight),
            arrowColor: CodableColor(arrowColor),
            textFontName: textFontName,
            textFontSize: Double(textFontSize),
            textFontColor: CodableColor(textFontColor),
            textOutlineColor: CodableColor(textOutlineColor),
            textOutlineWeight: Double(textOutlineWeight),
            shapeBorderWeight: Double(shapeBorderWeight),
            shapeBorderColor: CodableColor(shapeBorderColor),
            shapeFillColor: CodableColor(shapeFillColor),
            highlightColor: CodableColor(highlightColor),
            highlightOpacity: Double(highlightOpacity),
            spotlightOverlayColor: CodableColor(spotlightOverlayColor),
            spotlightOverlayOpacity: Double(spotlightOverlayOpacity),
            spotlightShapeType: CodableShapeType(spotlightShapeType),
            stepDiameter: Double(stepDiameter),
            stepFillColor: CodableColor(stepFillColor),
            stepTextColor: CodableColor(stepTextColor),
            arrows: arrows.map(CodableArrow.init),
            textAnnotations: textAnnotations.map(CodableTextAnnotation.init),
            shapes: shapes.map(CodableShape.init),
            blurRegions: blurRegions.map(CodableBlurRegion.init),
            highlights: highlights.map(CodableHighlight.init),
            spotlights: spotlights.map(CodableSpotlight.init),
            stepBadges: stepBadges.map(CodableStepBadge.init),
            zOrderCounter: zOrderCounter
        )
    }
}

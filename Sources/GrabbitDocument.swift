import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - GrabbitDocument
//
// The NSDocument subclass that owns all model state for one editor session.
// Every mutation goes through a method here that registers its inverse with
// undoManager before making the change — giving Cmd+Z/Cmd+Shift+Z for free.
//
// The document can be in two states:
//   • Untitled (from a screen capture or "New from Clipboard") — fileURL is nil
//   • File-backed (opened from disk or saved at least once) — fileURL is set
//
// Saving always writes the fully-rendered flat image (border + annotations +
// shadow) to a PNG/JPEG/TIFF file, matching the previous behaviour.

class GrabbitDocument: NSDocument {

    // MARK: - Model state

    /// The base image (after any crops). Starts as the captured/opened image.
    private(set) var currentImage: NSImage

    /// True when the editor was opened with no image (empty state).
    private(set) var hasImage: Bool

    // Effect settings — loaded from UserDefaults on init, persisted on change.
    var borderWeight:      CGFloat
    var borderColor:       NSColor
    var borderEnabled:     Bool
    var shadowOffsetX:     CGFloat
    var shadowOffsetY:     CGFloat
    var shadowBlur:        CGFloat
    var shadowColor:       NSColor
    var shadowOpacity:     CGFloat
    var shadowEnabled:     Bool

    // Current tool defaults (also persisted).
    var arrowWeight:       CGFloat
    var arrowColor:        NSColor
    var textFontName:      String
    var textFontSize:      CGFloat
    var textFontColor:     NSColor
    var textOutlineColor:  NSColor
    var textOutlineWeight: CGFloat
    var shapeType:         ShapeType = .rectangle
    var shapeBorderWeight: CGFloat
    var shapeBorderColor:  NSColor
    var shapeFillColor:    NSColor
    var highlightColor:    NSColor
    var highlightOpacity:  CGFloat

    // Annotation arrays.
    private(set) var arrows:          [Arrow]          = []
    private(set) var textAnnotations: [TextAnnotation] = []
    private(set) var shapes:          [Shape]          = []
    private(set) var blurRegions:     [BlurRegion]     = []
    private(set) var highlights:      [Highlight]      = []

    // Z-order counter — only ever incremented, never decremented.
    private var zOrderCounter: Int = 0
    func nextZOrder() -> Int { zOrderCounter += 1; return zOrderCounter }

    // Simple dirty flag — set on any mutation, cleared on save.
    private(set) var isDirty: Bool = false

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        switch change {
        case .changeDone, .changeRedone: isDirty = true
        case .changeCleared, .changeUndone: isDirty = false
        default: break
        }
    }

    // MARK: - Callbacks to the window controller

    /// Called after any model mutation so the overlay can redraw.
    var onAnnotationsChanged: (() -> Void)?

    /// Called after currentImage changes (crop, load).
    var onImageChanged: (() -> Void)?

    // MARK: - Init

    /// Designated init for a new document backed by an image (capture / clipboard).
    init(image: NSImage, hasImage: Bool = true) {
        self.currentImage  = image
        self.hasImage      = hasImage

        borderWeight       = CGFloat(loadDouble(Prefs.borderWeight,      default: 0))
        borderColor        = loadColor(Prefs.borderColor,                 default: .black)
        borderEnabled      = UserDefaults.standard.object(forKey: Prefs.borderEnabled) != nil
                             ? UserDefaults.standard.bool(forKey: Prefs.borderEnabled) : false
        shadowOffsetX      = CGFloat(loadDouble(Prefs.shadowX,            default: 5))
        shadowOffsetY      = CGFloat(loadDouble(Prefs.shadowY,            default: -5))
        shadowBlur         = CGFloat(loadDouble(Prefs.shadowBlur,         default: 10))
        shadowColor        = loadColor(Prefs.shadowColor,                 default: .black)
        shadowOpacity      = CGFloat(loadDouble(Prefs.shadowOpacity,      default: 0))
        shadowEnabled      = UserDefaults.standard.object(forKey: Prefs.shadowEnabled) != nil
                             ? UserDefaults.standard.bool(forKey: Prefs.shadowEnabled) : false
        arrowWeight        = CGFloat(loadDouble(Prefs.arrowWeight,        default: 2))
        arrowColor         = loadColor(Prefs.arrowColor,                  default: .systemRed)
        textFontName       = loadString(Prefs.textFontName,               default: "Helvetica-Bold")
        textFontSize       = CGFloat(loadDouble(Prefs.textFontSize,       default: 24))
        textFontColor      = loadColor(Prefs.textFontColor,               default: .white)
        textOutlineColor   = loadColor(Prefs.textOutlineColor,            default: .black)
        textOutlineWeight  = CGFloat(loadDouble(Prefs.textOutlineWeight,  default: 2))
        shapeBorderWeight  = CGFloat(loadDouble(Prefs.shapeBorderWeight,  default: 2))
        shapeBorderColor   = loadColor(Prefs.shapeBorderColor,            default: .black)
        shapeFillColor     = loadColor(Prefs.shapeFillColor,              default: .clear)
        highlightColor     = NSColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0)
        highlightOpacity   = 0.4

        super.init()
        // A freshly captured/opened image is immediately dirty — it hasn't been saved yet.
        if hasImage { updateChangeCount(.changeDone) }
    }

    /// Required by NSDocument for file-backed open. Loads the image from disk.
    override init() {
        currentImage  = NSImage(size: NSSize(width: 1, height: 1))
        hasImage      = false

        borderWeight       = CGFloat(loadDouble(Prefs.borderWeight,      default: 0))
        borderColor        = loadColor(Prefs.borderColor,                 default: .black)
        borderEnabled      = UserDefaults.standard.object(forKey: Prefs.borderEnabled) != nil
                             ? UserDefaults.standard.bool(forKey: Prefs.borderEnabled) : false
        shadowOffsetX      = CGFloat(loadDouble(Prefs.shadowX,            default: 5))
        shadowOffsetY      = CGFloat(loadDouble(Prefs.shadowY,            default: -5))
        shadowBlur         = CGFloat(loadDouble(Prefs.shadowBlur,         default: 10))
        shadowColor        = loadColor(Prefs.shadowColor,                 default: .black)
        shadowOpacity      = CGFloat(loadDouble(Prefs.shadowOpacity,      default: 0))
        shadowEnabled      = UserDefaults.standard.object(forKey: Prefs.shadowEnabled) != nil
                             ? UserDefaults.standard.bool(forKey: Prefs.shadowEnabled) : false
        arrowWeight        = CGFloat(loadDouble(Prefs.arrowWeight,        default: 2))
        arrowColor         = loadColor(Prefs.arrowColor,                  default: .systemRed)
        textFontName       = loadString(Prefs.textFontName,               default: "Helvetica-Bold")
        textFontSize       = CGFloat(loadDouble(Prefs.textFontSize,       default: 24))
        textFontColor      = loadColor(Prefs.textFontColor,               default: .white)
        textOutlineColor   = loadColor(Prefs.textOutlineColor,            default: .black)
        textOutlineWeight  = CGFloat(loadDouble(Prefs.textOutlineWeight,  default: 2))
        shapeBorderWeight  = CGFloat(loadDouble(Prefs.shapeBorderWeight,  default: 2))
        shapeBorderColor   = loadColor(Prefs.shapeBorderColor,            default: .black)
        shapeFillColor     = loadColor(Prefs.shapeFillColor,              default: .clear)
        highlightColor     = NSColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0)
        highlightOpacity   = 0.4

        super.init()
    }

    // MARK: - NSDocument overrides

    override class var autosavesInPlace: Bool { false }

    // We manage our own "unsaved changes" prompts in EditorWindowController,
    // so tell NSDocument the document can always close immediately.
    override func canClose(withDelegate delegate: Any,
                           shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        // Signal "yes, close" to the delegate without showing any sheet.
        guard let sel = shouldCloseSelector,
              let obj = delegate as? NSObject else { return }
        // The selector signature is: -(void)document:(NSDocument*)doc
        //     shouldClose:(BOOL)shouldClose contextInfo:(void*)ctx
        // We use NSInvocation via ObjC runtime to pass the bool correctly.
        let imp = obj.method(for: sel)
        typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let fn = unsafeBitCast(imp, to: Fn.self)
        fn(obj, sel, self, true, contextInfo)
    }

    override func makeWindowControllers() {
        let wc = EditorWindowController(document: self)
        addWindowController(wc)
    }

    // MARK: Read — opening an image file from disk

    override func read(from url: URL, ofType typeName: String) throws {
        guard let image = NSImage(contentsOf: url) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr)
        }
        currentImage = image
        hasImage     = true
        // Clear any stale annotations from a previous load.
        arrows.removeAll(); textAnnotations.removeAll()
        shapes.removeAll(); blurRegions.removeAll(); highlights.removeAll()
    }

    // MARK: Write — saving the rendered flat image

    override func write(to url: URL, ofType typeName: String) throws {
        let image = rendered()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr)
        }
        let type: UTType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": type = .jpeg
        case "tiff", "tif": type = .tiff
        default:            type = .png
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr)
        }
    }

    // Use a save panel that offers PNG/JPEG/TIFF.
    override func runModalSavePanel(for saveOperation: NSDocument.SaveOperationType,
                                    delegate: Any?,
                                    didSave didSaveSelector: Selector?,
                                    contextInfo: UnsafeMutableRawPointer?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "capture.png"
        panel.isExtensionHidden = false

        guard let win = windowForSheet else {
            super.runModalSavePanel(for: saveOperation, delegate: delegate,
                                    didSave: didSaveSelector, contextInfo: contextInfo)
            return
        }

        panel.beginSheetModal(for: win) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url {
                do {
                    try self.write(to: url, ofType: url.pathExtension)
                    self.fileURL = url
                    self.updateChangeCount(.changeCleared)
                    // Notify delegate the save succeeded.
                    if let sel = didSaveSelector, let del = delegate as AnyObject? {
                        _ = del.perform(sel, with: self, with: true)
                    }
                } catch {
                    self.presentError(error)
                    if let sel = didSaveSelector, let del = delegate as AnyObject? {
                        _ = del.perform(sel, with: self, with: false)
                    }
                }
            } else {
                if let sel = didSaveSelector, let del = delegate as AnyObject? {
                    _ = del.perform(sel, with: self, with: false)
                }
            }
        }
    }

    // MARK: - Load image (replaces doLoadImage)

    /// Replace the current image and clear all annotations.
    /// Registers undo for the previous state.
    func loadImage(_ image: NSImage) {
        let prevImage       = currentImage
        let prevHasImage    = hasImage
        let prevArrows      = arrows
        let prevTexts       = textAnnotations
        let prevShapes      = shapes
        let prevBlurs       = blurRegions
        let prevHighlights  = highlights
        let prevZOrder      = zOrderCounter

        undoManager?.registerUndo(withTarget: self) { doc in
            doc.restoreFullState(
                image: prevImage, hasImage: prevHasImage,
                arrows: prevArrows, texts: prevTexts,
                shapes: prevShapes, blurs: prevBlurs,
                highlights: prevHighlights, zOrder: prevZOrder
            )
        }
        undoManager?.setActionName("Load Image")

        currentImage = image
        hasImage     = true
        arrows.removeAll(); textAnnotations.removeAll()
        shapes.removeAll(); blurRegions.removeAll(); highlights.removeAll()
        zOrderCounter = 0
        updateChangeCount(.changeDone)
        onImageChanged?()
        onAnnotationsChanged?()
    }

    private func restoreFullState(image: NSImage, hasImage: Bool,
                                  arrows: [Arrow], texts: [TextAnnotation],
                                  shapes: [Shape], blurs: [BlurRegion],
                                  highlights: [Highlight], zOrder: Int) {
        let prevImage      = currentImage
        let prevHasImage   = self.hasImage
        let prevArrows     = self.arrows
        let prevTexts      = textAnnotations
        let prevShapes     = self.shapes
        let prevBlurs      = blurRegions
        let prevHighlights = self.highlights
        let prevZOrder     = zOrderCounter

        undoManager?.registerUndo(withTarget: self) { doc in
            doc.restoreFullState(
                image: prevImage, hasImage: prevHasImage,
                arrows: prevArrows, texts: prevTexts,
                shapes: prevShapes, blurs: prevBlurs,
                highlights: prevHighlights, zOrder: prevZOrder
            )
        }

        currentImage      = image
        self.hasImage     = hasImage
        self.arrows       = arrows
        textAnnotations   = texts
        self.shapes       = shapes
        blurRegions       = blurs
        self.highlights   = highlights
        zOrderCounter     = zOrder
        updateChangeCount(.changeDone)
        onImageChanged?()
        onAnnotationsChanged?()
    }

    // MARK: - Crop (undoable)

    func applyCrop(to image: NSImage) {
        let prev = currentImage
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.applyCrop(to: prev)
        }
        undoManager?.setActionName("Crop")
        currentImage = image
        updateChangeCount(.changeDone)
        onImageChanged?()
    }

    func applyResize(to image: NSImage) {
        let prev = currentImage
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.applyResize(to: prev)
        }
        undoManager?.setActionName("Resize")
        currentImage = image
        updateChangeCount(.changeDone)
        onImageChanged?()
    }

    // MARK: - Annotation mutations (all undoable)
    // Each method snapshots the relevant array, registers the inverse, then mutates.

    func addArrow(_ arrow: Arrow) {
        undoManager?.registerUndo(withTarget: self) { [id = arrow.id] doc in
            doc.removeArrow(id: id)
        }
        undoManager?.setActionName("Add Arrow")
        arrows.append(arrow)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func removeArrow(id: UUID) {
        guard let idx = arrows.firstIndex(where: { $0.id == id }) else { return }
        let arrow = arrows[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.addArrow(arrow)
        }
        undoManager?.setActionName("Delete Arrow")
        arrows.remove(at: idx)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func updateArrow(id: UUID, start: CGPoint? = nil, end: CGPoint? = nil,
                     weight: CGFloat? = nil, color: NSColor? = nil) {
        guard let idx = arrows.firstIndex(where: { $0.id == id }) else { return }
        let prev = arrows[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.updateArrow(id: id, start: prev.start, end: prev.end,
                            weight: prev.weight, color: prev.color)
        }
        undoManager?.setActionName("Move Arrow")
        if let v = start  { arrows[idx].start  = v }
        if let v = end    { arrows[idx].end    = v }
        if let v = weight { arrows[idx].weight = v }
        if let v = color  { arrows[idx].color  = v }
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func addTextAnnotation(_ ann: TextAnnotation) {
        undoManager?.registerUndo(withTarget: self) { [id = ann.id] doc in
            doc.removeTextAnnotation(id: id)
        }
        undoManager?.setActionName("Add Text")
        textAnnotations.append(ann)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func removeTextAnnotation(id: UUID) {
        guard let idx = textAnnotations.firstIndex(where: { $0.id == id }) else { return }
        let ann = textAnnotations[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.addTextAnnotation(ann)
        }
        undoManager?.setActionName("Delete Text")
        textAnnotations.remove(at: idx)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func updateTextAnnotation(id: UUID, position: CGPoint? = nil, content: String? = nil,
                               fontName: String? = nil, fontSize: CGFloat? = nil,
                               fontColor: NSColor? = nil, outlineColor: NSColor? = nil,
                               outlineWeight: CGFloat? = nil) {
        guard let idx = textAnnotations.firstIndex(where: { $0.id == id }) else { return }
        let prev = textAnnotations[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.updateTextAnnotation(id: id, position: prev.position, content: prev.content,
                                     fontName: prev.fontName, fontSize: prev.fontSize,
                                     fontColor: prev.fontColor, outlineColor: prev.outlineColor,
                                     outlineWeight: prev.outlineWeight)
        }
        undoManager?.setActionName("Edit Text")
        if let v = position     { textAnnotations[idx].position     = v }
        if let v = content      { textAnnotations[idx].content      = v }
        if let v = fontName     { textAnnotations[idx].fontName     = v }
        if let v = fontSize     { textAnnotations[idx].fontSize     = v }
        if let v = fontColor    { textAnnotations[idx].fontColor    = v }
        if let v = outlineColor { textAnnotations[idx].outlineColor = v }
        if let v = outlineWeight { textAnnotations[idx].outlineWeight = v }
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func addShape(_ shape: Shape) {
        undoManager?.registerUndo(withTarget: self) { [id = shape.id] doc in
            doc.removeShape(id: id)
        }
        undoManager?.setActionName("Add Shape")
        shapes.append(shape)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func removeShape(id: UUID) {
        guard let idx = shapes.firstIndex(where: { $0.id == id }) else { return }
        let shape = shapes[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.addShape(shape)
        }
        undoManager?.setActionName("Delete Shape")
        shapes.remove(at: idx)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func updateShape(id: UUID, rect: CGRect? = nil, shapeType: ShapeType? = nil,
                     borderWeight: CGFloat? = nil, borderColor: NSColor? = nil,
                     fillColor: NSColor? = nil) {
        guard let idx = shapes.firstIndex(where: { $0.id == id }) else { return }
        let prev = shapes[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.updateShape(id: id, rect: prev.rect, shapeType: prev.shapeType,
                            borderWeight: prev.borderWeight, borderColor: prev.borderColor,
                            fillColor: prev.fillColor)
        }
        undoManager?.setActionName("Edit Shape")
        if let v = rect         { shapes[idx].rect         = v }
        if let v = shapeType    { shapes[idx].shapeType    = v }
        if let v = borderWeight { shapes[idx].borderWeight = v }
        if let v = borderColor  { shapes[idx].borderColor  = v }
        if let v = fillColor    { shapes[idx].fillColor    = v }
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func addBlurRegion(_ region: BlurRegion) {
        undoManager?.registerUndo(withTarget: self) { [id = region.id] doc in
            doc.removeBlurRegion(id: id)
        }
        undoManager?.setActionName("Add Blur")
        blurRegions.append(region)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func removeBlurRegion(id: UUID) {
        guard let idx = blurRegions.firstIndex(where: { $0.id == id }) else { return }
        let region = blurRegions[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.addBlurRegion(region)
        }
        undoManager?.setActionName("Delete Blur")
        blurRegions.remove(at: idx)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func updateBlurRegion(id: UUID, rect: CGRect? = nil,
                          intensity: CGFloat? = nil, style: BlurStyle? = nil) {
        guard let idx = blurRegions.firstIndex(where: { $0.id == id }) else { return }
        let prev = blurRegions[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.updateBlurRegion(id: id, rect: prev.rect,
                                 intensity: prev.intensity, style: prev.style)
        }
        undoManager?.setActionName("Edit Blur")
        if let v = rect      { blurRegions[idx].rect      = v }
        if let v = intensity { blurRegions[idx].intensity = v }
        if let v = style     { blurRegions[idx].style     = v }
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func addHighlight(_ highlight: Highlight) {
        undoManager?.registerUndo(withTarget: self) { [id = highlight.id] doc in
            doc.removeHighlight(id: id)
        }
        undoManager?.setActionName("Add Highlight")
        highlights.append(highlight)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func removeHighlight(id: UUID) {
        guard let idx = highlights.firstIndex(where: { $0.id == id }) else { return }
        let h = highlights[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.addHighlight(h)
        }
        undoManager?.setActionName("Delete Highlight")
        highlights.remove(at: idx)
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func updateHighlight(id: UUID, rect: CGRect? = nil,
                         color: NSColor? = nil, opacity: CGFloat? = nil) {
        guard let idx = highlights.firstIndex(where: { $0.id == id }) else { return }
        let prev = highlights[idx]
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.updateHighlight(id: id, rect: prev.rect,
                                color: prev.color, opacity: prev.opacity)
        }
        undoManager?.setActionName("Edit Highlight")
        if let v = rect    { highlights[idx].rect    = v }
        if let v = color   { highlights[idx].color   = v }
        if let v = opacity { highlights[idx].opacity = v }
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    // MARK: - Z-order mutations (undoable)

    func setZOrders(_ pairs: [(id: UUID, z: Int)]) {
        // Snapshot current z-orders for undo.
        let prev = allZOrderPairs()
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.setZOrders(prev)
        }
        undoManager?.setActionName("Arrange")
        for pair in pairs {
            applyZOrder(pair.z, for: pair.id)
        }
        updateChangeCount(.changeDone)
        onAnnotationsChanged?()
    }

    func allZOrderPairs() -> [(id: UUID, z: Int)] {
        var all: [(UUID, Int)] = []
        arrows.forEach          { all.append(($0.id, $0.zOrder)) }
        textAnnotations.forEach { all.append(($0.id, $0.zOrder)) }
        shapes.forEach          { all.append(($0.id, $0.zOrder)) }
        blurRegions.forEach     { all.append(($0.id, $0.zOrder)) }
        highlights.forEach      { all.append(($0.id, $0.zOrder)) }
        return all.sorted { $0.1 < $1.1 }
    }

    private func applyZOrder(_ z: Int, for id: UUID) {
        if let i = arrows.firstIndex(where: { $0.id == id })          { arrows[i].zOrder = z }
        if let i = textAnnotations.firstIndex(where: { $0.id == id }) { textAnnotations[i].zOrder = z }
        if let i = shapes.firstIndex(where: { $0.id == id })          { shapes[i].zOrder = z }
        if let i = blurRegions.firstIndex(where: { $0.id == id })     { blurRegions[i].zOrder = z }
        if let i = highlights.firstIndex(where: { $0.id == id })      { highlights[i].zOrder = z }
    }

    // MARK: - Preferences persistence

    func savePrefs() {
        saveDouble(Double(borderWeight),      key: Prefs.borderWeight)
        saveColor(borderColor,                key: Prefs.borderColor)
        UserDefaults.standard.set(borderEnabled, forKey: Prefs.borderEnabled)
        saveDouble(Double(shadowOffsetX),     key: Prefs.shadowX)
        saveDouble(Double(shadowOffsetY),     key: Prefs.shadowY)
        saveDouble(Double(shadowBlur),        key: Prefs.shadowBlur)
        saveColor(shadowColor,                key: Prefs.shadowColor)
        saveDouble(Double(shadowOpacity),     key: Prefs.shadowOpacity)
        UserDefaults.standard.set(shadowEnabled, forKey: Prefs.shadowEnabled)
        saveDouble(Double(arrowWeight),       key: Prefs.arrowWeight)
        saveColor(arrowColor,                 key: Prefs.arrowColor)
        saveString(textFontName,              key: Prefs.textFontName)
        saveDouble(Double(textFontSize),      key: Prefs.textFontSize)
        saveColor(textFontColor,              key: Prefs.textFontColor)
        saveColor(textOutlineColor,           key: Prefs.textOutlineColor)
        saveDouble(Double(textOutlineWeight), key: Prefs.textOutlineWeight)
        saveDouble(Double(shapeBorderWeight), key: Prefs.shapeBorderWeight)
        saveColor(shapeBorderColor,           key: Prefs.shapeBorderColor)
        saveColor(shapeFillColor,             key: Prefs.shapeFillColor)
    }
}

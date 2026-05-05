import AppKit
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers
import Vision

// MARK: - EditorWindowController

class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {

    // MARK: Document
    private(set) var grabbitDocument: GrabbitDocument

    // MARK: Views
    var captureView:             NSImageView!
    var annotationOverlay:       AnnotationOverlay!
    private var canvas:          CanvasView!
    private var sidebar:         TabbedEditorSidebar!
    private var arrowToolButton: NSButton!
    private var textToolButton:  NSButton!
    private var shapeToolButton: NSButton!
    private var blurToolButton:  NSButton!
    private var highlightToolButton: NSButton!
    private var zoomScroll:      NSScrollView!
    private var zoomLabel:       NSTextField!
    private var cropToolButton:   NSButton!
    private var resizeToolButton: NSButton!
    private var ocrToolButton:    NSButton!
    var cropOverlay:              CropOverlayView!
    private var placeholderLabel: NSTextField!

    private var borderWeightSlider:      NSSlider!;  private var borderWeightLabel:      NSTextField!
    private var borderColorWell:         NSColorWell!
    private var shadowXSlider:           NSSlider!;  private var shadowXLabel:           NSTextField!
    private var shadowYSlider:           NSSlider!;  private var shadowYLabel:           NSTextField!
    private var shadowBlurSlider:        NSSlider!;  private var shadowBlurLabel:        NSTextField!
    private var shadowColorWell:         NSColorWell!
    private var shadowOpacitySlider:     NSSlider!;  private var shadowOpacityLabel:     NSTextField!
    private var borderToggle:            NSButton!
    private var shadowToggle:            NSButton!
    private var arrowWeightSlider:       NSSlider!;  private var arrowWeightLabel:       NSTextField!
    private var arrowColorWell:          NSColorWell!
    private var textFontPopup:           NSPopUpButton!
    private var textFontSizeSlider:      NSSlider!;  private var textFontSizeLabel:      NSTextField!
    private var textFontColorWell:       NSColorWell!
    private var textOutlineColorWell:    NSColorWell!
    private var textOutlineWeightSlider: NSSlider!;  private var textOutlineWeightLabel: NSTextField!
    private var shapeTypePopup:          NSPopUpButton!
    private var shapeBorderWeightSlider: NSSlider!;  private var shapeBorderWeightLabel: NSTextField!
    private var shapeBorderColorWell:    NSColorWell!
    private var shapeFillColorWell:      NSColorWell!
    private var blurIntensitySlider:     NSSlider!;  private var blurIntensityLabel:     NSTextField!
    private var blurStylePopup:          NSPopUpButton!
    private var highlightColorWell:      NSColorWell!
    private var highlightOpacitySlider:  NSSlider!;  private var highlightOpacityLabel:  NSTextField!

    private var toolMode: ToolMode = .none
    private var toolShortcuts = ToolShortcutsConfig.load()
    private var toolShortcutMonitor: Any?

    // MARK: - Show helpers (used by CaptureSession / AppDelegate)

    static func show(image: NSImage) {
        let doc = GrabbitDocument(image: image)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        activateApp()
    }

    static func showEmpty() {
        let doc = GrabbitDocument(image: NSImage(size: NSSize(width: 1, height: 1)),
                                  hasImage: false)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        activateApp()
    }

    static func activateApp() {
        NSApp.setActivationPolicy(.regular)
        let other = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.activationPolicy == .regular &&
            $0 != NSRunningApplication.current
        }) ?? NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        })
        other?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Init

    init(document: GrabbitDocument) {
        self.grabbitDocument = document

        // ── Window ──────────────────────────────────────────────────────────────
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let w = min(visible.width  * 0.70, 1400)
        let h = min(visible.height * 0.70,  900)
        let x = visible.minX + (visible.width  - w) / 2
        let y = visible.minY + (visible.height - h) / 2
        let initialFrame = NSRect(x: x, y: y, width: w, height: h)

        let win = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        win.title = "Grabbit"
        win.setFrame(initialFrame, display: false)
        win.minSize = NSSize(width: 600, height: 400)

        // ── Image view + overlay ─────────────────────────────────────────────────
        let iv = NSImageView()
        iv.image = document.currentImage
        iv.imageScaling = .scaleProportionallyDown
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false

        let ol = AnnotationOverlay()
        ol.translatesAutoresizingMaskIntoConstraints = false
        ol.wantsLayer = true

        // ── Zoom scroll view ─────────────────────────────────────────────────────
        let zoomDoc = CenteredDocumentView()
        zoomDoc.translatesAutoresizingMaskIntoConstraints = false
        zoomDoc.addSubview(iv)
        zoomDoc.addSubview(ol)

        let pad: CGFloat = 32
        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: zoomDoc.topAnchor, constant: pad),
            iv.bottomAnchor.constraint(equalTo: zoomDoc.bottomAnchor, constant: -pad),
            iv.leadingAnchor.constraint(equalTo: zoomDoc.leadingAnchor, constant: pad),
            iv.trailingAnchor.constraint(equalTo: zoomDoc.trailingAnchor, constant: -pad),
            ol.topAnchor.constraint(equalTo: iv.topAnchor),
            ol.bottomAnchor.constraint(equalTo: iv.bottomAnchor),
            ol.leadingAnchor.constraint(equalTo: iv.leadingAnchor),
            ol.trailingAnchor.constraint(equalTo: iv.trailingAnchor),
        ])

        let zs = ZoomableScrollView()
        zs.allowsMagnification   = true
        zs.minMagnification      = 0.1
        zs.maxMagnification      = 8.0
        zs.hasVerticalScroller   = true
        zs.hasHorizontalScroller = true
        zs.autohidesScrollers    = true
        zs.scrollerStyle         = .overlay
        zs.drawsBackground       = false
        zs.translatesAutoresizingMaskIntoConstraints = false

        let centerClip = CenteringClipView()
        centerClip.drawsBackground = false
        zs.contentView  = centerClip
        zs.documentView = zoomDoc

        // ── Canvas ───────────────────────────────────────────────────────────────
        let cv = CanvasView()
        cv.translatesAutoresizingMaskIntoConstraints = false

        // ── Toolbar buttons ──────────────────────────────────────────────────────
        let arrowBtn     = makeToolButton("Arrow")
        let textBtn      = makeToolButton("Text")
        let shapeBtn     = makeToolButton("Shape")
        let cropBtn      = makeToolButton("Crop")
        let resizeBtn    = makeToolButton("Resize")
        let ocrBtn       = makeToolButton("Extract Text")
        let blurBtn      = makeToolButton("Blur")
        let highlightBtn = makeToolButton("Highlight")
        cropBtn.toolTip      = "Crop image"
        resizeBtn.toolTip    = "Resize image"
        ocrBtn.toolTip       = "Drag a region to extract text (OCR)"
        blurBtn.toolTip      = "Blur / pixelate a region"
        highlightBtn.toolTip = "Highlight a region"

        let toolsStack = NSStackView(views: [cropBtn, resizeBtn, ocrBtn, arrowBtn, textBtn, shapeBtn, blurBtn, highlightBtn])
        toolsStack.orientation = .horizontal
        toolsStack.spacing = 6
        toolsStack.translatesAutoresizingMaskIntoConstraints = false

        let zoomOutBtn = NSButton(title: "−", target: nil, action: nil)
        zoomOutBtn.bezelStyle = .rounded; zoomOutBtn.controlSize = .small
        zoomOutBtn.translatesAutoresizingMaskIntoConstraints = false

        let zoomInBtn = NSButton(title: "+", target: nil, action: nil)
        zoomInBtn.bezelStyle = .rounded; zoomInBtn.controlSize = .small
        zoomInBtn.translatesAutoresizingMaskIntoConstraints = false

        let zl = NSTextField(labelWithString: "100%")
        zl.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zl.alignment = .center
        zl.translatesAutoresizingMaskIntoConstraints = false
        zl.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let zoomStack = NSStackView(views: [zoomOutBtn, zl, zoomInBtn])
        zoomStack.orientation = .horizontal; zoomStack.spacing = 4
        zoomStack.translatesAutoresizingMaskIntoConstraints = false

        let toolbarBg = NSVisualEffectView()
        toolbarBg.material = .windowBackground; toolbarBg.blendingMode = .withinWindow
        toolbarBg.state = .active
        toolbarBg.translatesAutoresizingMaskIntoConstraints = false

        let toolbarSep = NSBox()
        toolbarSep.boxType = .custom; toolbarSep.borderWidth = 0
        toolbarSep.fillColor = NSColor.separatorColor; toolbarSep.cornerRadius = 0
        toolbarSep.translatesAutoresizingMaskIntoConstraints = false

        let tbH: CGFloat = 44
        cv.addSubview(toolbarBg); cv.addSubview(toolbarSep)
        cv.addSubview(zs); cv.addSubview(toolsStack); cv.addSubview(zoomStack)

        NSLayoutConstraint.activate([
            toolbarBg.topAnchor.constraint(equalTo: cv.topAnchor),
            toolbarBg.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            toolbarBg.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            toolbarBg.heightAnchor.constraint(equalToConstant: tbH),
            toolbarSep.topAnchor.constraint(equalTo: toolbarBg.bottomAnchor),
            toolbarSep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            toolbarSep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            toolbarSep.heightAnchor.constraint(equalToConstant: 1),
            zs.topAnchor.constraint(equalTo: cv.topAnchor, constant: tbH + 1),
            zs.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            zs.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            zs.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            toolsStack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            toolsStack.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: tbH / 2),
            zoomStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            zoomStack.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: tbH / 2),
        ])

        // ── Crop overlay ─────────────────────────────────────────────────────────
        let co = CropOverlayView()
        co.translatesAutoresizingMaskIntoConstraints = false
        co.isHidden = true
        zoomDoc.addSubview(co)
        NSLayoutConstraint.activate([
            co.topAnchor.constraint(equalTo: iv.topAnchor),
            co.bottomAnchor.constraint(equalTo: iv.bottomAnchor),
            co.leadingAnchor.constraint(equalTo: iv.leadingAnchor),
            co.trailingAnchor.constraint(equalTo: iv.trailingAnchor),
        ])

        // ── Sidebar controls ─────────────────────────────────────────────────────
        let doc = document  // local alias for readability

        let bwSlider = sld(0, 50,  Double(doc.borderWeight));    let bwLabel = vlbl(fmt(doc.borderWeight))
        let bcWell   = well(doc.borderColor)
        let bToggle  = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        bToggle.state = doc.borderEnabled ? .on : .off

        let sxSlider = sld(-50, 50, Double(doc.shadowOffsetX));  let sxLabel = vlbl(fmt(doc.shadowOffsetX))
        let sySlider = sld(-50, 50, Double(doc.shadowOffsetY));  let syLabel = vlbl(fmt(doc.shadowOffsetY))
        let sbSlider = sld(0,   50, Double(doc.shadowBlur));     let sbLabel = vlbl(fmt(doc.shadowBlur))
        let scWell   = well(doc.shadowColor)
        let soSlider = sld(0, 100, Double(doc.shadowOpacity * 100))
        let soLabel  = vlbl(fmtPct(doc.shadowOpacity))
        let sToggle  = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        sToggle.state = doc.shadowEnabled ? .on : .off

        let awSlider = sld(1, 20, Double(doc.arrowWeight));      let awLabel = vlbl(fmt(doc.arrowWeight))
        let acWell   = well(doc.arrowColor)

        let tfPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        tfPopup.controlSize = .small
        tfPopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let fonts = ["Helvetica-Bold", "Helvetica", "Arial-BoldMT", "ArialMT",
                     "Courier-Bold", "Courier", "TimesNewRomanPS-BoldMT",
                     "TimesNewRomanPSMT", "Georgia-Bold", "Georgia",
                     "Menlo-Bold", "Menlo-Regular", "Monaco"]
        fonts.forEach { tfPopup.addItem(withTitle: $0.replacingOccurrences(of: "-", with: " ")) }
        if let idx = fonts.firstIndex(of: doc.textFontName) { tfPopup.selectItem(at: idx) }
        let tfSizeSlider = sld(8, 72, Double(doc.textFontSize)); let tfSizeLabel = vlbl(fmt(doc.textFontSize))
        let tfColorWell  = well(doc.textFontColor)
        let toColorWell  = well(doc.textOutlineColor)
        let toWtSlider   = sld(0, 20, Double(doc.textOutlineWeight))
        let toWtLabel    = vlbl(fmt(doc.textOutlineWeight))

        let shapeTypePopupLocal = NSPopUpButton(frame: .zero, pullsDown: false)
        shapeTypePopupLocal.controlSize = .small
        shapeTypePopupLocal.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        shapeTypePopupLocal.addItem(withTitle: "Rectangle")
        shapeTypePopupLocal.addItem(withTitle: "Circle")
        shapeTypePopupLocal.addItem(withTitle: "Rounded Rectangle")
        shapeTypePopupLocal.selectItem(at: 0)
        let shapeBorderSlider = sld(0, 50, Double(doc.shapeBorderWeight))
        let shapeBorderLabel  = vlbl(fmt(doc.shapeBorderWeight))
        let shapeBorderWell   = well(doc.shapeBorderColor)
        let shapeFillWell     = well(doc.shapeFillColor)

        let blurIntensitySliderLocal = sld(1, 100, 80); let blurIntensityLabelLocal = vlbl("80")
        let blurStylePopupLocal = NSPopUpButton(frame: .zero, pullsDown: false)
        blurStylePopupLocal.controlSize = .small
        blurStylePopupLocal.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        blurStylePopupLocal.addItem(withTitle: "Blur")
        blurStylePopupLocal.addItem(withTitle: "Pixelate")
        blurStylePopupLocal.selectItem(at: 0)

        let highlightColorWellLocal     = well(doc.highlightColor)
        let highlightOpacitySliderLocal = sld(5, 85, Double(doc.highlightOpacity * 100))
        let highlightOpacityLabelLocal  = vlbl("\(Int(doc.highlightOpacity * 100))%")

        let sb = TabbedEditorSidebar(
            arrowWeightSlider: awSlider, arrowWeightLabel: awLabel, arrowColorWell: acWell,
            textFontPopup: tfPopup,
            textFontSizeSlider: tfSizeSlider, textFontSizeLabel: tfSizeLabel,
            textFontColorWell: tfColorWell,
            textOutlineColorWell: toColorWell,
            textOutlineWeightSlider: toWtSlider, textOutlineWeightLabel: toWtLabel,
            shapeTypePopup: shapeTypePopupLocal,
            shapeBorderWeightSlider: shapeBorderSlider, shapeBorderWeightLabel: shapeBorderLabel,
            shapeBorderColorWell: shapeBorderWell,
            shapeFillColorWell: shapeFillWell,
            blurIntensitySlider: blurIntensitySliderLocal, blurIntensityLabel: blurIntensityLabelLocal,
            blurStylePopup: blurStylePopupLocal,
            highlightColorWell: highlightColorWellLocal,
            highlightOpacitySlider: highlightOpacitySliderLocal,
            highlightOpacityLabel: highlightOpacityLabelLocal)
        sb.translatesAutoresizingMaskIntoConstraints = false
        sb.addEffectSection("BORDER", toggle: bToggle)
        sb.addEffectRow("Weight", bwSlider, bwLabel)
        sb.addEffectRow("Color",  bcWell)
        sb.addEffectSection("SHADOW", toggle: sToggle)
        sb.addEffectRow("Offset X", sxSlider, sxLabel)
        sb.addEffectRow("Offset Y", sySlider, syLabel)
        sb.addEffectRow("Blur",     sbSlider, sbLabel)
        sb.addEffectRow("Color",    scWell)
        sb.addEffectRow("Opacity",  soSlider, soLabel)

        // ── Root layout ──────────────────────────────────────────────────────────
        let root = NSView()
        root.addSubview(cv); root.addSubview(sb)
        NSLayoutConstraint.activate([
            sb.topAnchor.constraint(equalTo: root.topAnchor),
            sb.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sb.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sb.widthAnchor.constraint(equalToConstant: 220),
            cv.topAnchor.constraint(equalTo: root.topAnchor),
            cv.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            cv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: sb.leadingAnchor),
        ])
        win.contentView = root

        // ── IUO assignments ──────────────────────────────────────────────────────
        captureView = iv;  annotationOverlay = ol;  canvas = cv;  sidebar = sb
        arrowToolButton = arrowBtn;  textToolButton = textBtn;  shapeToolButton = shapeBtn
        blurToolButton = blurBtn;    highlightToolButton = highlightBtn
        zoomScroll = zs;  zoomLabel = zl
        cropToolButton = cropBtn;  resizeToolButton = resizeBtn;  ocrToolButton = ocrBtn;  cropOverlay = co
        borderToggle = bToggle;              shadowToggle = sToggle
        borderWeightSlider = bwSlider;       borderWeightLabel = bwLabel;  borderColorWell = bcWell
        shadowXSlider = sxSlider;            shadowXLabel = sxLabel
        shadowYSlider = sySlider;            shadowYLabel = syLabel
        shadowBlurSlider = sbSlider;         shadowBlurLabel = sbLabel
        shadowColorWell = scWell
        shadowOpacitySlider = soSlider;      shadowOpacityLabel = soLabel
        arrowWeightSlider = awSlider;        arrowWeightLabel = awLabel;   arrowColorWell = acWell
        textFontPopup = tfPopup
        textFontSizeSlider = tfSizeSlider;   textFontSizeLabel = tfSizeLabel
        textFontColorWell = tfColorWell;     textOutlineColorWell = toColorWell
        textOutlineWeightSlider = toWtSlider; textOutlineWeightLabel = toWtLabel
        shapeTypePopup = shapeTypePopupLocal
        shapeBorderWeightSlider = shapeBorderSlider; shapeBorderWeightLabel = shapeBorderLabel
        shapeBorderColorWell = shapeBorderWell;      shapeFillColorWell = shapeFillWell
        blurIntensitySlider = blurIntensitySliderLocal; blurIntensityLabel = blurIntensityLabelLocal
        blurStylePopup = blurStylePopupLocal
        highlightColorWell = highlightColorWellLocal
        highlightOpacitySlider = highlightOpacitySliderLocal
        highlightOpacityLabel  = highlightOpacityLabelLocal

        super.init(window: win)
        win.delegate = self
        setupToolShortcutMonitor()

        // ── Wire targets ─────────────────────────────────────────────────────────
        arrowBtn.target     = self; arrowBtn.action     = #selector(toggleArrowTool(_:))
        textBtn.target      = self; textBtn.action      = #selector(toggleTextTool(_:))
        shapeBtn.target     = self; shapeBtn.action     = #selector(toggleShapeTool(_:))
        cropBtn.target      = self; cropBtn.action      = #selector(toggleCropTool(_:))
        resizeBtn.target    = self; resizeBtn.action    = #selector(resizeToolClicked(_:))
        ocrBtn.target       = self; ocrBtn.action       = #selector(toggleOCRTool(_:))
        blurBtn.target      = self; blurBtn.action      = #selector(toggleBlurTool(_:))
        highlightBtn.target = self; highlightBtn.action = #selector(toggleHighlightTool(_:))
        zoomInBtn.target    = self; zoomInBtn.action    = #selector(zoomIn)
        zoomOutBtn.target   = self; zoomOutBtn.action   = #selector(zoomOut)
        borderToggle.target = self; borderToggle.action = #selector(borderToggleChanged(_:))
        shadowToggle.target = self; shadowToggle.action = #selector(shadowToggleChanged(_:))
        borderWeightSlider.target  = self; borderWeightSlider.action  = #selector(borderWeightChanged(_:))
        shadowXSlider.target       = self; shadowXSlider.action       = #selector(shadowXChanged(_:))
        shadowYSlider.target       = self; shadowYSlider.action       = #selector(shadowYChanged(_:))
        shadowBlurSlider.target    = self; shadowBlurSlider.action    = #selector(shadowBlurChanged(_:))
        shadowOpacitySlider.target = self; shadowOpacitySlider.action = #selector(shadowOpacityChanged(_:))
        arrowWeightSlider.target   = self; arrowWeightSlider.action   = #selector(arrowWeightChanged(_:))
        textFontPopup.target       = self; textFontPopup.action       = #selector(textFontChanged(_:))
        textFontSizeSlider.target  = self; textFontSizeSlider.action  = #selector(textFontSizeChanged(_:))
        textOutlineWeightSlider.target = self
        textOutlineWeightSlider.action = #selector(textOutlineWeightChanged(_:))
        shapeTypePopup.target          = self; shapeTypePopup.action          = #selector(shapeTypeChanged(_:))
        shapeBorderWeightSlider.target = self; shapeBorderWeightSlider.action = #selector(shapeBorderWeightChanged(_:))
        shapeBorderColorWell.target    = self; shapeBorderColorWell.action    = #selector(colorPanelChanged)
        shapeFillColorWell.target      = self; shapeFillColorWell.action      = #selector(colorPanelChanged)
        blurIntensitySlider.target     = self; blurIntensitySlider.action     = #selector(blurIntensityChanged(_:))
        blurStylePopup.target          = self; blurStylePopup.action          = #selector(blurStyleChanged(_:))
        highlightColorWell.target      = self; highlightColorWell.action      = #selector(colorPanelChanged)
        highlightOpacitySlider.target  = self; highlightOpacitySlider.action  = #selector(highlightOpacityChanged(_:))

        (zoomScroll as? ZoomableScrollView)?.onMagnificationChanged = { [weak self] in
            self?.updateZoomLabel()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(colorPanelChanged),
            name: NSColorPanel.colorDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(zoomDidEnd),
            name: NSScrollView.didEndLiveMagnifyNotification, object: zoomScroll)

        // ── Overlay wiring ───────────────────────────────────────────────────────
        annotationOverlay.document            = document
        annotationOverlay.currentWeight       = document.arrowWeight
        annotationOverlay.currentColor        = document.arrowColor
        annotationOverlay.currentFontName     = document.textFontName
        annotationOverlay.currentFontSize     = document.textFontSize
        annotationOverlay.currentFontColor    = document.textFontColor
        annotationOverlay.currentOutlineColor = document.textOutlineColor
        annotationOverlay.currentOutlineWeight = document.textOutlineWeight
        annotationOverlay.currentShapeType    = document.shapeType
        annotationOverlay.currentBorderWeight = document.shapeBorderWeight
        annotationOverlay.currentBorderColor  = document.shapeBorderColor
        annotationOverlay.currentFillColor    = document.shapeFillColor
        annotationOverlay.currentHighlightColor   = document.highlightColor
        annotationOverlay.currentHighlightOpacity = document.highlightOpacity

        annotationOverlay.imageDisplayRectProvider = { [weak self] in
            guard let iv = self?.captureView, let img = iv.image else { return .zero }
            return Self.imageDisplayRect(for: img, in: iv)
        }
        annotationOverlay.imageProvider = { [weak self] in
            self?.grabbitDocument.currentImage
        }
        annotationOverlay.onCopy = { [weak self] in self?.copyToClipboard() }
        annotationOverlay.onActivateTool = { [weak self] tool in
            guard let self else { return }
            self.syncToolbarState(to: tool)
            switch tool {
            case .arrow:     self.annotationOverlay.activeTool = .arrow
            case .text:      self.annotationOverlay.activeTool = .text
            case .shape:     self.annotationOverlay.activeTool = .shape
            case .blur:      self.annotationOverlay.activeTool = .blur
            case .highlight: self.annotationOverlay.activeTool = .highlight
            case .ocr:       self.annotationOverlay.activeTool = .ocr
            case .none:      self.annotationOverlay.activeTool = .none
            }
            self.window?.makeFirstResponder(self.annotationOverlay)
        }

        annotationOverlay.onTextSelectionChanged = { [weak self] ann in
            guard let self else { return }
            if let ann = ann {
                self.grabbitDocument.textFontName      = ann.fontName
                self.grabbitDocument.textFontSize      = ann.fontSize
                self.grabbitDocument.textFontColor     = ann.fontColor
                self.grabbitDocument.textOutlineColor  = ann.outlineColor
                self.grabbitDocument.textOutlineWeight = ann.outlineWeight
                self.annotationOverlay.currentFontName      = ann.fontName
                self.annotationOverlay.currentFontSize      = ann.fontSize
                self.annotationOverlay.currentFontColor     = ann.fontColor
                self.annotationOverlay.currentOutlineColor  = ann.outlineColor
                self.annotationOverlay.currentOutlineWeight = ann.outlineWeight
            }
            let fontList = ["Helvetica-Bold", "Helvetica", "Arial-BoldMT", "ArialMT",
                            "Courier-Bold", "Courier", "TimesNewRomanPS-BoldMT",
                            "TimesNewRomanPSMT", "Georgia-Bold", "Georgia",
                            "Menlo-Bold", "Menlo-Regular", "Monaco"]
            if let idx = fontList.firstIndex(of: self.grabbitDocument.textFontName) {
                self.textFontPopup.selectItem(at: idx)
            }
            self.textFontSizeSlider.doubleValue      = Double(self.grabbitDocument.textFontSize)
            self.textFontSizeLabel.stringValue        = fmt(self.grabbitDocument.textFontSize)
            self.textFontColorWell.color              = self.grabbitDocument.textFontColor
            self.textOutlineColorWell.color           = self.grabbitDocument.textOutlineColor
            self.textOutlineWeightSlider.doubleValue  = Double(self.grabbitDocument.textOutlineWeight)
            self.textOutlineWeightLabel.stringValue   = fmt(self.grabbitDocument.textOutlineWeight)
        }

        // Document callbacks → redraw overlay / refresh image view.
        document.onAnnotationsChanged = { [weak self] in
            self?.annotationOverlay.needsDisplay = true
        }

        // Overlay selection callback → sync toolbar + sidebar to the selected type.
        annotationOverlay.onSelectionChanged = { [weak self] tool in
            guard let self else { return }
            self.syncToolbarState(to: tool)
        }
        document.onImageChanged = { [weak self] in
            guard let self else { return }
            self.captureView.image = self.grabbitDocument.currentImage
            self.refreshBaseImage()
            self.refreshShadow()
            self.annotationOverlay.needsDisplay = true
            if self.grabbitDocument.hasImage {
                self.applyActiveState()
            }
        }

        // ── Crop overlay wiring ──────────────────────────────────────────────────
        co.imageDisplayRectProvider = { [weak self] in
            guard let iv = self?.captureView, let img = iv.image else { return .zero }
            return Self.imageDisplayRect(for: img, in: iv)
        }
        co.onCropConfirmed = { [weak self] normRect in self?.applyCrop(normRect: normRect) }
        co.onCropCancelled = { [weak self] in self?.deactivateCropTool() }

        // ── OCR overlay wiring ───────────────────────────────────────────────────
        annotationOverlay.onOCRRegionSelected = { [weak self] normRect in
            self?.performOCR(normRect: normRect)
        }

        // ── Title-bar Save button ────────────────────────────────────────────────
        let saveBtn = NSButton(title: "Save As…", target: self, action: #selector(saveAs(_:)))
        saveBtn.bezelStyle = .rounded; saveBtn.controlSize = .small; saveBtn.sizeToFit()
        let acc = NSTitlebarAccessoryViewController()
        acc.view = saveBtn; acc.layoutAttribute = .right
        win.addTitlebarAccessoryViewController(acc)

        // ── Empty-state placeholder ──────────────────────────────────────────────
        let ph = NSTextField(labelWithString: "Use File › New from Clipboard to open an image")
        ph.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        ph.textColor = NSColor.tertiaryLabelColor
        ph.alignment = .center
        ph.translatesAutoresizingMaskIntoConstraints = false
        ph.isHidden = true
        zoomDoc.addSubview(ph)
        NSLayoutConstraint.activate([
            ph.centerXAnchor.constraint(equalTo: zoomDoc.centerXAnchor),
            ph.centerYAnchor.constraint(equalTo: zoomDoc.centerYAnchor),
        ])
        placeholderLabel = ph

        refreshBaseImage()
        refreshShadow()

        if !document.hasImage { applyEmptyState() }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tool actions

    @objc private func toggleArrowTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .arrow)
            annotationOverlay.activeTool = .arrow
            window?.makeFirstResponder(annotationOverlay)
        } else {
            syncToolbarState(to: .none)
            annotationOverlay.activeTool = .none
        }
    }

    @objc private func toggleTextTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .text)
            annotationOverlay.activeTool = .text
            window?.makeFirstResponder(annotationOverlay)
        } else {
            syncToolbarState(to: .none)
            annotationOverlay.activeTool = .none
        }
    }

    @objc private func toggleShapeTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .shape)
            annotationOverlay.activeTool = .shape
            window?.makeFirstResponder(annotationOverlay)
        } else {
            syncToolbarState(to: .none)
            annotationOverlay.activeTool = .none
        }
    }

    @objc private func toggleBlurTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .blur)
            annotationOverlay.activeTool = .blur
            window?.makeFirstResponder(annotationOverlay)
        } else {
            syncToolbarState(to: .none)
            annotationOverlay.activeTool = .none
        }
    }

    @objc private func toggleHighlightTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .highlight)
            annotationOverlay.activeTool = .highlight
            window?.makeFirstResponder(annotationOverlay)
        } else {
            syncToolbarState(to: .none)
            annotationOverlay.activeTool = .none
        }
    }

    @objc private func toggleCropTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .none)   // crop has no annotation tool equivalent
            cropToolButton.state = .on    // keep crop button highlighted manually
            toolMode = .crop
            annotationOverlay.activeTool = .none
            cropOverlay.isHidden = false; cropOverlay.reset()
            window?.makeFirstResponder(cropOverlay)
        } else { deactivateCropTool() }
        sidebar.setToolMode(toolMode)
    }

    /// Single source of truth for toolbar button states + toolMode + sidebar.
    /// Pass `.none` to deactivate all tools.
    private func syncToolbarState(to tool: AnnotationTool) {
        arrowToolButton.state     = tool == .arrow     ? .on : .off
        textToolButton.state      = tool == .text      ? .on : .off
        shapeToolButton.state     = tool == .shape     ? .on : .off
        blurToolButton.state      = tool == .blur      ? .on : .off
        highlightToolButton.state = tool == .highlight ? .on : .off
        ocrToolButton.state       = tool == .ocr       ? .on : .off
        switch tool {
        case .arrow:     toolMode = .arrow
        case .text:      toolMode = .text
        case .shape:     toolMode = .shape
        case .blur:      toolMode = .blur
        case .highlight: toolMode = .highlight
        case .ocr:       toolMode = .ocr
        case .none:      toolMode = .none
        }
        sidebar.setToolMode(toolMode)
    }

    private func deactivateCropTool() {
        cropToolButton.state = .off
        cropOverlay.isHidden = true; cropOverlay.reset()
        syncToolbarState(to: .none)
    }

    // MARK: - OCR tool

    @objc private func toggleOCRTool(_ sender: NSButton) {
        if sender.state == .on {
            syncToolbarState(to: .ocr)
            annotationOverlay.activeTool = .ocr
            window?.makeFirstResponder(annotationOverlay)
        } else {
            syncToolbarState(to: .none)
            annotationOverlay.activeTool = .none
        }
    }

    private func performOCR(normRect: CGRect) {
        let img = grabbitDocument.currentImage

        guard let cgFull = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        // Use the actual CGImage pixel dimensions — these may differ from img.size
        // on Retina displays (e.g. img.size = 500×300 but cgImage = 1000×600).
        let cgW = CGFloat(cgFull.width)
        let cgH = CGFloat(cgFull.height)

        // normRect uses the overlay's coordinate convention: y=0 at the BOTTOM of
        // the image. CGImage.cropping(to:) uses y=0 at the TOP. Flip the Y axis.
        let pixelRect = CGRect(
            x:      normRect.origin.x * cgW,
            y:      (1.0 - normRect.origin.y - normRect.height) * cgH,
            width:  normRect.width  * cgW,
            height: normRect.height * cgH
        ).integral

        guard pixelRect.width > 1, pixelRect.height > 1,
              let cgCropped = cgFull.cropping(to: pixelRect)
        else { return }

        // Run Vision on a background thread so the UI stays responsive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgCropped, options: [:])
            var extractedText = ""
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                extractedText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
            } catch {
                NSLog("Grabbit: OCR failed: \(error)")
            }

            DispatchQueue.main.async {
                self?.showOCRResult(extractedText)
            }
        }
    }

    private func showOCRResult(_ text: String) {
        guard let win = window else { return }

        // ── Sheet window ────────────────────────────────────────────────────────
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        sheet.title = "Extracted Text"

        let content = sheet.contentView!

        // ── Scrollable, editable text area ───────────────────────────────────────
        // NSTextView.scrollableTextView() returns a correctly wired scroll+text pair.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable      = true
        textView.isSelectable    = true
        textView.isRichText      = false
        textView.font            = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor       = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.string = text.isEmpty ? "(No text detected)" : text

        // ── Buttons ──────────────────────────────────────────────────────────────
        let copyBtn = NSButton(title: "Copy", target: nil, action: nil)
        copyBtn.bezelStyle = .rounded
        copyBtn.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = NSButton(title: "Close", target: nil, action: nil)
        closeBtn.bezelStyle    = .rounded
        closeBtn.keyEquivalent = "\u{1b}"
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnRow = NSStackView(views: [copyBtn, closeBtn])
        btnRow.orientation = .horizontal; btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scrollView)
        content.addSubview(btnRow)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: btnRow.topAnchor, constant: -12),
            btnRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            btnRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])

        // ── Button actions ───────────────────────────────────────────────────────
        copyBtn.target = self
        copyBtn.action = #selector(copyOCRText(_:))
        closeBtn.target = self
        closeBtn.action = #selector(dismissSheet(_:))

        // Stash the text view so the copy handler can read it.
        objc_setAssociatedObject(sheet, &OCRKeys.textView, textView, .OBJC_ASSOCIATION_RETAIN)

        win.beginSheet(sheet)
    }

    @objc private func copyOCRText(_ sender: Any?) {
        guard let sheet = window?.attachedSheet else { return }
        let textView = objc_getAssociatedObject(sheet, &OCRKeys.textView) as? NSTextView
        let str = textView?.string ?? ""
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(str, forType: .string)
    }

    // MARK: - Resize tool

    @objc private func resizeToolClicked(_ sender: NSButton) {
        // Resize is a momentary action, not a toggle — reset button state immediately.
        sender.state = .off
        showResizeDialog()
    }

    /// Hard upper bound on either dimension. 8192 × 8192 @ 4 bytes = 256 MB,
    /// which is already very large. Going beyond this risks OOM crashes.
    private static let resizeMaxPx: Int = 8192

    private func showResizeDialog() {
        guard let win = window else { return }
        let img = grabbitDocument.currentImage
        // Use the actual pixel dimensions from the CGImage backing, not NSImage.size
        // which is in points and would show half the real pixel count on Retina displays.
        let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let origW = cgImg.map { CGFloat($0.width)  } ?? img.size.width
        let origH = cgImg.map { CGFloat($0.height) } ?? img.size.height
        let maxPx = Self.resizeMaxPx

        // ── Sheet window ────────────────────────────────────────────────────────
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 185),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        sheet.title = "Resize Image"

        let content = sheet.contentView!

        // ── Labels ──────────────────────────────────────────────────────────────
        let wLabel = NSTextField(labelWithString: "Width:")
        wLabel.alignment = .right
        wLabel.translatesAutoresizingMaskIntoConstraints = false

        let hLabel = NSTextField(labelWithString: "Height:")
        hLabel.alignment = .right
        hLabel.translatesAutoresizingMaskIntoConstraints = false

        let pxLabel1 = NSTextField(labelWithString: "px")
        pxLabel1.translatesAutoresizingMaskIntoConstraints = false
        let pxLabel2 = NSTextField(labelWithString: "px")
        pxLabel2.translatesAutoresizingMaskIntoConstraints = false

        // ── Text fields ─────────────────────────────────────────────────────────
        let wField = NSTextField()
        wField.stringValue = "\(Int(origW))"
        wField.alignment = .right
        wField.translatesAutoresizingMaskIntoConstraints = false
        wField.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let hField = NSTextField()
        hField.stringValue = "\(Int(origH))"
        hField.alignment = .right
        hField.translatesAutoresizingMaskIntoConstraints = false
        hField.widthAnchor.constraint(equalToConstant: 72).isActive = true

        // ── Lock button ─────────────────────────────────────────────────────────
        let lockBtn = NSButton(checkboxWithTitle: "Lock aspect ratio", target: nil, action: nil)
        lockBtn.state = .on
        lockBtn.translatesAutoresizingMaskIntoConstraints = false

        // ── Warning label (hidden until a value exceeds the cap) ─────────────────
        let warningLabel = NSTextField(labelWithString: "Max \(maxPx) px per side.")
        warningLabel.textColor = .systemOrange
        warningLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.isHidden = true

        // ── Action buttons ───────────────────────────────────────────────────────
        let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false

        let applyBtn = NSButton(title: "Apply", target: nil, action: nil)
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        applyBtn.translatesAutoresizingMaskIntoConstraints = false

        // ── Layout ───────────────────────────────────────────────────────────────
        let wRow = NSStackView(views: [wLabel, wField, pxLabel1])
        wRow.orientation = .horizontal; wRow.spacing = 6; wRow.alignment = .centerY
        wRow.translatesAutoresizingMaskIntoConstraints = false

        let hRow = NSStackView(views: [hLabel, hField, pxLabel2])
        hRow.orientation = .horizontal; hRow.spacing = 6; hRow.alignment = .centerY
        hRow.translatesAutoresizingMaskIntoConstraints = false

        let btnRow = NSStackView(views: [cancelBtn, applyBtn])
        btnRow.orientation = .horizontal; btnRow.spacing = 8
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        // Align the two row labels to the same width.
        wLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        hLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let stack = NSStackView(views: [wRow, hRow, lockBtn, warningLabel, btnRow])
        stack.orientation = .vertical; stack.spacing = 10; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            btnRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        // ── Validation helper ────────────────────────────────────────────────────
        // Shows the warning and updates the Apply button title if either value
        // exceeds the cap. Called after every field change.
        let validate = {
            let w = Int(wField.stringValue) ?? 0
            let h = Int(hField.stringValue) ?? 0
            let over = w > maxPx || h > maxPx
            warningLabel.isHidden = !over
            applyBtn.title = over ? "Apply (clamped)" : "Apply"
        }

        // ── Aspect-ratio enforcement ─────────────────────────────────────────────
        var updatingFields = false

        let wDelegate = ResizeFieldDelegate { [weak lockBtn] newVal in
            guard !updatingFields, lockBtn?.state == .on, origW > 0 else {
                validate(); return
            }
            updatingFields = true
            let ratio = origH / origW
            hField.stringValue = "\(max(1, Int(round(newVal * ratio))))"
            updatingFields = false
            validate()
        }
        let hDelegate = ResizeFieldDelegate { [weak lockBtn] newVal in
            guard !updatingFields, lockBtn?.state == .on, origH > 0 else {
                validate(); return
            }
            updatingFields = true
            let ratio = origW / origH
            wField.stringValue = "\(max(1, Int(round(newVal * ratio))))"
            updatingFields = false
            validate()
        }
        wField.delegate = wDelegate
        hField.delegate = hDelegate

        // ── Button actions ───────────────────────────────────────────────────────
        cancelBtn.target = self
        cancelBtn.action = #selector(dismissSheet(_:))

        applyBtn.target = self
        applyBtn.action = #selector(applyResizeFromSheet(_:))

        // Stash context on the sheet so the apply handler can read it.
        objc_setAssociatedObject(sheet, &ResizeKeys.wField,    wField,    .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &ResizeKeys.hField,    hField,    .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &ResizeKeys.wDelegate, wDelegate, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(sheet, &ResizeKeys.hDelegate, hDelegate, .OBJC_ASSOCIATION_RETAIN)

        win.beginSheet(sheet)
    }

    @objc private func dismissSheet(_ sender: Any?) {
        guard let sheet = window?.attachedSheet else { return }
        window?.endSheet(sheet, returnCode: .cancel)
    }

    @objc private func applyResizeFromSheet(_ sender: Any?) {
        guard let sheet = window?.attachedSheet else { return }
        let wField = objc_getAssociatedObject(sheet, &ResizeKeys.wField) as? NSTextField
        let hField = objc_getAssociatedObject(sheet, &ResizeKeys.hField) as? NSTextField

        // Parse and hard-clamp to the safe maximum before doing any work.
        let maxPx = Self.resizeMaxPx
        let rawW = Int(wField?.stringValue ?? "0") ?? 0
        let rawH = Int(hField?.stringValue ?? "0") ?? 0
        let newW = CGFloat(min(maxPx, max(1, rawW)))
        let newH = CGFloat(min(maxPx, max(1, rawH)))

        window?.endSheet(sheet, returnCode: .OK)

        let img = grabbitDocument.currentImage
        guard let srcCG = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        // Compare against actual pixel dimensions, not point-based NSImage.size.
        guard newW != CGFloat(srcCG.width) || newH != CGFloat(srcCG.height) else { return }

        // Draw into a CGContext at exactly the requested pixel dimensions.
        guard let ctx = CGContext(
                data: nil,
                width: Int(newW), height: Int(newH),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        ctx.interpolationQuality = .high
        ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let resizedCG = ctx.makeImage() else { return }
        // Set NSImage.size = pixel dimensions so the rest of the pipeline treats
        // size as pixels (1 pt = 1 px), consistent with how we write to disk.
        let resized = NSImage(cgImage: resizedCG, size: NSSize(width: newW, height: newH))

        grabbitDocument.applyResize(to: resized)
    }

    private func applyCrop(normRect: CGRect) {
        let img = grabbitDocument.currentImage
        // Use actual CGImage pixel dimensions, not NSImage.size (which is in points
        // and would be half the real pixel count on Retina displays).
        guard let srcCG = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            deactivateCropTool(); return
        }
        let imgW = CGFloat(srcCG.width)
        let imgH = CGFloat(srcCG.height)
        let pixelRect = CGRect(
            x: normRect.origin.x * imgW,
            y: normRect.origin.y * imgH,
            width: normRect.size.width  * imgW,
            height: normRect.size.height * imgH).integral
        guard pixelRect.width > 1, pixelRect.height > 1 else { deactivateCropTool(); return }

        // Crop directly from the CGImage (CGImage origin is bottom-left).
        let srcRect = CGRect(
            x: pixelRect.minX,
            y: imgH - pixelRect.maxY,
            width: pixelRect.width,
            height: pixelRect.height)
        guard let croppedCG = srcCG.cropping(to: srcRect) else { deactivateCropTool(); return }
        // Set NSImage.size = pixel dimensions so the pipeline treats size as pixels.
        let cropped = NSImage(cgImage: croppedCG, size: pixelRect.size)

        grabbitDocument.applyCrop(to: cropped)
        deactivateCropTool()
    }

    // MARK: - Zoom

    @objc private func zoomIn() {
        let newMag = min(8.0, zoomScroll.magnification * 1.25)
        let center = CGPoint(x: zoomScroll.documentView!.frame.midX,
                             y: zoomScroll.documentView!.frame.midY)
        zoomScroll.setMagnification(newMag, centeredAt: center); updateZoomLabel()
    }

    @objc private func zoomOut() {
        let newMag = max(0.1, zoomScroll.magnification / 1.25)
        let center = CGPoint(x: zoomScroll.documentView!.frame.midX,
                             y: zoomScroll.documentView!.frame.midY)
        zoomScroll.setMagnification(newMag, centeredAt: center); updateZoomLabel()
    }

    @objc private func zoomDidEnd(_ note: Notification) { updateZoomLabel() }

    private func updateZoomLabel() {
        zoomLabel.stringValue = "\(Int(round(zoomScroll.magnification * 100)))%"
    }

    // MARK: - Sidebar control actions

    @objc private func borderToggleChanged(_ btn: NSButton) {
        grabbitDocument.borderEnabled = btn.state == .on
        refreshBaseImage(); grabbitDocument.savePrefs()
    }

    @objc private func shadowToggleChanged(_ btn: NSButton) {
        grabbitDocument.shadowEnabled = btn.state == .on
        refreshShadow(); grabbitDocument.savePrefs()
    }

    @objc private func borderWeightChanged(_ s: NSSlider) {
        grabbitDocument.borderWeight = CGFloat(s.doubleValue)
        borderWeightLabel.stringValue = fmt(grabbitDocument.borderWeight)
        refreshBaseImage(); grabbitDocument.savePrefs()
    }

    @objc private func shadowXChanged(_ s: NSSlider) {
        grabbitDocument.shadowOffsetX = CGFloat(s.doubleValue)
        shadowXLabel.stringValue = fmt(grabbitDocument.shadowOffsetX)
        refreshShadow(); grabbitDocument.savePrefs()
    }

    @objc private func shadowYChanged(_ s: NSSlider) {
        grabbitDocument.shadowOffsetY = CGFloat(s.doubleValue)
        shadowYLabel.stringValue = fmt(grabbitDocument.shadowOffsetY)
        refreshShadow(); grabbitDocument.savePrefs()
    }

    @objc private func shadowBlurChanged(_ s: NSSlider) {
        grabbitDocument.shadowBlur = CGFloat(s.doubleValue)
        shadowBlurLabel.stringValue = fmt(grabbitDocument.shadowBlur)
        refreshShadow(); grabbitDocument.savePrefs()
    }

    @objc private func shadowOpacityChanged(_ s: NSSlider) {
        grabbitDocument.shadowOpacity = CGFloat(s.doubleValue) / 100
        shadowOpacityLabel.stringValue = fmtPct(grabbitDocument.shadowOpacity)
        refreshShadow(); grabbitDocument.savePrefs()
    }

    @objc private func arrowWeightChanged(_ s: NSSlider) {
        grabbitDocument.arrowWeight = max(1, CGFloat(s.doubleValue))
        annotationOverlay.currentWeight = grabbitDocument.arrowWeight
        annotationOverlay.updateSelected(weight: grabbitDocument.arrowWeight)
        arrowWeightLabel.stringValue = fmt(grabbitDocument.arrowWeight)
        grabbitDocument.savePrefs()
    }

    @objc private func textFontChanged(_ popup: NSPopUpButton) {
        let fonts = ["Helvetica-Bold", "Helvetica", "Arial-BoldMT", "ArialMT",
                     "Courier-Bold", "Courier", "TimesNewRomanPS-BoldMT",
                     "TimesNewRomanPSMT", "Georgia-Bold", "Georgia",
                     "Menlo-Bold", "Menlo-Regular", "Monaco"]
        guard popup.indexOfSelectedItem >= 0, popup.indexOfSelectedItem < fonts.count else { return }
        grabbitDocument.textFontName = fonts[popup.indexOfSelectedItem]
        annotationOverlay.currentFontName = grabbitDocument.textFontName
        annotationOverlay.updateSelectedText(fontName: grabbitDocument.textFontName)
        grabbitDocument.savePrefs()
    }

    @objc private func textFontSizeChanged(_ s: NSSlider) {
        grabbitDocument.textFontSize = CGFloat(s.doubleValue)
        textFontSizeLabel.stringValue = fmt(grabbitDocument.textFontSize)
        annotationOverlay.currentFontSize = grabbitDocument.textFontSize
        annotationOverlay.updateSelectedText(fontSize: grabbitDocument.textFontSize)
        grabbitDocument.savePrefs()
    }

    @objc private func textOutlineWeightChanged(_ s: NSSlider) {
        grabbitDocument.textOutlineWeight = CGFloat(s.doubleValue)
        textOutlineWeightLabel.stringValue = fmt(grabbitDocument.textOutlineWeight)
        annotationOverlay.currentOutlineWeight = grabbitDocument.textOutlineWeight
        annotationOverlay.updateSelectedText(outlineWeight: grabbitDocument.textOutlineWeight)
        grabbitDocument.savePrefs()
    }

    @objc private func shapeTypeChanged(_ popup: NSPopUpButton) {
        let types: [ShapeType] = [.rectangle, .circle, .roundedRectangle]
        guard popup.indexOfSelectedItem >= 0, popup.indexOfSelectedItem < types.count else { return }
        grabbitDocument.shapeType = types[popup.indexOfSelectedItem]
        annotationOverlay.currentShapeType = grabbitDocument.shapeType
        annotationOverlay.updateSelectedShape(shapeType: grabbitDocument.shapeType)
        grabbitDocument.savePrefs()
    }

    @objc private func shapeBorderWeightChanged(_ s: NSSlider) {
        grabbitDocument.shapeBorderWeight = CGFloat(s.doubleValue)
        shapeBorderWeightLabel.stringValue = fmt(grabbitDocument.shapeBorderWeight)
        annotationOverlay.currentBorderWeight = grabbitDocument.shapeBorderWeight
        annotationOverlay.updateSelectedShape(borderWeight: grabbitDocument.shapeBorderWeight)
        grabbitDocument.savePrefs()
    }

    @objc private func blurIntensityChanged(_ s: NSSlider) {
        let intensity = CGFloat(s.doubleValue)
        blurIntensityLabel.stringValue = "\(Int(intensity))"
        annotationOverlay.currentBlurIntensity = intensity
        annotationOverlay.updateSelectedBlur(intensity: intensity)
        annotationOverlay.needsDisplay = true
    }

    @objc private func blurStyleChanged(_ popup: NSPopUpButton) {
        let style: BlurStyle = popup.indexOfSelectedItem == 0 ? .blur : .pixelate
        annotationOverlay.currentBlurStyle = style
        annotationOverlay.updateSelectedBlur(style: style)
        annotationOverlay.needsDisplay = true
    }

    @objc private func highlightOpacityChanged(_ s: NSSlider) {
        grabbitDocument.highlightOpacity = CGFloat(s.doubleValue) / 100
        highlightOpacityLabel.stringValue = fmtPct(grabbitDocument.highlightOpacity)
        annotationOverlay.currentHighlightOpacity = grabbitDocument.highlightOpacity
        annotationOverlay.updateSelectedHighlight(opacity: grabbitDocument.highlightOpacity)
        annotationOverlay.needsDisplay = true
    }

    @objc private func colorPanelChanged() {
        if borderColorWell.isActive {
            grabbitDocument.borderColor = borderColorWell.color; refreshBaseImage()
        } else if shadowColorWell.isActive {
            grabbitDocument.shadowColor = shadowColorWell.color; refreshShadow()
        } else if arrowColorWell.isActive {
            grabbitDocument.arrowColor = arrowColorWell.color
            annotationOverlay.currentColor = grabbitDocument.arrowColor
            annotationOverlay.updateSelected(color: grabbitDocument.arrowColor)
        } else if textFontColorWell.isActive {
            grabbitDocument.textFontColor = textFontColorWell.color
            annotationOverlay.currentFontColor = grabbitDocument.textFontColor
            annotationOverlay.updateSelectedText(fontColor: grabbitDocument.textFontColor)
        } else if textOutlineColorWell.isActive {
            grabbitDocument.textOutlineColor = textOutlineColorWell.color
            annotationOverlay.currentOutlineColor = grabbitDocument.textOutlineColor
            annotationOverlay.updateSelectedText(outlineColor: grabbitDocument.textOutlineColor)
        } else if shapeBorderColorWell.isActive {
            grabbitDocument.shapeBorderColor = shapeBorderColorWell.color
            annotationOverlay.currentBorderColor = grabbitDocument.shapeBorderColor
            annotationOverlay.updateSelectedShape(borderColor: grabbitDocument.shapeBorderColor)
        } else if shapeFillColorWell.isActive {
            grabbitDocument.shapeFillColor = shapeFillColorWell.color
            annotationOverlay.currentFillColor = grabbitDocument.shapeFillColor
            annotationOverlay.updateSelectedShape(fillColor: grabbitDocument.shapeFillColor)
        } else if highlightColorWell.isActive {
            grabbitDocument.highlightColor = highlightColorWell.color
            annotationOverlay.currentHighlightColor = grabbitDocument.highlightColor
            annotationOverlay.updateSelectedHighlight(color: grabbitDocument.highlightColor)
        }
        grabbitDocument.savePrefs()
    }

    // MARK: - Save / Copy

    @objc func copyImage(_ sender: Any?) { copyToClipboard() }

    @objc func saveAs(_ sender: Any?) {
        annotationOverlay.finalizeEditing()
        grabbitDocument.runModalSavePanel(for: .saveAsOperation,
                                          delegate: nil, didSave: nil, contextInfo: nil)
    }

    @objc func save(_ sender: Any?) {
        annotationOverlay.finalizeEditing()
        if grabbitDocument.fileURL != nil {
            grabbitDocument.save(self)
        } else {
            saveAs(sender)
        }
    }

    private func copyToClipboard() {
        annotationOverlay.finalizeEditing()
        let displayWidth = captureView.bounds.width
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([grabbitDocument.rendered(displayWidth: displayWidth)])
    }

    // MARK: - Refresh

    func refreshBaseImage() {
        let doc = grabbitDocument
        captureView.image = (doc.borderEnabled && doc.borderWeight > 0)
            ? doc.withBorder(doc.currentImage)
            : doc.currentImage
        annotationOverlay.needsDisplay = true
    }

    func refreshShadow() {
        let doc = grabbitDocument
        captureView.wantsLayer = true
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = false
        guard let layer = captureView.layer else { return }
        layer.masksToBounds = false
        layer.shadowOpacity = doc.shadowEnabled ? Float(doc.shadowOpacity) : 0
        layer.shadowRadius  = doc.shadowBlur
        layer.shadowOffset  = CGSize(width: doc.shadowOffsetX, height: doc.shadowOffsetY)
        layer.shadowColor   = doc.shadowColor.cgColor
    }

    // MARK: - Empty state / load image

    private func applyEmptyState() {
        captureView.image = nil
        annotationOverlay.isHidden = true
        cropOverlay.isHidden = true
        placeholderLabel.isHidden = false
        arrowToolButton.isEnabled     = false
        textToolButton.isEnabled      = false
        shapeToolButton.isEnabled     = false
        blurToolButton.isEnabled      = false
        highlightToolButton.isEnabled = false
        cropToolButton.isEnabled      = false
        resizeToolButton.isEnabled    = false
        ocrToolButton.isEnabled       = false
    }

    private func applyActiveState() {
        annotationOverlay.isHidden = false
        placeholderLabel.isHidden  = true
        arrowToolButton.isEnabled     = true
        textToolButton.isEnabled      = true
        shapeToolButton.isEnabled     = true
        blurToolButton.isEnabled      = true
        highlightToolButton.isEnabled = true
        cropToolButton.isEnabled      = true
        resizeToolButton.isEnabled    = true
        ocrToolButton.isEnabled       = true
    }

    /// Replace the current image (used by "Open…" and "New from Clipboard").
    func replaceImage(_ image: NSImage, completion: ((Bool) -> Void)? = nil) {
        guard grabbitDocument.isDirty,
              let win = window else {
            grabbitDocument.loadImage(image)
            completion?(true)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save changes before opening a new image?"
        alert.informativeText = "Your current image has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: win) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.saveAs(nil)
                self.grabbitDocument.loadImage(image)
                completion?(true)
            case .alertSecondButtonReturn:
                self.grabbitDocument.loadImage(image)
                completion?(true)
            default:
                completion?(false)
            }
        }
    }

    /// Close the current image, returning the editor to the empty state.
    @objc func closeImage(_ sender: Any?) {
        guard grabbitDocument.hasImage else { return }

        let doClose = { [weak self] in
            guard let self else { return }
            self.grabbitDocument.loadImage(NSImage(size: NSSize(width: 1, height: 1)))
            self.applyEmptyState()
        }

        guard grabbitDocument.isDirty, let win = window else {
            doClose(); return
        }

        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "Your current image has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: win) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:  self.save(nil); doClose()
            case .alertSecondButtonReturn: doClose()
            default: break
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let m = toolShortcutMonitor { NSEvent.removeMonitor(m); toolShortcutMonitor = nil }
        NotificationCenter.default.removeObserver(self,
            name: NSColorPanel.colorDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self,
            name: NSScrollView.didEndLiveMagnifyNotification, object: zoomScroll)
        // When the last editor closes, go back to accessory (menu-bar-only) mode.
        if NSDocumentController.shared.documents.filter({ $0 !== grabbitDocument }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Menu tool actions (routed via responder chain from Tools menu)

    @objc func activateCropTool(_ sender: Any?)      { guard cropToolButton.isEnabled      else { return }; cropToolButton.performClick(nil) }
    @objc func activateResizeTool(_ sender: Any?)    { guard resizeToolButton.isEnabled    else { return }; resizeToolButton.performClick(nil) }
    @objc func activateOCRTool(_ sender: Any?)       { guard ocrToolButton.isEnabled       else { return }; ocrToolButton.performClick(nil) }
    @objc func activateArrowTool(_ sender: Any?)     { guard arrowToolButton.isEnabled     else { return }; arrowToolButton.performClick(nil) }
    @objc func activateTextTool(_ sender: Any?)      { guard textToolButton.isEnabled      else { return }; textToolButton.performClick(nil) }
    @objc func activateShapeTool(_ sender: Any?)     { guard shapeToolButton.isEnabled     else { return }; shapeToolButton.performClick(nil) }
    @objc func activateBlurTool(_ sender: Any?)      { guard blurToolButton.isEnabled      else { return }; blurToolButton.performClick(nil) }
    @objc func activateHighlightTool(_ sender: Any?) { guard highlightToolButton.isEnabled else { return }; highlightToolButton.performClick(nil) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let toolSelectors: [Selector] = [
            #selector(activateCropTool(_:)),   #selector(activateResizeTool(_:)),
            #selector(activateOCRTool(_:)),    #selector(activateArrowTool(_:)),
            #selector(activateTextTool(_:)),   #selector(activateShapeTool(_:)),
            #selector(activateBlurTool(_:)),   #selector(activateHighlightTool(_:)),
        ]
        if let action = menuItem.action, toolSelectors.contains(action) {
            return grabbitDocument.hasImage
        }
        return true
    }

    // MARK: - Tool keyboard shortcuts

    func updateToolShortcuts(_ shortcuts: ToolShortcutsConfig) {
        toolShortcuts = shortcuts
    }

    private func setupToolShortcutMonitor() {
        toolShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.window?.isKeyWindow == true,
                  self.window?.attachedSheet == nil else { return event }
            let fr = self.window?.firstResponder
            if fr is NSTextView || fr is NSTextField { return event }
            if self.handleToolShortcut(event) { return nil }
            return event
        }
    }

    private func handleToolShortcut(_ event: NSEvent) -> Bool {
        let mods = carbonModifiers(from: event.modifierFlags)
        let kc   = UInt32(event.keyCode)
        func matches(_ cfg: HotkeyConfig) -> Bool { cfg.keyCode == kc && cfg.modifiers == mods }

        if matches(toolShortcuts.crop),      cropToolButton.isEnabled      { cropToolButton.performClick(nil);      return true }
        if matches(toolShortcuts.resize),    resizeToolButton.isEnabled    { resizeToolButton.performClick(nil);    return true }
        if matches(toolShortcuts.ocr),       ocrToolButton.isEnabled       { ocrToolButton.performClick(nil);       return true }
        if matches(toolShortcuts.arrow),     arrowToolButton.isEnabled     { arrowToolButton.performClick(nil);     return true }
        if matches(toolShortcuts.text),      textToolButton.isEnabled      { textToolButton.performClick(nil);      return true }
        if matches(toolShortcuts.shape),     shapeToolButton.isEnabled     { shapeToolButton.performClick(nil);     return true }
        if matches(toolShortcuts.blur),      blurToolButton.isEnabled      { blurToolButton.performClick(nil);      return true }
        if matches(toolShortcuts.highlight), highlightToolButton.isEnabled { highlightToolButton.performClick(nil); return true }
        return false
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    // MARK: - Utility

    static func imageDisplayRect(for image: NSImage, in view: NSView) -> CGRect {
        let vw = view.bounds.width, vh = view.bounds.height
        let iw = image.size.width,  ih = image.size.height
        let scale = min(1.0, min(vw / iw, vh / ih))
        let sw = iw * scale, sh = ih * scale
        return CGRect(x: (vw - sw) / 2, y: (vh - sh) / 2, width: sw, height: sh)
    }
}

// MARK: - Resize helpers

/// Keys for objc_setAssociatedObject used to pass context to the sheet handlers.
private enum ResizeKeys {
    static var wField:    UInt8 = 0
    static var hField:    UInt8 = 1
    static var wDelegate: UInt8 = 2
    static var hDelegate: UInt8 = 3
}

/// NSTextField delegate that fires a callback whenever the user edits the value,
/// used to keep width/height in sync when aspect ratio is locked.
private class ResizeFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onChange: (CGFloat) -> Void
    init(_ onChange: @escaping (CGFloat) -> Void) { self.onChange = onChange }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let val = Double(field.stringValue) else { return }
        onChange(CGFloat(val))
    }
}

// MARK: - OCR associated-object keys

private enum OCRKeys {
    static var textView: UInt8 = 0
}

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - EditorWindowController

class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openEditors: [EditorWindowController] = []

    // MARK: State

    let originalImage: NSImage
    var currentImage: NSImage          // tracks the working image (after crops)
    var borderWeight:      CGFloat
    var borderColor:       NSColor
    var shadowOffsetX:     CGFloat
    var shadowOffsetY:     CGFloat
    var shadowBlur:        CGFloat
    var shadowColor:       NSColor
    var shadowOpacity:     CGFloat
    var arrowWeight:       CGFloat
    var arrowColor:        NSColor
    var borderEnabled:     Bool
    var shadowEnabled:     Bool
    var textFontName:      String
    var textFontSize:      CGFloat
    var textFontColor:     NSColor
    var textOutlineColor:  NSColor
    var textOutlineWeight: CGFloat
    private var toolMode: ToolMode = .none

    // Shape state
    private var shapeType:        ShapeType = .rectangle
    var shapeBorderWeight: CGFloat = 2
    var shapeBorderColor: NSColor = .black
    var shapeFillColor:   NSColor = .clear

    // MARK: Views

    var captureView:             NSImageView!
    var annotationOverlay:       AnnotationOverlay!
    private var canvas:          CanvasView!
    private var sidebar:         TabbedEditorSidebar!
    private var arrowToolButton: NSButton!
    private var textToolButton:  NSButton!
    private var shapeToolButton: NSButton!
    private var zoomScroll:      NSScrollView!
    private var zoomLabel:       NSTextField!
    private var cropToolButton:  NSButton!
    var cropOverlay:             CropOverlayView!

    private var borderWeightSlider:      NSSlider!;   private var borderWeightLabel:      NSTextField!
    private var borderColorWell:         NSColorWell!
    private var shadowXSlider:           NSSlider!;   private var shadowXLabel:           NSTextField!
    private var shadowYSlider:           NSSlider!;   private var shadowYLabel:           NSTextField!
    private var shadowBlurSlider:        NSSlider!;   private var shadowBlurLabel:        NSTextField!
    private var shadowColorWell:         NSColorWell!
    private var shadowOpacitySlider:     NSSlider!;   private var shadowOpacityLabel:     NSTextField!
    private var borderToggle:            NSButton!
    private var shadowToggle:            NSButton!
    private var arrowWeightSlider:       NSSlider!;   private var arrowWeightLabel:       NSTextField!
    private var arrowColorWell:          NSColorWell!
    private var textFontPopup:           NSPopUpButton!
    private var textFontSizeSlider:      NSSlider!;   private var textFontSizeLabel:      NSTextField!
    private var textFontColorWell:       NSColorWell!
    private var textOutlineColorWell:    NSColorWell!
    private var textOutlineWeightSlider: NSSlider!;   private var textOutlineWeightLabel: NSTextField!
    private var shapeTypePopup:          NSPopUpButton!
    private var shapeBorderWeightSlider: NSSlider!;   private var shapeBorderWeightLabel: NSTextField!
    private var shapeBorderColorWell:    NSColorWell!
    private var shapeFillColorWell:      NSColorWell!

    // MARK: - Show

    static func show(image: NSImage) {
        let c = EditorWindowController(image: image)
        openEditors.append(c)
        // Known macOS bug (FB7743313): setActivationPolicy(.regular) alone doesn't
        // update the menu bar. The only reliable fix is to briefly activate another
        // app then immediately re-activate ourselves, forcing the window server
        // through the full activation path.
        // Finder is always running and is the guaranteed fallback.
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
            c.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Init

    init(image: NSImage) {
        self.originalImage = image
        self.currentImage  = image

        borderWeight       = CGFloat(loadDouble(Prefs.borderWeight,      default: 0))
        borderColor        = loadColor(Prefs.borderColor,                 default: .black)
        shadowOffsetX      = CGFloat(loadDouble(Prefs.shadowX,            default: 5))
        shadowOffsetY      = CGFloat(loadDouble(Prefs.shadowY,            default: -5))
        shadowBlur         = CGFloat(loadDouble(Prefs.shadowBlur,         default: 10))
        shadowColor        = loadColor(Prefs.shadowColor,                 default: .black)
        shadowOpacity      = CGFloat(loadDouble(Prefs.shadowOpacity,      default: 0))
        arrowWeight        = CGFloat(loadDouble(Prefs.arrowWeight,        default: 2))
        arrowColor         = loadColor(Prefs.arrowColor,                  default: .systemRed)
        borderEnabled      = UserDefaults.standard.object(forKey: Prefs.borderEnabled) != nil
                             ? UserDefaults.standard.bool(forKey: Prefs.borderEnabled) : false
        shadowEnabled      = UserDefaults.standard.object(forKey: Prefs.shadowEnabled) != nil
                             ? UserDefaults.standard.bool(forKey: Prefs.shadowEnabled) : false
        textFontName       = loadString(Prefs.textFontName,               default: "Helvetica-Bold")
        textFontSize       = CGFloat(loadDouble(Prefs.textFontSize,       default: 24))
        textFontColor      = loadColor(Prefs.textFontColor,               default: .white)
        textOutlineColor   = loadColor(Prefs.textOutlineColor,            default: .black)
        textOutlineWeight  = CGFloat(loadDouble(Prefs.textOutlineWeight,  default: 2))

        shapeBorderWeight  = CGFloat(loadDouble(Prefs.shapeBorderWeight,  default: 2))
        shapeBorderColor   = loadColor(Prefs.shapeBorderColor,            default: .black)
        shapeFillColor     = loadColor(Prefs.shapeFillColor,              default: .clear)

        // ── Window ──────────────────────────────────────────────────────────────
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        // Open at 70% of the visible screen, capped at 1400×900, and centered.
        let w = min(visible.width  * 0.70, 1400)
        let h = min(visible.height * 0.70,  900)
        let x = visible.minX + (visible.width  - w) / 2
        let y = visible.minY + (visible.height - h) / 2
        let initialFrame = NSRect(x: x, y: y, width: w, height: h)

        let win = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Grabbit"
        win.setFrame(initialFrame, display: false)
        win.minSize = NSSize(width: 600, height: 400)

        // ── Image view + overlay ─────────────────────────────────────────────────
        let iv = NSImageView()
        iv.image = image
        iv.imageScaling = .scaleProportionallyDown
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false

        let ol = AnnotationOverlay()
        ol.translatesAutoresizingMaskIntoConstraints = false
        ol.wantsLayer = true

        // ── Zoom scroll view ─────────────────────────────────────────────────────
        // zoomDoc is the scroll view's document — it sizes itself to the image
        // plus padding. The scroll view centers it when smaller than the viewport.
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
        zs.allowsMagnification    = true
        zs.minMagnification       = 0.1
        zs.maxMagnification       = 8.0
        zs.hasVerticalScroller    = true
        zs.hasHorizontalScroller  = true
        zs.autohidesScrollers     = true
        zs.scrollerStyle          = .overlay
        zs.drawsBackground        = false
        zs.translatesAutoresizingMaskIntoConstraints = false

        // Use a centering clip view so the document is always centered in the
        // viewport when it's smaller than the available space.
        let centerClip = CenteringClipView()
        centerClip.drawsBackground = false
        zs.contentView = centerClip
        zs.documentView = zoomDoc

        // ── Canvas ───────────────────────────────────────────────────────────────
        let cv = CanvasView()
        cv.translatesAutoresizingMaskIntoConstraints = false

        // ── Canvas toolbar ───────────────────────────────────────────────────────
        let arrowBtn = makeToolButton("Arrow")
        let textBtn  = makeToolButton("Text")
        let shapeBtn = makeToolButton("Shape")
        let cropBtn  = makeToolButton("Crop")
        cropBtn.toolTip = "Crop image"

        let toolsStack = NSStackView(views: [cropBtn, arrowBtn, textBtn, shapeBtn])
        toolsStack.orientation = .horizontal
        toolsStack.spacing = 6
        toolsStack.translatesAutoresizingMaskIntoConstraints = false

        let zoomOutBtn = NSButton(title: "−", target: nil, action: nil)
        zoomOutBtn.bezelStyle = .rounded
        zoomOutBtn.controlSize = .small
        zoomOutBtn.translatesAutoresizingMaskIntoConstraints = false

        let zoomInBtn = NSButton(title: "+", target: nil, action: nil)
        zoomInBtn.bezelStyle = .rounded
        zoomInBtn.controlSize = .small
        zoomInBtn.translatesAutoresizingMaskIntoConstraints = false

        let zl = NSTextField(labelWithString: "100%")
        zl.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zl.alignment = .center
        zl.translatesAutoresizingMaskIntoConstraints = false
        zl.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let zoomStack = NSStackView(views: [zoomOutBtn, zl, zoomInBtn])
        zoomStack.orientation = .horizontal
        zoomStack.spacing = 4
        zoomStack.translatesAutoresizingMaskIntoConstraints = false

        // ── Toolbar background strip ─────────────────────────────────────────────
        // A plain NSVisualEffectView gives us the correct system material that
        // adapts to both light and dark mode, keeping buttons legible in either.
        let toolbarBg = NSVisualEffectView()
        toolbarBg.material = .windowBackground
        toolbarBg.blendingMode = .withinWindow
        toolbarBg.state = .active
        toolbarBg.translatesAutoresizingMaskIntoConstraints = false

        // A 1-pt separator at the bottom of the toolbar strip
        let toolbarSep = NSBox()
        toolbarSep.boxType = .custom
        toolbarSep.borderWidth = 0
        toolbarSep.fillColor = NSColor.separatorColor
        toolbarSep.cornerRadius = 0
        toolbarSep.translatesAutoresizingMaskIntoConstraints = false

        let tbH: CGFloat = 44
        cv.addSubview(toolbarBg)
        cv.addSubview(toolbarSep)
        cv.addSubview(zs)
        cv.addSubview(toolsStack)
        cv.addSubview(zoomStack)

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

        let bwSlider = sld(0, 50,  Double(borderWeight));    let bwLabel = vlbl(fmt(borderWeight))
        let bcWell   = well(borderColor)
        let bToggle  = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        bToggle.state = borderEnabled ? .on : .off

        let sxSlider = sld(-50, 50, Double(shadowOffsetX));  let sxLabel = vlbl(fmt(shadowOffsetX))
        let sySlider = sld(-50, 50, Double(shadowOffsetY));  let syLabel = vlbl(fmt(shadowOffsetY))
        let sbSlider = sld(0,   50, Double(shadowBlur));     let sbLabel = vlbl(fmt(shadowBlur))
        let scWell   = well(shadowColor)
        let soSlider = sld(0, 100, Double(shadowOpacity * 100)); let soLabel = vlbl(fmtPct(shadowOpacity))
        let sToggle  = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        sToggle.state = shadowEnabled ? .on : .off

        let awSlider = sld(1, 20, Double(arrowWeight));      let awLabel = vlbl(fmt(arrowWeight))
        let acWell   = well(arrowColor)

        // Text property controls
        let tfPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        tfPopup.controlSize = .small
        tfPopup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let fonts = ["Helvetica-Bold", "Helvetica", "Arial-BoldMT", "ArialMT", "Courier-Bold", "Courier",
                     "TimesNewRomanPS-BoldMT", "TimesNewRomanPSMT", "Georgia-Bold", "Georgia",
                     "Menlo-Bold", "Menlo-Regular", "Monaco"]
        fonts.forEach { tfPopup.addItem(withTitle: $0.replacingOccurrences(of: "-", with: " ")) }
        if let idx = fonts.firstIndex(of: textFontName) {
            tfPopup.selectItem(at: idx)
        }
        let tfSizeSlider  = sld(8, 72, Double(textFontSize));          let tfSizeLabel = vlbl(fmt(textFontSize))
        let tfColorWell   = well(textFontColor)
        let toColorWell   = well(textOutlineColor)
        let toWtSlider    = sld(0, 20, Double(textOutlineWeight));     let toWtLabel = vlbl(fmt(textOutlineWeight))

        // Shape property controls
        let shapeTypePopupLocal = NSPopUpButton(frame: .zero, pullsDown: false)
        shapeTypePopupLocal.controlSize = .small
        shapeTypePopupLocal.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        shapeTypePopupLocal.addItem(withTitle: "Rectangle")
        shapeTypePopupLocal.addItem(withTitle: "Circle")
        shapeTypePopupLocal.addItem(withTitle: "Rounded Rectangle")
        shapeTypePopupLocal.selectItem(at: 0)
        let shapeBorderSlider = sld(0, 50, Double(shapeBorderWeight)); let shapeBorderLabel = vlbl(fmt(shapeBorderWeight))
        let shapeBorderWell   = well(shapeBorderColor)
        let shapeFillWell     = well(shapeFillColor)

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
            shapeFillColorWell: shapeFillWell
        )
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

        // ── Root ─────────────────────────────────────────────────────────────────
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
        zoomScroll = zs;  zoomLabel = zl
        cropToolButton = cropBtn;  cropOverlay = co
        borderToggle = bToggle;              shadowToggle = sToggle
        borderWeightSlider = bwSlider;       borderWeightLabel = bwLabel;       borderColorWell = bcWell
        shadowXSlider = sxSlider;            shadowXLabel = sxLabel
        shadowYSlider = sySlider;            shadowYLabel = syLabel
        shadowBlurSlider = sbSlider;         shadowBlurLabel = sbLabel
        shadowColorWell = scWell
        shadowOpacitySlider = soSlider;      shadowOpacityLabel = soLabel
        arrowWeightSlider = awSlider;        arrowWeightLabel = awLabel;        arrowColorWell = acWell
        textFontPopup = tfPopup
        textFontSizeSlider = tfSizeSlider;   textFontSizeLabel = tfSizeLabel
        textFontColorWell = tfColorWell;     textOutlineColorWell = toColorWell
        textOutlineWeightSlider = toWtSlider; textOutlineWeightLabel = toWtLabel
        shapeTypePopup = shapeTypePopupLocal; shapeBorderWeightSlider = shapeBorderSlider
        shapeBorderWeightLabel = shapeBorderLabel; shapeBorderColorWell = shapeBorderWell
        shapeFillColorWell = shapeFillWell

        super.init(window: win)
        win.delegate = self

        // ── Wire targets ─────────────────────────────────────────────────────────
        arrowBtn.target             = self; arrowBtn.action             = #selector(toggleArrowTool(_:))
        textBtn.target              = self; textBtn.action              = #selector(toggleTextTool(_:))
        shapeBtn.target             = self; shapeBtn.action             = #selector(toggleShapeTool(_:))
        cropBtn.target              = self; cropBtn.action              = #selector(toggleCropTool(_:))
        zoomInBtn.target            = self; zoomInBtn.action            = #selector(zoomIn)
        zoomOutBtn.target           = self; zoomOutBtn.action           = #selector(zoomOut)
        borderToggle.target         = self; borderToggle.action         = #selector(borderToggleChanged(_:))
        shadowToggle.target         = self; shadowToggle.action         = #selector(shadowToggleChanged(_:))
        borderWeightSlider.target   = self; borderWeightSlider.action   = #selector(borderWeightChanged(_:))
        shadowXSlider.target        = self; shadowXSlider.action        = #selector(shadowXChanged(_:))
        shadowYSlider.target        = self; shadowYSlider.action        = #selector(shadowYChanged(_:))
        shadowBlurSlider.target     = self; shadowBlurSlider.action     = #selector(shadowBlurChanged(_:))
        shadowOpacitySlider.target  = self; shadowOpacitySlider.action  = #selector(shadowOpacityChanged(_:))
        arrowWeightSlider.target    = self; arrowWeightSlider.action    = #selector(arrowWeightChanged(_:))
        textFontPopup.target        = self; textFontPopup.action        = #selector(textFontChanged(_:))
        textFontSizeSlider.target   = self; textFontSizeSlider.action   = #selector(textFontSizeChanged(_:))
        textOutlineWeightSlider.target = self
        textOutlineWeightSlider.action = #selector(textOutlineWeightChanged(_:))
        shapeTypePopup.target = self
        shapeTypePopup.action = #selector(shapeTypeChanged(_:))
        shapeBorderWeightSlider.target = self
        shapeBorderWeightSlider.action = #selector(shapeBorderWeightChanged(_:))
        shapeBorderColorWell.target = self
        shapeBorderColorWell.action = #selector(colorPanelChanged)
        shapeFillColorWell.target = self
        shapeFillColorWell.action = #selector(colorPanelChanged)

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
        annotationOverlay.currentWeight       = arrowWeight
        annotationOverlay.currentColor        = arrowColor
        annotationOverlay.currentFontName     = textFontName
        annotationOverlay.currentFontSize     = textFontSize
        annotationOverlay.currentFontColor    = textFontColor
        annotationOverlay.currentOutlineColor = textOutlineColor
        annotationOverlay.currentOutlineWeight = textOutlineWeight
        annotationOverlay.currentShapeType     = shapeType
        annotationOverlay.currentBorderWeight  = shapeBorderWeight
        annotationOverlay.currentBorderColor   = shapeBorderColor
        annotationOverlay.currentFillColor     = shapeFillColor

        annotationOverlay.imageDisplayRectProvider = { [weak self] in
            guard let iv = self?.captureView, let img = iv.image else { return .zero }
            return Self.imageDisplayRect(for: img, in: iv)
        }
        co.imageDisplayRectProvider = { [weak self] in
            guard let iv = self?.captureView, let img = iv.image else { return .zero }
            return Self.imageDisplayRect(for: img, in: iv)
        }
        annotationOverlay.onCopy   = { [weak self] in self?.copyToClipboard() }
        annotationOverlay.onChange = { [weak self] in self?.refreshForExport() }
        annotationOverlay.onActivateTool = { [weak self] tool in
            guard let self else { return }
            // Deselect all toolbar buttons first, then activate the right one.
            self.arrowToolButton.state = .off
            self.textToolButton.state  = .off
            self.shapeToolButton.state = .off
            switch tool {
            case .arrow:
                self.arrowToolButton.state = .on
                self.toolMode = .arrow
                self.annotationOverlay.activeTool = .arrow
            case .text:
                self.textToolButton.state = .on
                self.toolMode = .text
                self.annotationOverlay.activeTool = .text
            case .shape:
                self.shapeToolButton.state = .on
                self.toolMode = .shape
                self.annotationOverlay.activeTool = .shape
            case .none:
                break
            }
            self.sidebar.setToolMode(self.toolMode)
            self.window?.makeFirstResponder(self.annotationOverlay)
        }

        // ── Crop overlay wiring ──────────────────────────────────────────────────
        co.onCropConfirmed = { [weak self] normRect in
            self?.applyCrop(normRect: normRect)
        }
        co.onCropCancelled = { [weak self] in
            self?.deactivateCropTool()
        }

        annotationOverlay.onTextSelectionChanged = { [weak self] ann in
            guard let self else { return }
            if let ann = ann {
                self.textFontName      = ann.fontName
                self.textFontSize      = ann.fontSize
                self.textFontColor     = ann.fontColor
                self.textOutlineColor  = ann.outlineColor
                self.textOutlineWeight = ann.outlineWeight
                self.annotationOverlay.currentFontName      = ann.fontName
                self.annotationOverlay.currentFontSize      = ann.fontSize
                self.annotationOverlay.currentFontColor     = ann.fontColor
                self.annotationOverlay.currentOutlineColor  = ann.outlineColor
                self.annotationOverlay.currentOutlineWeight = ann.outlineWeight
            }
            let fonts = ["Helvetica-Bold", "Helvetica", "Arial-BoldMT", "ArialMT", "Courier-Bold", "Courier",
                         "TimesNewRomanPS-BoldMT", "TimesNewRomanPSMT", "Georgia-Bold", "Georgia",
                         "Menlo-Bold", "Menlo-Regular", "Monaco"]
            if let idx = fonts.firstIndex(of: self.textFontName) {
                self.textFontPopup.selectItem(at: idx)
            }
            self.textFontSizeSlider.doubleValue      = Double(self.textFontSize)
            self.textFontSizeLabel.stringValue        = fmt(self.textFontSize)
            self.textFontColorWell.color              = self.textFontColor
            self.textOutlineColorWell.color           = self.textOutlineColor
            self.textOutlineWeightSlider.doubleValue  = Double(self.textOutlineWeight)
            self.textOutlineWeightLabel.stringValue   = fmt(self.textOutlineWeight)
        }

        refreshBaseImage()
        refreshShadow()

        // ── Title-bar Save button ────────────────────────────────────────────────
        let saveBtn = NSButton(title: "Save As…", target: self, action: #selector(saveAs(_:)))
        saveBtn.bezelStyle = .rounded; saveBtn.controlSize = .small; saveBtn.sizeToFit()
        let acc = NSTitlebarAccessoryViewController()
        acc.view = saveBtn; acc.layoutAttribute = .right
        win.addTitlebarAccessoryViewController(acc)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Actions

    @objc private func toggleArrowTool(_ sender: NSButton) {
        if sender.state == .on {
            toolMode = .arrow
            textToolButton.state = .off
            annotationOverlay.activeTool = .arrow
            window?.makeFirstResponder(annotationOverlay)
        } else {
            toolMode = .none
            annotationOverlay.activeTool = .none
        }
        sidebar.setToolMode(toolMode)
    }

    @objc private func toggleTextTool(_ sender: NSButton) {
        if sender.state == .on {
            toolMode = .text
            arrowToolButton.state = .off
            annotationOverlay.activeTool = .text
            window?.makeFirstResponder(annotationOverlay)
        } else {
            toolMode = .none
            annotationOverlay.activeTool = .none
        }
        sidebar.setToolMode(toolMode)
    }

    @objc private func toggleShapeTool(_ sender: NSButton) {
        if sender.state == .on {
            toolMode = .shape
            arrowToolButton.state = .off
            textToolButton.state = .off
            annotationOverlay.activeTool = .shape
            window?.makeFirstResponder(annotationOverlay)
        } else {
            toolMode = .none
            annotationOverlay.activeTool = .none
        }
        sidebar.setToolMode(toolMode)
    }

    @objc private func toggleCropTool(_ sender: NSButton) {
        if sender.state == .on {
            toolMode = .crop
            arrowToolButton.state = .off
            textToolButton.state  = .off
            annotationOverlay.activeTool = .none
            cropOverlay.isHidden = false
            cropOverlay.reset()
            window?.makeFirstResponder(cropOverlay)
        } else {
            deactivateCropTool()
        }
        sidebar.setToolMode(toolMode)
    }

    private func deactivateCropTool() {
        toolMode = .none
        cropToolButton.state = .off
        cropOverlay.isHidden = true
        cropOverlay.reset()
        sidebar.setToolMode(toolMode)
    }

    private func applyCrop(normRect: CGRect) {
        let img = currentImage
        let pixelRect = CGRect(
            x: normRect.origin.x * img.size.width,
            y: normRect.origin.y * img.size.height,
            width: normRect.size.width * img.size.width,
            height: normRect.size.height * img.size.height
        ).integral

        guard pixelRect.width > 1, pixelRect.height > 1 else {
            deactivateCropTool(); return
        }

        let imageBeforeCrop = currentImage
        window?.undoManager?.registerUndo(withTarget: self, handler: { target in
            target.swapCropImage(to: imageBeforeCrop)
        })
        window?.undoManager?.setActionName("Crop")

        let cropped = NSImage(size: pixelRect.size)
        cropped.lockFocus()
        let srcRect = CGRect(
            x: pixelRect.origin.x,
            y: pixelRect.origin.y,
            width: pixelRect.width,
            height: pixelRect.height
        )
        img.draw(in: CGRect(origin: .zero, size: pixelRect.size),
                 from: srcRect,
                 operation: .copy,
                 fraction: 1.0)
        cropped.unlockFocus()

        currentImage = cropped
        captureView.image = cropped
        annotationOverlay.needsDisplay = true

        deactivateCropTool()
    }

    @objc private func swapCropImage(to image: NSImage) {
        let previous = currentImage
        window?.undoManager?.registerUndo(withTarget: self, handler: { target in
            target.swapCropImage(to: previous)
        })
        window?.undoManager?.setActionName("Crop")
        currentImage = image
        captureView.image = image
        annotationOverlay.needsDisplay = true
    }

    @objc private func zoomIn() {
        let newMag = min(8.0, zoomScroll.magnification * 1.25)
        let center = CGPoint(x: zoomScroll.documentView!.frame.midX,
                             y: zoomScroll.documentView!.frame.midY)
        zoomScroll.setMagnification(newMag, centeredAt: center)
        updateZoomLabel()
    }

    @objc private func zoomOut() {
        let newMag = max(0.1, zoomScroll.magnification / 1.25)
        let center = CGPoint(x: zoomScroll.documentView!.frame.midX,
                             y: zoomScroll.documentView!.frame.midY)
        zoomScroll.setMagnification(newMag, centeredAt: center)
        updateZoomLabel()
    }

    @objc private func zoomDidEnd(_ note: Notification) { updateZoomLabel() }

    private func updateZoomLabel() {
        zoomLabel.stringValue = "\(Int(round(zoomScroll.magnification * 100)))%"
    }

    @objc private func borderToggleChanged(_ btn: NSButton) {
        borderEnabled = btn.state == .on
        refreshBaseImage(); savePrefs()
    }

    @objc private func shadowToggleChanged(_ btn: NSButton) {
        shadowEnabled = btn.state == .on
        refreshShadow(); savePrefs()
    }

    @objc private func borderWeightChanged(_ s: NSSlider) {
        borderWeight = CGFloat(s.doubleValue)
        borderWeightLabel.stringValue = fmt(borderWeight)
        refreshBaseImage(); savePrefs()
    }

    @objc private func shadowXChanged(_ s: NSSlider) {
        shadowOffsetX = CGFloat(s.doubleValue)
        shadowXLabel.stringValue = fmt(shadowOffsetX)
        refreshShadow(); savePrefs()
    }

    @objc private func shadowYChanged(_ s: NSSlider) {
        shadowOffsetY = CGFloat(s.doubleValue)
        shadowYLabel.stringValue = fmt(shadowOffsetY)
        refreshShadow(); savePrefs()
    }

    @objc private func shadowBlurChanged(_ s: NSSlider) {
        shadowBlur = CGFloat(s.doubleValue)
        shadowBlurLabel.stringValue = fmt(shadowBlur)
        refreshShadow(); savePrefs()
    }

    @objc private func shadowOpacityChanged(_ s: NSSlider) {
        shadowOpacity = CGFloat(s.doubleValue) / 100
        shadowOpacityLabel.stringValue = fmtPct(shadowOpacity)
        refreshShadow(); savePrefs()
    }

    @objc private func arrowWeightChanged(_ s: NSSlider) {
        arrowWeight = max(1, CGFloat(s.doubleValue))
        annotationOverlay.currentWeight = arrowWeight
        annotationOverlay.updateSelected(weight: arrowWeight)
        arrowWeightLabel.stringValue = fmt(arrowWeight)
        savePrefs()
    }

    @objc private func textFontChanged(_ popup: NSPopUpButton) {
        let fonts = ["Helvetica-Bold", "Helvetica", "Arial-BoldMT", "ArialMT", "Courier-Bold", "Courier",
                     "TimesNewRomanPS-BoldMT", "TimesNewRomanPSMT", "Georgia-Bold", "Georgia",
                     "Menlo-Bold", "Menlo-Regular", "Monaco"]
        guard popup.indexOfSelectedItem >= 0, popup.indexOfSelectedItem < fonts.count else { return }
        textFontName = fonts[popup.indexOfSelectedItem]
        annotationOverlay.currentFontName = textFontName
        annotationOverlay.updateSelectedText(fontName: textFontName)
        savePrefs()
    }

    @objc private func textFontSizeChanged(_ s: NSSlider) {
        textFontSize = CGFloat(s.doubleValue)
        textFontSizeLabel.stringValue = fmt(textFontSize)
        annotationOverlay.currentFontSize = textFontSize
        annotationOverlay.updateSelectedText(fontSize: textFontSize)
        savePrefs()
    }

    @objc private func textOutlineWeightChanged(_ s: NSSlider) {
        textOutlineWeight = CGFloat(s.doubleValue)
        textOutlineWeightLabel.stringValue = fmt(textOutlineWeight)
        annotationOverlay.currentOutlineWeight = textOutlineWeight
        annotationOverlay.updateSelectedText(outlineWeight: textOutlineWeight)
        savePrefs()
    }

    @objc private func shapeTypeChanged(_ popup: NSPopUpButton) {
        let types: [ShapeType] = [.rectangle, .circle, .roundedRectangle]
        guard popup.indexOfSelectedItem >= 0, popup.indexOfSelectedItem < types.count else { return }
        shapeType = types[popup.indexOfSelectedItem]
        annotationOverlay.currentShapeType = shapeType
        annotationOverlay.updateSelectedShape(shapeType: shapeType)
        savePrefs()
    }

    @objc private func shapeBorderWeightChanged(_ s: NSSlider) {
        shapeBorderWeight = CGFloat(s.doubleValue)
        shapeBorderWeightLabel.stringValue = fmt(shapeBorderWeight)
        annotationOverlay.currentBorderWeight = shapeBorderWeight
        annotationOverlay.updateSelectedShape(borderWeight: shapeBorderWeight)
        savePrefs()
    }

    @objc private func colorPanelChanged() {
        if borderColorWell.isActive {
            borderColor = borderColorWell.color
            refreshBaseImage()
        } else if shadowColorWell.isActive {
            shadowColor = shadowColorWell.color
            refreshShadow()
        } else if arrowColorWell.isActive {
            arrowColor = arrowColorWell.color
            annotationOverlay.currentColor = arrowColor
            annotationOverlay.updateSelected(color: arrowColor)
        } else if textFontColorWell.isActive {
            textFontColor = textFontColorWell.color
            annotationOverlay.currentFontColor = textFontColor
            annotationOverlay.updateSelectedText(fontColor: textFontColor)
        } else if textOutlineColorWell.isActive {
            textOutlineColor = textOutlineColorWell.color
            annotationOverlay.currentOutlineColor = textOutlineColor
            annotationOverlay.updateSelectedText(outlineColor: textOutlineColor)
        } else if shapeBorderColorWell.isActive {
            shapeBorderColor = shapeBorderColorWell.color
            annotationOverlay.currentBorderColor = shapeBorderColor
            annotationOverlay.updateSelectedShape(borderColor: shapeBorderColor)
            savePrefs()
        } else if shapeFillColorWell.isActive {
            shapeFillColor = shapeFillColorWell.color
            annotationOverlay.currentFillColor = shapeFillColor
            annotationOverlay.updateSelectedShape(fillColor: shapeFillColor)
            savePrefs()
        }
        savePrefs()
    }

    @objc func copyImage(_ sender: Any?) { copyToClipboard() }

    @objc func saveAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "capture.png"
        panel.isExtensionHidden = false
        guard let win = window else { return }
        panel.beginSheetModal(for: win) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.annotationOverlay.finalizeEditing()
            self.writeImage(self.rendered(), to: url)
        }
    }

    // MARK: - Prefs

    private func savePrefs() {
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

    // MARK: - Refresh

    func refreshBaseImage() {
        captureView.image = (borderEnabled && borderWeight > 0) ? withBorder(currentImage) : currentImage
        annotationOverlay.needsDisplay = true
    }

    func refreshShadow() {
        captureView.wantsLayer = true
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = false
        guard let layer = captureView.layer else { return }
        layer.masksToBounds = false
        layer.shadowOpacity = shadowEnabled ? Float(shadowOpacity) : 0
        layer.shadowRadius  = shadowBlur
        layer.shadowOffset  = CGSize(width: shadowOffsetX, height: shadowOffsetY)
        layer.shadowColor   = shadowColor.cgColor
    }

    private func refreshForExport() {}

    // MARK: - Clipboard / write

    private func copyToClipboard() {
        annotationOverlay.finalizeEditing()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([rendered()])
    }

    private func writeImage(_ image: NSImage, to url: URL) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let type: UTType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": type = .jpeg
        case "tiff", "tif": type = .tiff
        default:            type = .png
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self,
            name: NSColorPanel.colorDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self,
            name: NSScrollView.didEndLiveMagnifyNotification, object: zoomScroll)
        Self.openEditors.removeAll { $0 === self }
        if Self.openEditors.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    // MARK: - Utility

    // Scale capped at 1.0 so images are never enlarged beyond their natural size.
    static func imageDisplayRect(for image: NSImage, in view: NSView) -> CGRect {
        let vw = view.bounds.width, vh = view.bounds.height
        let iw = image.size.width,  ih = image.size.height
        let scale = min(1.0, min(vw / iw, vh / ih))
        let sw = iw * scale, sh = ih * scale
        return CGRect(x: (vw - sw) / 2, y: (vh - sh) / 2, width: sw, height: sh)
    }
}

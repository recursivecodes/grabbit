import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Preference keys

private enum Prefs {
    static let borderWeight      = "grabbit.borderWeight"
    static let borderColor       = "grabbit.borderColor"
    static let shadowX           = "grabbit.shadowX"
    static let shadowY           = "grabbit.shadowY"
    static let shadowBlur        = "grabbit.shadowBlur"
    static let shadowColor       = "grabbit.shadowColor"
    static let shadowOpacity     = "grabbit.shadowOpacity"
    static let arrowWeight       = "grabbit.arrowWeight"
    static let arrowColor        = "grabbit.arrowColor"
    static let borderEnabled     = "grabbit.borderEnabled"
    static let shadowEnabled     = "grabbit.shadowEnabled"
    static let textFontName      = "grabbit.textFontName"
    static let textFontSize      = "grabbit.textFontSize"
    static let textFontColor     = "grabbit.textFontColor"
    static let textOutlineColor  = "grabbit.textOutlineColor"
    static let textOutlineWeight = "grabbit.textOutlineWeight"
    static let shapeBorderWeight = "grabbit.shapeBorderWeight"
    static let shapeBorderColor  = "grabbit.shapeBorderColor"
    static let shapeFillColor    = "grabbit.shapeFillColor"
}

// MARK: - UserDefaults helpers

private func loadDouble(_ key: String, default def: Double) -> Double {
    UserDefaults.standard.object(forKey: key) != nil
        ? UserDefaults.standard.double(forKey: key) : def
}

private func loadColor(_ key: String, default def: NSColor) -> NSColor {
    guard let data = UserDefaults.standard.data(forKey: key),
          let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    else { return def }
    return c
}

private func loadString(_ key: String, default def: String) -> String {
    UserDefaults.standard.string(forKey: key) ?? def
}

private func saveDouble(_ value: Double, key: String) {
    UserDefaults.standard.set(value, forKey: key)
}

private func saveColor(_ color: NSColor, key: String) {
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
        UserDefaults.standard.set(data, forKey: key)
    }
}

private func saveString(_ value: String, key: String) {
    UserDefaults.standard.set(value, forKey: key)
}

// MARK: - Tool mode

private enum ToolMode { case none, arrow, text, shape }

// MARK: - EditorWindowController

class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openEditors: [EditorWindowController] = []

    // MARK: State

    private let originalImage: NSImage
    private var borderWeight:      CGFloat
    private var borderColor:       NSColor
    private var shadowOffsetX:     CGFloat
    private var shadowOffsetY:     CGFloat
    private var shadowBlur:        CGFloat
    private var shadowColor:       NSColor
    private var shadowOpacity:     CGFloat
    private var arrowWeight:       CGFloat
    private var arrowColor:        NSColor
    private var borderEnabled:     Bool
    private var shadowEnabled:     Bool
    private var textFontName:      String
    private var textFontSize:      CGFloat
    private var textFontColor:     NSColor
    private var textOutlineColor:  NSColor
    private var textOutlineWeight: CGFloat
    private var toolMode: ToolMode = .none

    // Shape state
    private var shapeType:        ShapeType = .rectangle
    private var shapeBorderWeight: CGFloat = 2
    private var shapeBorderColor: NSColor = .black
    private var shapeFillColor:   NSColor = .clear

    // MARK: Views

    private var captureView:             NSImageView!
    private var annotationOverlay:       AnnotationOverlay!
    private var canvas:                  CanvasView!
    private var sidebar:                 TabbedEditorSidebar!
    private var arrowToolButton:         NSButton!
    private var textToolButton:          NSButton!
    private var zoomScroll:              NSScrollView!
    private var zoomLabel:              NSTextField!

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
        NSApp.setActivationPolicy(.regular)
        c.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        c.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Init

    init(image: NSImage) {
        self.originalImage = image

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
        let win = NSWindow(
            contentRect: screen.visibleFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Grabbit"
        win.setFrame(screen.visibleFrame, display: false)
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
        let zoomDoc = NSView()
        zoomDoc.translatesAutoresizingMaskIntoConstraints = true
        zoomDoc.autoresizingMask = [.width, .height]

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
        zs.documentView           = zoomDoc
        zs.translatesAutoresizingMaskIntoConstraints = false

        // ── Canvas ───────────────────────────────────────────────────────────────
        let cv = CanvasView()
        cv.translatesAutoresizingMaskIntoConstraints = false

        // ── Canvas toolbar ───────────────────────────────────────────────────────
        let arrowBtn = makeToolButton("Arrow")
        let textBtn  = makeToolButton("Text")
        let shapeBtn = makeToolButton("Shape")

        let toolsStack = NSStackView(views: [arrowBtn, textBtn, shapeBtn])
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

        let tbH: CGFloat = 44
        cv.addSubview(zs)
        cv.addSubview(toolsStack)
        cv.addSubview(zoomStack)

        NSLayoutConstraint.activate([
            zs.topAnchor.constraint(equalTo: cv.topAnchor, constant: tbH),
            zs.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            zs.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            zs.trailingAnchor.constraint(equalTo: cv.trailingAnchor),

            toolsStack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            toolsStack.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: tbH / 2),

            zoomStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            zoomStack.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: tbH / 2),
        ])

        // ── Sidebar controls ─────────────────────────────────────────────────────
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
        arrowToolButton = arrowBtn;  textToolButton = textBtn
        zoomScroll = zs;  zoomLabel = zl
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
        annotationOverlay.onCopy   = { [weak self] in self?.copyToClipboard() }
        annotationOverlay.onChange = { [weak self] in self?.refreshForExport() }

        annotationOverlay.onTextSelectionChanged = { [weak self] ann in
            guard let self else { return }
            if let ann = ann {
                self.textFontName      = ann.fontName
                self.textFontSize      = ann.fontSize
                self.textFontColor     = ann.fontColor
                self.textOutlineColor  = ann.outlineColor
                self.textOutlineWeight = ann.outlineWeight
                // Propagate to current defaults so new annotations inherit.
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

    @objc private func zoomIn() {
        zoomScroll.magnification = min(8.0, zoomScroll.magnification * 1.25)
        updateZoomLabel()
    }

    @objc private func zoomOut() {
        zoomScroll.magnification = max(0.1, zoomScroll.magnification / 1.25)
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

    private func refreshBaseImage() {
        captureView.image = (borderEnabled && borderWeight > 0) ? withBorder(originalImage) : originalImage
        annotationOverlay.needsDisplay = true
    }

    private func refreshShadow() {
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

    // MARK: - Rendering

    private func rendered() -> NSImage {
        var img = (borderEnabled && borderWeight > 0) ? withBorder(originalImage) : originalImage
        img = withArrows(img)
        img = withTexts(img)
        img = withShapes(img)
        if shadowEnabled && shadowOpacity > 0 { img = withShadow(img) }
        return img
    }

    private func withBorder(_ base: NSImage) -> NSImage {
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
            // Fill
            if shape.fillColor.alphaComponent > 0 {
                shape.fillColor.setFill()
                path.fill()
            }
            // Stroke
            shape.borderColor.setStroke()
            path.lineWidth = shape.borderWeight * scale
            path.stroke()
        }
        out.unlockFocus()
        return out
    }

    private func withShadow(_ base: NSImage) -> NSImage {
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

// MARK: - Tabbed sidebar

private class TabbedEditorSidebar: NSView {
    private let tabControl:       NSSegmentedControl
    private let propertiesScroll: NSScrollView
    private let effectsScroll:    NSScrollView
    private let effectsStack:     NSStackView
    private let propertiesStack:  NSStackView
    private var noToolView:       NSView!
    private var arrowPropViews:   [NSView] = []
    private var textPropViews:    [NSView] = []
    private var shapePropViews:   [NSView] = []

    init(
        arrowWeightSlider: NSSlider, arrowWeightLabel: NSTextField, arrowColorWell: NSColorWell,
        textFontPopup: NSPopUpButton,
        textFontSizeSlider: NSSlider, textFontSizeLabel: NSTextField,
        textFontColorWell: NSColorWell,
        textOutlineColorWell: NSColorWell,
        textOutlineWeightSlider: NSSlider, textOutlineWeightLabel: NSTextField,
        shapeTypePopup: NSPopUpButton,
        shapeBorderWeightSlider: NSSlider, shapeBorderWeightLabel: NSTextField,
        shapeBorderColorWell: NSColorWell,
        shapeFillColorWell: NSColorWell
    ) {
        tabControl = NSSegmentedControl(
            labels: ["Properties", "Effects"],
            trackingMode: .selectOne, target: nil, action: nil
        )
        tabControl.selectedSegment = 0
        tabControl.controlSize = .small
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        effectsStack = NSStackView()
        effectsStack.orientation = .vertical
        effectsStack.alignment = .left
        effectsStack.spacing = 0
        effectsStack.translatesAutoresizingMaskIntoConstraints = false

        propertiesStack = NSStackView()
        propertiesStack.orientation = .vertical
        propertiesStack.alignment = .left
        propertiesStack.spacing = 0
        propertiesStack.translatesAutoresizingMaskIntoConstraints = false

        let ps = NSScrollView()
        ps.hasVerticalScroller = true; ps.autohidesScrollers = true
        ps.drawsBackground = false
        ps.translatesAutoresizingMaskIntoConstraints = false
        let pClip = FlippedClipView()
        pClip.drawsBackground = false
        ps.contentView = pClip
        ps.documentView = propertiesStack
        propertiesScroll = ps

        let es = NSScrollView()
        es.hasVerticalScroller = true; es.autohidesScrollers = true
        es.drawsBackground = false
        es.translatesAutoresizingMaskIntoConstraints = false
        let eClip = FlippedClipView()
        eClip.drawsBackground = false
        es.contentView = eClip
        es.documentView = effectsStack
        effectsScroll = es

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor

        let sep = NSBox()
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = NSColor.separatorColor
        sep.cornerRadius = 0
        sep.translatesAutoresizingMaskIntoConstraints = false

        let tabDivider = NSBox()
        tabDivider.boxType = .separator
        tabDivider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(sep)
        addSubview(tabControl)
        addSubview(tabDivider)
        addSubview(propertiesScroll)
        addSubview(effectsScroll)

        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1),

            tabControl.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            tabControl.leadingAnchor.constraint(equalTo: sep.trailingAnchor, constant: 10),
            tabControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            tabDivider.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 8),
            tabDivider.heightAnchor.constraint(equalToConstant: 1),
            tabDivider.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            tabDivider.trailingAnchor.constraint(equalTo: trailingAnchor),

            propertiesScroll.topAnchor.constraint(equalTo: tabDivider.bottomAnchor),
            propertiesScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            propertiesScroll.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            propertiesScroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            effectsScroll.topAnchor.constraint(equalTo: tabDivider.bottomAnchor),
            effectsScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectsScroll.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            effectsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            propertiesStack.topAnchor.constraint(equalTo: pClip.topAnchor),
            propertiesStack.leadingAnchor.constraint(equalTo: pClip.leadingAnchor),
            propertiesStack.widthAnchor.constraint(equalTo: pClip.widthAnchor),
            effectsStack.topAnchor.constraint(equalTo: eClip.topAnchor),
            effectsStack.leadingAnchor.constraint(equalTo: eClip.leadingAnchor),
            effectsStack.widthAnchor.constraint(equalTo: eClip.widthAnchor),
        ])

        // ── Properties: "no tool" placeholder ───────────────────────────────────
        let placeholder = NSTextField(labelWithString: "Select a tool from the\ntoolbar to see its properties.")
        placeholder.font = NSFont.systemFont(ofSize: 12)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.lineBreakMode = .byWordWrapping
        placeholder.maximumNumberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let ntBox = NSView()
        ntBox.translatesAutoresizingMaskIntoConstraints = false
        ntBox.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: ntBox.topAnchor, constant: 24),
            placeholder.bottomAnchor.constraint(equalTo: ntBox.bottomAnchor, constant: -24),
            placeholder.leadingAnchor.constraint(equalTo: ntBox.leadingAnchor, constant: 14),
            placeholder.trailingAnchor.constraint(equalTo: ntBox.trailingAnchor, constant: -14),
        ])
        propertiesStack.addArrangedSubview(ntBox)
        noToolView = ntBox

        // ── Properties: arrow tool section ──────────────────────────────────────
        let arrowHeader = makeSectionBox("ARROW")
        arrowHeader.isHidden = true
        propertiesStack.addArrangedSubview(arrowHeader)
        arrowPropViews.append(arrowHeader)

        let awRow = makeSidebarRow("Weight", arrowWeightSlider, arrowWeightLabel)
        awRow.isHidden = true
        propertiesStack.addArrangedSubview(awRow)
        arrowPropViews.append(awRow)

        let acRow = makeSidebarRow("Color", arrowColorWell)
        acRow.isHidden = true
        propertiesStack.addArrangedSubview(acRow)
        arrowPropViews.append(acRow)

        // ── Properties: text tool section ───────────────────────────────────────
        let textHeader = makeSectionBox("TEXT")
        textHeader.isHidden = true
        propertiesStack.addArrangedSubview(textHeader)
        textPropViews.append(textHeader)

        let tfFontRow = makeSidebarRow("Font", textFontPopup)
        tfFontRow.isHidden = true
        propertiesStack.addArrangedSubview(tfFontRow)
        textPropViews.append(tfFontRow)

        let tfSizeRow = makeSidebarRow("Size", textFontSizeSlider, textFontSizeLabel)
        tfSizeRow.isHidden = true
        propertiesStack.addArrangedSubview(tfSizeRow)
        textPropViews.append(tfSizeRow)

        let tfColorRow = makeSidebarRow("Color", textFontColorWell)
        tfColorRow.isHidden = true
        propertiesStack.addArrangedSubview(tfColorRow)
        textPropViews.append(tfColorRow)

        let toColorRow = makeSidebarRow("Outline", textOutlineColorWell)
        toColorRow.isHidden = true
        propertiesStack.addArrangedSubview(toColorRow)
        textPropViews.append(toColorRow)

        let toWtRow = makeSidebarRow("Thickness", textOutlineWeightSlider, textOutlineWeightLabel)
        toWtRow.isHidden = true
        propertiesStack.addArrangedSubview(toWtRow)
        textPropViews.append(toWtRow)

        // ── Properties: shape tool section ──────────────────────────────────────
        let shapeHeader = makeSectionBox("SHAPE")
        shapeHeader.isHidden = true
        propertiesStack.addArrangedSubview(shapeHeader)
        shapePropViews.append(shapeHeader)

        let shapeTypeRow = makeSidebarRow("Type", shapeTypePopup)
        shapeTypeRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeTypeRow)
        shapePropViews.append(shapeTypeRow)

        let shapeBorderRow = makeSidebarRow("Border", shapeBorderWeightSlider, shapeBorderWeightLabel)
        shapeBorderRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeBorderRow)
        shapePropViews.append(shapeBorderRow)

        let shapeBorderColorRow = makeSidebarRow("Color", shapeBorderColorWell)
        shapeBorderColorRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeBorderColorRow)
        shapePropViews.append(shapeBorderColorRow)

        let shapeFillColorRow = makeSidebarRow("Fill", shapeFillColorWell)
        shapeFillColorRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeFillColorRow)
        shapePropViews.append(shapeFillColorRow)

        // Start showing Properties tab
        effectsScroll.isHidden = true

        tabControl.target = self
        tabControl.action = #selector(tabChanged(_:))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tab switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        propertiesScroll.isHidden = sender.selectedSegment != 0
        effectsScroll.isHidden    = sender.selectedSegment != 1
    }

    func setToolMode(_ mode: ToolMode) {
        noToolView.isHidden = mode != .none
        let isArrow = mode == .arrow
        let isText  = mode == .text
        let isShape = mode == .shape
        arrowPropViews.forEach { $0.isHidden = !isArrow }
        textPropViews.forEach  { $0.isHidden = !isText }
        shapePropViews.forEach { $0.isHidden = !isShape }
        if mode != .none && tabControl.selectedSegment != 0 {
            tabControl.selectedSegment = 0
            propertiesScroll.isHidden = false
            effectsScroll.isHidden = true
        }
    }

    // MARK: Effects panel builders

    func addEffectSection(_ title: String, toggle: NSButton? = nil) {
        if !effectsStack.arrangedSubviews.isEmpty {
            let divider = NSBox(); divider.boxType = .separator
            effectsStack.addArrangedSubview(divider)
        }
        effectsStack.addArrangedSubview(makeSectionBox(title, toggle: toggle))
    }

    func addEffectRow(_ labelText: String, _ control: NSView, _ valLabel: NSTextField? = nil) {
        effectsStack.addArrangedSubview(makeSidebarRow(labelText, control, valLabel))
    }

    // MARK: Private builders

    private func makeSectionBox(_ title: String, toggle: NSButton? = nil) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            lbl.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            lbl.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
        ])
        if let toggle = toggle {
            toggle.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(toggle)
            NSLayoutConstraint.activate([
                toggle.centerYAnchor.constraint(equalTo: lbl.centerYAnchor),
                toggle.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            ])
        }
        return box
    }

    private func makeSidebarRow(_ labelText: String, _ control: NSView,
                                _ valLabel: NSTextField? = nil) -> NSView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: 60).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [lbl, control]
        if let vl = valLabel {
            vl.translatesAutoresizingMaskIntoConstraints = false
            vl.widthAnchor.constraint(equalToConstant: 36).isActive = true
            vl.setContentHuggingPriority(.required, for: .horizontal)
            views.append(vl)
        }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }
}

// MARK: - ZoomableScrollView

private class ZoomableScrollView: NSScrollView {
    var onMagnificationChanged: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event); return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor: CGFloat = delta > 0 ? 1.08 : 1 / 1.08
        let newMag = (magnification * factor).clamped(to: minMagnification...maxMagnification)
        let center = convert(event.locationInWindow, from: nil)
        setMagnification(newMag, centeredAt: center)
        onMagnificationChanged?()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

// MARK: - FlippedClipView

private class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - Canvas

private class CanvasView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.93, alpha: 1).setFill()
        dirtyRect.fill()
    }
}

// MARK: - Tiny helpers

private func makeToolButton(_ title: String) -> NSButton {
    let b = NSButton()
    b.title = title
    b.setButtonType(.toggle)
    b.bezelStyle = .rounded
    b.translatesAutoresizingMaskIntoConstraints = false
    return b
}

private func sld(_ min: Double, _ max: Double, _ val: Double) -> NSSlider {
    let s = NSSlider(value: val, minValue: min, maxValue: max, target: nil, action: nil)
    s.controlSize = .small; return s
}

private func well(_ color: NSColor) -> NSColorWell {
    let w = NSColorWell(); w.color = color; return w
}

private func vlbl(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    f.alignment = .right
    f.translatesAutoresizingMaskIntoConstraints = false
    f.widthAnchor.constraint(equalToConstant: 36).isActive = true
    f.setContentHuggingPriority(.required, for: .horizontal)
    return f
}

private func fmt(_ v: CGFloat) -> String { "\(Int(v))" }
private func fmtPct(_ v: CGFloat) -> String { "\(Int(v * 100))%" }

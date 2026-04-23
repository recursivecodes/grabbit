import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Preference keys

private enum Prefs {
    static let borderWeight  = "grabbit.borderWeight"
    static let borderColor   = "grabbit.borderColor"
    static let shadowX       = "grabbit.shadowX"
    static let shadowY       = "grabbit.shadowY"
    static let shadowBlur    = "grabbit.shadowBlur"
    static let shadowColor   = "grabbit.shadowColor"
    static let shadowOpacity = "grabbit.shadowOpacity"
    static let arrowWeight   = "grabbit.arrowWeight"
    static let arrowColor    = "grabbit.arrowColor"
    static let borderEnabled = "grabbit.borderEnabled"
    static let shadowEnabled = "grabbit.shadowEnabled"
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

private func saveDouble(_ value: Double, key: String) {
    UserDefaults.standard.set(value, forKey: key)
}

private func saveColor(_ color: NSColor, key: String) {
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Tool mode

private enum ToolMode { case none, arrow, text, shape }

// MARK: - EditorWindowController

class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openEditors: [EditorWindowController] = []

    // MARK: State

    private let originalImage: NSImage
    private var borderWeight:  CGFloat
    private var borderColor:   NSColor
    private var shadowOffsetX: CGFloat
    private var shadowOffsetY: CGFloat
    private var shadowBlur:    CGFloat
    private var shadowColor:   NSColor
    private var shadowOpacity: CGFloat
    private var arrowWeight:   CGFloat
    private var arrowColor:    NSColor
    private var borderEnabled: Bool
    private var shadowEnabled: Bool
    private var toolMode: ToolMode = .none

    // MARK: Views

    private var captureView:        NSImageView!
    private var annotationOverlay:  AnnotationOverlay!
    private var canvas:             CanvasView!
    private var sidebar:            TabbedEditorSidebar!
    private var arrowToolButton:    NSButton!

    private var borderWeightSlider:  NSSlider!;   private var borderWeightLabel:  NSTextField!
    private var borderColorWell:     NSColorWell!
    private var shadowXSlider:       NSSlider!;   private var shadowXLabel:       NSTextField!
    private var shadowYSlider:       NSSlider!;   private var shadowYLabel:       NSTextField!
    private var shadowBlurSlider:    NSSlider!;   private var shadowBlurLabel:    NSTextField!
    private var shadowColorWell:     NSColorWell!
    private var shadowOpacitySlider: NSSlider!;   private var shadowOpacityLabel: NSTextField!
    private var borderToggle:        NSButton!
    private var shadowToggle:        NSButton!
    private var arrowWeightSlider:   NSSlider!;   private var arrowWeightLabel:   NSTextField!
    private var arrowColorWell:      NSColorWell!

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

        borderWeight  = CGFloat(loadDouble(Prefs.borderWeight,  default: 0))
        borderColor   = loadColor(Prefs.borderColor,            default: .black)
        shadowOffsetX = CGFloat(loadDouble(Prefs.shadowX,       default: 5))
        shadowOffsetY = CGFloat(loadDouble(Prefs.shadowY,       default: -5))
        shadowBlur    = CGFloat(loadDouble(Prefs.shadowBlur,    default: 10))
        shadowColor   = loadColor(Prefs.shadowColor,            default: .black)
        shadowOpacity = CGFloat(loadDouble(Prefs.shadowOpacity, default: 0))
        arrowWeight   = CGFloat(loadDouble(Prefs.arrowWeight,   default: 2))
        arrowColor    = loadColor(Prefs.arrowColor,             default: .systemRed)
        borderEnabled = UserDefaults.standard.object(forKey: Prefs.borderEnabled) != nil
                        ? UserDefaults.standard.bool(forKey: Prefs.borderEnabled) : false
        shadowEnabled = UserDefaults.standard.object(forKey: Prefs.shadowEnabled) != nil
                        ? UserDefaults.standard.bool(forKey: Prefs.shadowEnabled) : false

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

        // ── Image view ──────────────────────────────────────────────────────────
        let iv = NSImageView()
        iv.image = image
        iv.imageScaling = .scaleProportionallyDown  // never enlarge beyond natural size
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false

        let ol = AnnotationOverlay()
        ol.translatesAutoresizingMaskIntoConstraints = false

        // ── Canvas ──────────────────────────────────────────────────────────────
        let cv = CanvasView()
        cv.translatesAutoresizingMaskIntoConstraints = false

        // ── Canvas toolbar (top-center) ──────────────────────────────────────────
        let arrowBtn = makeToolButton("Arrow")
        let textBtn  = makeToolButton("Text")
        let shapeBtn = makeToolButton("Shape")
        textBtn.isEnabled  = false
        shapeBtn.isEnabled = false

        let toolbarStack = NSStackView(views: [arrowBtn, textBtn, shapeBtn])
        toolbarStack.orientation = .horizontal
        toolbarStack.spacing = 6
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(iv)
        cv.addSubview(ol)
        cv.addSubview(toolbarStack)

        let pad: CGFloat = 32
        let tbH: CGFloat = 44

        NSLayoutConstraint.activate([
            // Toolbar centered at top of canvas
            toolbarStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 10),
            toolbarStack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Image view fills canvas below toolbar with padding
            iv.topAnchor.constraint(equalTo: cv.topAnchor, constant: tbH),
            iv.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
            iv.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            iv.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            ol.topAnchor.constraint(equalTo: iv.topAnchor),
            ol.bottomAnchor.constraint(equalTo: iv.bottomAnchor),
            ol.leadingAnchor.constraint(equalTo: iv.leadingAnchor),
            ol.trailingAnchor.constraint(equalTo: iv.trailingAnchor),
        ])

        // ── Sidebar controls ────────────────────────────────────────────────────
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

        let sb = TabbedEditorSidebar(
            arrowWeightSlider: awSlider, arrowWeightLabel: awLabel, arrowColorWell: acWell
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

        // ── Root ────────────────────────────────────────────────────────────────
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

        // ── IUO assignments ─────────────────────────────────────────────────────
        captureView = iv;  annotationOverlay = ol;  canvas = cv;  sidebar = sb
        arrowToolButton = arrowBtn
        borderToggle = bToggle;          shadowToggle = sToggle
        borderWeightSlider = bwSlider;   borderWeightLabel = bwLabel;   borderColorWell = bcWell
        shadowXSlider = sxSlider;        shadowXLabel = sxLabel
        shadowYSlider = sySlider;        shadowYLabel = syLabel
        shadowBlurSlider = sbSlider;     shadowBlurLabel = sbLabel
        shadowColorWell = scWell
        shadowOpacitySlider = soSlider;  shadowOpacityLabel = soLabel
        arrowWeightSlider = awSlider;    arrowWeightLabel = awLabel;    arrowColorWell = acWell

        super.init(window: win)
        win.delegate = self

        // ── Wire targets ─────────────────────────────────────────────────────────
        arrowBtn.target            = self; arrowBtn.action            = #selector(toggleArrowTool(_:))
        borderToggle.target        = self; borderToggle.action        = #selector(borderToggleChanged(_:))
        shadowToggle.target        = self; shadowToggle.action        = #selector(shadowToggleChanged(_:))
        borderWeightSlider.target  = self; borderWeightSlider.action  = #selector(borderWeightChanged(_:))
        shadowXSlider.target       = self; shadowXSlider.action       = #selector(shadowXChanged(_:))
        shadowYSlider.target       = self; shadowYSlider.action       = #selector(shadowYChanged(_:))
        shadowBlurSlider.target    = self; shadowBlurSlider.action    = #selector(shadowBlurChanged(_:))
        shadowOpacitySlider.target = self; shadowOpacitySlider.action = #selector(shadowOpacityChanged(_:))
        arrowWeightSlider.target   = self; arrowWeightSlider.action   = #selector(arrowWeightChanged(_:))

        NotificationCenter.default.addObserver(
            self, selector: #selector(colorPanelChanged),
            name: NSColorPanel.colorDidChangeNotification, object: nil)

        // ── Overlay wiring ───────────────────────────────────────────────────────
        annotationOverlay.currentWeight = arrowWeight
        annotationOverlay.currentColor  = arrowColor
        annotationOverlay.imageDisplayRectProvider = { [weak self] in
            guard let iv = self?.captureView, let img = iv.image else { return .zero }
            return Self.imageDisplayRect(for: img, in: iv)
        }
        annotationOverlay.onCopy   = { [weak self] in self?.copyToClipboard() }
        annotationOverlay.onChange = { [weak self] in self?.refreshForExport() }

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
            annotationOverlay.isToolActive = true
            window?.makeFirstResponder(annotationOverlay)
        } else {
            toolMode = .none
            annotationOverlay.isToolActive = false
        }
        sidebar.setToolMode(toolMode)
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
            self.writeImage(self.rendered(), to: url)
        }
    }

    // MARK: - Prefs

    private func savePrefs() {
        saveDouble(Double(borderWeight),  key: Prefs.borderWeight)
        saveColor(borderColor,            key: Prefs.borderColor)
        UserDefaults.standard.set(borderEnabled, forKey: Prefs.borderEnabled)
        saveDouble(Double(shadowOffsetX), key: Prefs.shadowX)
        saveDouble(Double(shadowOffsetY), key: Prefs.shadowY)
        saveDouble(Double(shadowBlur),    key: Prefs.shadowBlur)
        saveColor(shadowColor,            key: Prefs.shadowColor)
        saveDouble(Double(shadowOpacity), key: Prefs.shadowOpacity)
        UserDefaults.standard.set(shadowEnabled, forKey: Prefs.shadowEnabled)
        saveDouble(Double(arrowWeight),   key: Prefs.arrowWeight)
        saveColor(arrowColor,             key: Prefs.arrowColor)
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

    init(arrowWeightSlider: NSSlider, arrowWeightLabel: NSTextField, arrowColorWell: NSColorWell) {
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
        ps.documentView = propertiesStack
        ps.translatesAutoresizingMaskIntoConstraints = false
        propertiesScroll = ps

        let es = NSScrollView()
        es.hasVerticalScroller = true; es.autohidesScrollers = true
        es.drawsBackground = false
        es.documentView = effectsStack
        es.translatesAutoresizingMaskIntoConstraints = false
        effectsScroll = es

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
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

            propertiesStack.topAnchor.constraint(equalTo: ps.contentView.topAnchor),
            propertiesStack.widthAnchor.constraint(equalTo: ps.contentView.widthAnchor),
            effectsStack.topAnchor.constraint(equalTo: es.contentView.topAnchor),
            effectsStack.widthAnchor.constraint(equalTo: es.contentView.widthAnchor),
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

        // ── Properties: arrow tool section (hidden until arrow tool active) ──────
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
        arrowPropViews.forEach { $0.isHidden = !isArrow }
        // Auto-switch to Properties tab when a tool activates
        if mode != .none && tabControl.selectedSegment != 0 {
            tabControl.selectedSegment = 0
            propertiesScroll.isHidden = false
            effectsScroll.isHidden = true
        }
    }

    // MARK: Effects panel builders (called from EditorWindowController)

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

    // MARK: Private row/section builders

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

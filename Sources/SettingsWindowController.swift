import AppKit
import Carbon.HIToolbox

// MARK: - Delegate

protocol SettingsWindowControllerDelegate: AnyObject {
    func settingsDidUpdateHotkey(_ config: HotkeyConfig)
    func settingsDidUpdateQuickHotkey(_ config: HotkeyConfig)
    func settingsDidUpdateToolShortcuts(_ shortcuts: ToolShortcutsConfig)
}

// MARK: - SettingsWindowController

class SettingsWindowController: NSWindowController {
    weak var delegate: SettingsWindowControllerDelegate?

    private var currentConfig:        HotkeyConfig
    private var currentQuickConfig:   HotkeyConfig
    private var currentToolShortcuts: ToolShortcutsConfig

    private var hotkeyRecorder:      HotkeyRecorderView!
    private var quickHotkeyRecorder: HotkeyRecorderView!
    private var previewLabel:        NSTextField!
    private var quickPreviewLabel:   NSTextField!

    private var cropRecorder:      HotkeyRecorderView!
    private var resizeRecorder:    HotkeyRecorderView!
    private var ocrRecorder:       HotkeyRecorderView!
    private var arrowRecorder:     HotkeyRecorderView!
    private var textRecorder:      HotkeyRecorderView!
    private var shapeRecorder:     HotkeyRecorderView!
    private var blurRecorder:       HotkeyRecorderView!
    private var highlightRecorder:  HotkeyRecorderView!
    private var spotlightRecorder:  HotkeyRecorderView!
    private var stepRecorder:       HotkeyRecorderView!

    private static var shared: SettingsWindowController?

    static func show(currentConfig: HotkeyConfig,
                     quickConfig: HotkeyConfig,
                     toolShortcuts: ToolShortcutsConfig,
                     delegate: SettingsWindowControllerDelegate) {
        if shared == nil {
            shared = SettingsWindowController(config: currentConfig,
                                              quickConfig: quickConfig,
                                              toolShortcuts: toolShortcuts)
        }
        shared?.currentConfig        = currentConfig
        shared?.currentQuickConfig   = quickConfig
        shared?.currentToolShortcuts = toolShortcuts
        shared?.delegate = delegate
        shared?.refreshUI()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    init(config: HotkeyConfig, quickConfig: HotkeyConfig, toolShortcuts: ToolShortcutsConfig) {
        self.currentConfig        = config
        self.currentQuickConfig   = quickConfig
        self.currentToolShortcuts = toolShortcuts

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Grabbit Settings"
        win.center()
        win.isReleasedWhenClosed = false

        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // ── Capture shortcuts section header ─────────────────────────────────────
        let sectionLabel = NSTextField(labelWithString: "Keyboard Shortcuts")
        sectionLabel.font = .boldSystemFont(ofSize: 13)
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sectionLabel)

        let descLabel = NSTextField(labelWithString: "Click a field and press your desired shortcut.")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(descLabel)

        // ── Capture (editor) row ─────────────────────────────────────────────────
        let captureRowLabel = NSTextField(labelWithString: "Capture & Edit")
        captureRowLabel.font = .systemFont(ofSize: 12)
        captureRowLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(captureRowLabel)

        hotkeyRecorder = HotkeyRecorderView(config: currentConfig)
        hotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder.onConfigChanged = { [weak self] newConfig in
            self?.currentConfig = newConfig
            self?.refreshPreview()
        }
        cv.addSubview(hotkeyRecorder)

        previewLabel = NSTextField(labelWithString: "")
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(previewLabel)

        // ── Quick Capture (clipboard) row ────────────────────────────────────────
        let quickRowLabel = NSTextField(labelWithString: "Quick Capture")
        quickRowLabel.font = .systemFont(ofSize: 12)
        quickRowLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(quickRowLabel)

        let quickDescLabel = NSTextField(labelWithString: "Copies region directly to clipboard, no editor.")
        quickDescLabel.font = .systemFont(ofSize: 10)
        quickDescLabel.textColor = .secondaryLabelColor
        quickDescLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(quickDescLabel)

        quickHotkeyRecorder = HotkeyRecorderView(config: currentQuickConfig)
        quickHotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        quickHotkeyRecorder.onConfigChanged = { [weak self] newConfig in
            self?.currentQuickConfig = newConfig
            self?.refreshPreview()
        }
        cv.addSubview(quickHotkeyRecorder)

        quickPreviewLabel = NSTextField(labelWithString: "")
        quickPreviewLabel.font = .systemFont(ofSize: 12)
        quickPreviewLabel.textColor = .secondaryLabelColor
        quickPreviewLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(quickPreviewLabel)

        // ── Separator ────────────────────────────────────────────────────────────
        let sep = NSBox()
        sep.boxType = .custom; sep.borderWidth = 0
        sep.fillColor = NSColor.separatorColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sep)

        // ── Tool shortcuts section header ─────────────────────────────────────────
        let toolSectionLabel = NSTextField(labelWithString: "Tool Shortcuts")
        toolSectionLabel.font = .boldSystemFont(ofSize: 13)
        toolSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(toolSectionLabel)

        let toolDescLabel = NSTextField(labelWithString: "Active while the editor window is focused.")
        toolDescLabel.font = .systemFont(ofSize: 11)
        toolDescLabel.textColor = .secondaryLabelColor
        toolDescLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(toolDescLabel)

        // ── Tool rows ─────────────────────────────────────────────────────────────
        func makeRowLabel(_ title: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: title)
            lbl.font = .systemFont(ofSize: 12)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(lbl)
            return lbl
        }
        func makeRecorder(_ config: HotkeyConfig) -> HotkeyRecorderView {
            let rec = HotkeyRecorderView(config: config)
            rec.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(rec)
            return rec
        }

        let cropLabel      = makeRowLabel("Crop")
        cropRecorder       = makeRecorder(currentToolShortcuts.crop)
        cropRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.crop = cfg }

        let resizeLabel    = makeRowLabel("Resize")
        resizeRecorder     = makeRecorder(currentToolShortcuts.resize)
        resizeRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.resize = cfg }

        let ocrLabel       = makeRowLabel("Extract Text")
        ocrRecorder        = makeRecorder(currentToolShortcuts.ocr)
        ocrRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.ocr = cfg }

        let arrowLabel     = makeRowLabel("Arrow")
        arrowRecorder      = makeRecorder(currentToolShortcuts.arrow)
        arrowRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.arrow = cfg }

        let textLabel      = makeRowLabel("Text")
        textRecorder       = makeRecorder(currentToolShortcuts.text)
        textRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.text = cfg }

        let shapeLabel     = makeRowLabel("Shape")
        shapeRecorder      = makeRecorder(currentToolShortcuts.shape)
        shapeRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.shape = cfg }

        let blurLabel      = makeRowLabel("Blur")
        blurRecorder       = makeRecorder(currentToolShortcuts.blur)
        blurRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.blur = cfg }

        let highlightLabel = makeRowLabel("Highlight")
        highlightRecorder  = makeRecorder(currentToolShortcuts.highlight)
        highlightRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.highlight = cfg }

        let spotlightLabel = makeRowLabel("Spotlight")
        spotlightRecorder  = makeRecorder(currentToolShortcuts.spotlight)
        spotlightRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.spotlight = cfg }

        let stepLabel = makeRowLabel("Step")
        stepRecorder  = makeRecorder(currentToolShortcuts.step)
        stepRecorder.onConfigChanged = { [weak self] cfg in guard let self else { return }; self.currentToolShortcuts.step = cfg }

        // ── Buttons ──────────────────────────────────────────────────────────────
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(saveButton)

        // ── Layout ───────────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Capture shortcuts header
            sectionLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            sectionLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),

            descLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            descLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            // Capture & Edit row
            captureRowLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 14),
            captureRowLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            captureRowLabel.widthAnchor.constraint(equalToConstant: 100),

            hotkeyRecorder.centerYAnchor.constraint(equalTo: captureRowLabel.centerYAnchor),
            hotkeyRecorder.leadingAnchor.constraint(equalTo: captureRowLabel.trailingAnchor, constant: 8),
            hotkeyRecorder.widthAnchor.constraint(equalToConstant: 140),
            hotkeyRecorder.heightAnchor.constraint(equalToConstant: 26),

            previewLabel.centerYAnchor.constraint(equalTo: hotkeyRecorder.centerYAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: hotkeyRecorder.trailingAnchor, constant: 10),

            // Quick Capture row
            quickRowLabel.topAnchor.constraint(equalTo: captureRowLabel.bottomAnchor, constant: 16),
            quickRowLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            quickRowLabel.widthAnchor.constraint(equalToConstant: 100),

            quickHotkeyRecorder.centerYAnchor.constraint(equalTo: quickRowLabel.centerYAnchor),
            quickHotkeyRecorder.leadingAnchor.constraint(equalTo: quickRowLabel.trailingAnchor, constant: 8),
            quickHotkeyRecorder.widthAnchor.constraint(equalToConstant: 140),
            quickHotkeyRecorder.heightAnchor.constraint(equalToConstant: 26),

            quickPreviewLabel.centerYAnchor.constraint(equalTo: quickHotkeyRecorder.centerYAnchor),
            quickPreviewLabel.leadingAnchor.constraint(equalTo: quickHotkeyRecorder.trailingAnchor, constant: 10),

            quickDescLabel.topAnchor.constraint(equalTo: quickRowLabel.bottomAnchor, constant: 4),
            quickDescLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            quickDescLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            // Separator
            sep.topAnchor.constraint(equalTo: quickDescLabel.bottomAnchor, constant: 16),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            sep.heightAnchor.constraint(equalToConstant: 1),

            // Tool shortcuts header
            toolSectionLabel.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 14),
            toolSectionLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),

            toolDescLabel.topAnchor.constraint(equalTo: toolSectionLabel.bottomAnchor, constant: 4),
            toolDescLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            toolDescLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            // Crop row
            cropLabel.topAnchor.constraint(equalTo: toolDescLabel.bottomAnchor, constant: 12),
            cropLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            cropLabel.widthAnchor.constraint(equalToConstant: 100),
            cropRecorder.centerYAnchor.constraint(equalTo: cropLabel.centerYAnchor),
            cropRecorder.leadingAnchor.constraint(equalTo: cropLabel.trailingAnchor, constant: 8),
            cropRecorder.widthAnchor.constraint(equalToConstant: 120),
            cropRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Resize row
            resizeLabel.topAnchor.constraint(equalTo: cropRecorder.bottomAnchor, constant: 8),
            resizeLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            resizeLabel.widthAnchor.constraint(equalToConstant: 100),
            resizeRecorder.centerYAnchor.constraint(equalTo: resizeLabel.centerYAnchor),
            resizeRecorder.leadingAnchor.constraint(equalTo: resizeLabel.trailingAnchor, constant: 8),
            resizeRecorder.widthAnchor.constraint(equalToConstant: 120),
            resizeRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Extract Text row
            ocrLabel.topAnchor.constraint(equalTo: resizeRecorder.bottomAnchor, constant: 8),
            ocrLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            ocrLabel.widthAnchor.constraint(equalToConstant: 100),
            ocrRecorder.centerYAnchor.constraint(equalTo: ocrLabel.centerYAnchor),
            ocrRecorder.leadingAnchor.constraint(equalTo: ocrLabel.trailingAnchor, constant: 8),
            ocrRecorder.widthAnchor.constraint(equalToConstant: 120),
            ocrRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Arrow row
            arrowLabel.topAnchor.constraint(equalTo: ocrRecorder.bottomAnchor, constant: 8),
            arrowLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            arrowLabel.widthAnchor.constraint(equalToConstant: 100),
            arrowRecorder.centerYAnchor.constraint(equalTo: arrowLabel.centerYAnchor),
            arrowRecorder.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: 8),
            arrowRecorder.widthAnchor.constraint(equalToConstant: 120),
            arrowRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Text row
            textLabel.topAnchor.constraint(equalTo: arrowRecorder.bottomAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            textLabel.widthAnchor.constraint(equalToConstant: 100),
            textRecorder.centerYAnchor.constraint(equalTo: textLabel.centerYAnchor),
            textRecorder.leadingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 8),
            textRecorder.widthAnchor.constraint(equalToConstant: 120),
            textRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Shape row
            shapeLabel.topAnchor.constraint(equalTo: textRecorder.bottomAnchor, constant: 8),
            shapeLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            shapeLabel.widthAnchor.constraint(equalToConstant: 100),
            shapeRecorder.centerYAnchor.constraint(equalTo: shapeLabel.centerYAnchor),
            shapeRecorder.leadingAnchor.constraint(equalTo: shapeLabel.trailingAnchor, constant: 8),
            shapeRecorder.widthAnchor.constraint(equalToConstant: 120),
            shapeRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Blur row
            blurLabel.topAnchor.constraint(equalTo: shapeRecorder.bottomAnchor, constant: 8),
            blurLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            blurLabel.widthAnchor.constraint(equalToConstant: 100),
            blurRecorder.centerYAnchor.constraint(equalTo: blurLabel.centerYAnchor),
            blurRecorder.leadingAnchor.constraint(equalTo: blurLabel.trailingAnchor, constant: 8),
            blurRecorder.widthAnchor.constraint(equalToConstant: 120),
            blurRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Highlight row
            highlightLabel.topAnchor.constraint(equalTo: blurRecorder.bottomAnchor, constant: 8),
            highlightLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            highlightLabel.widthAnchor.constraint(equalToConstant: 100),
            highlightRecorder.centerYAnchor.constraint(equalTo: highlightLabel.centerYAnchor),
            highlightRecorder.leadingAnchor.constraint(equalTo: highlightLabel.trailingAnchor, constant: 8),
            highlightRecorder.widthAnchor.constraint(equalToConstant: 120),
            highlightRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Spotlight row
            spotlightLabel.topAnchor.constraint(equalTo: highlightRecorder.bottomAnchor, constant: 8),
            spotlightLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            spotlightLabel.widthAnchor.constraint(equalToConstant: 100),
            spotlightRecorder.centerYAnchor.constraint(equalTo: spotlightLabel.centerYAnchor),
            spotlightRecorder.leadingAnchor.constraint(equalTo: spotlightLabel.trailingAnchor, constant: 8),
            spotlightRecorder.widthAnchor.constraint(equalToConstant: 120),
            spotlightRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Step row
            stepLabel.topAnchor.constraint(equalTo: spotlightRecorder.bottomAnchor, constant: 8),
            stepLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            stepLabel.widthAnchor.constraint(equalToConstant: 100),
            stepRecorder.centerYAnchor.constraint(equalTo: stepLabel.centerYAnchor),
            stepRecorder.leadingAnchor.constraint(equalTo: stepLabel.trailingAnchor, constant: 8),
            stepRecorder.widthAnchor.constraint(equalToConstant: 120),
            stepRecorder.heightAnchor.constraint(equalToConstant: 26),

            // Buttons
            cancelButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),

            saveButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
        ])

        refreshPreview()
    }

    private func refreshUI() {
        hotkeyRecorder?.setConfig(currentConfig)
        quickHotkeyRecorder?.setConfig(currentQuickConfig)
        cropRecorder?.setConfig(currentToolShortcuts.crop)
        resizeRecorder?.setConfig(currentToolShortcuts.resize)
        ocrRecorder?.setConfig(currentToolShortcuts.ocr)
        arrowRecorder?.setConfig(currentToolShortcuts.arrow)
        textRecorder?.setConfig(currentToolShortcuts.text)
        shapeRecorder?.setConfig(currentToolShortcuts.shape)
        blurRecorder?.setConfig(currentToolShortcuts.blur)
        highlightRecorder?.setConfig(currentToolShortcuts.highlight)
        spotlightRecorder?.setConfig(currentToolShortcuts.spotlight)
        stepRecorder?.setConfig(currentToolShortcuts.step)
        refreshPreview()
    }

    private func refreshPreview() {
        previewLabel?.stringValue      = currentConfig.displayString
        quickPreviewLabel?.stringValue = currentQuickConfig.displayString
    }

    // MARK: - Actions

    @objc private func cancel() { close() }

    @objc private func save() {
        delegate?.settingsDidUpdateHotkey(currentConfig)
        delegate?.settingsDidUpdateQuickHotkey(currentQuickConfig)
        delegate?.settingsDidUpdateToolShortcuts(currentToolShortcuts)
        close()
    }
}

// MARK: - HotkeyRecorderView

/// A field that captures the next key combination pressed while it has focus.
class HotkeyRecorderView: NSView {
    var onConfigChanged: ((HotkeyConfig) -> Void)?

    private var config: HotkeyConfig
    private var isRecording = false
    private var label: NSTextField!
    private var localMonitor: Any?

    init(config: HotkeyConfig) {
        self.config = config
        super.init(frame: .zero)
        buildUI()
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setConfig(_ config: HotkeyConfig) {
        self.config = config
        updateLabel()
    }

    // MARK: Private

    private func buildUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func updateLabel() {
        if isRecording {
            label.stringValue = "Press shortcut…"
            label.textColor = .secondaryLabelColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        } else {
            label.stringValue = config.displayString
            label.textColor = .labelColor
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        updateLabel()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        updateLabel()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return }
        let carbonMods = carbonModifiers(from: event.modifierFlags)
        let hasModifier = (carbonMods & UInt32(cmdKey | optionKey | controlKey)) != 0
        guard hasModifier else { return }
        let newConfig = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
        config = newConfig
        stopRecording()
        onConfigChanged?(newConfig)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }
}

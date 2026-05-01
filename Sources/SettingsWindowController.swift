import AppKit
import Carbon.HIToolbox

// MARK: - Delegate

protocol SettingsWindowControllerDelegate: AnyObject {
    func settingsDidUpdateHotkey(_ config: HotkeyConfig)
    func settingsDidUpdateQuickHotkey(_ config: HotkeyConfig)
}

// MARK: - SettingsWindowController

class SettingsWindowController: NSWindowController {
    weak var delegate: SettingsWindowControllerDelegate?

    private var currentConfig:      HotkeyConfig
    private var currentQuickConfig: HotkeyConfig
    private var hotkeyRecorder:      HotkeyRecorderView!
    private var quickHotkeyRecorder: HotkeyRecorderView!
    private var previewLabel:      NSTextField!
    private var quickPreviewLabel: NSTextField!

    private static var shared: SettingsWindowController?

    static func show(currentConfig: HotkeyConfig,
                     quickConfig: HotkeyConfig,
                     delegate: SettingsWindowControllerDelegate) {
        if shared == nil {
            shared = SettingsWindowController(config: currentConfig, quickConfig: quickConfig)
        }
        shared?.currentConfig      = currentConfig
        shared?.currentQuickConfig = quickConfig
        shared?.delegate = delegate
        shared?.refreshUI()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    init(config: HotkeyConfig, quickConfig: HotkeyConfig) {
        self.currentConfig      = config
        self.currentQuickConfig = quickConfig

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
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

        // ── Section header ───────────────────────────────────────────────────────
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
            sectionLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            sectionLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),

            descLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            descLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            // Capture & Edit row
            captureRowLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            captureRowLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            captureRowLabel.widthAnchor.constraint(equalToConstant: 100),

            hotkeyRecorder.centerYAnchor.constraint(equalTo: captureRowLabel.centerYAnchor),
            hotkeyRecorder.leadingAnchor.constraint(equalTo: captureRowLabel.trailingAnchor, constant: 8),
            hotkeyRecorder.widthAnchor.constraint(equalToConstant: 140),
            hotkeyRecorder.heightAnchor.constraint(equalToConstant: 28),

            previewLabel.centerYAnchor.constraint(equalTo: hotkeyRecorder.centerYAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: hotkeyRecorder.trailingAnchor, constant: 10),

            // Quick Capture row
            quickRowLabel.topAnchor.constraint(equalTo: captureRowLabel.bottomAnchor, constant: 20),
            quickRowLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            quickRowLabel.widthAnchor.constraint(equalToConstant: 100),

            quickHotkeyRecorder.centerYAnchor.constraint(equalTo: quickRowLabel.centerYAnchor),
            quickHotkeyRecorder.leadingAnchor.constraint(equalTo: quickRowLabel.trailingAnchor, constant: 8),
            quickHotkeyRecorder.widthAnchor.constraint(equalToConstant: 140),
            quickHotkeyRecorder.heightAnchor.constraint(equalToConstant: 28),

            quickPreviewLabel.centerYAnchor.constraint(equalTo: quickHotkeyRecorder.centerYAnchor),
            quickPreviewLabel.leadingAnchor.constraint(equalTo: quickHotkeyRecorder.trailingAnchor, constant: 10),

            quickDescLabel.topAnchor.constraint(equalTo: quickRowLabel.bottomAnchor, constant: 4),
            quickDescLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            quickDescLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

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

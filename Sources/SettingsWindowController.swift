import AppKit
import Carbon.HIToolbox

// MARK: - Delegate

protocol SettingsWindowControllerDelegate: AnyObject {
    func settingsDidUpdateHotkey(_ config: HotkeyConfig)
}

// MARK: - SettingsWindowController

class SettingsWindowController: NSWindowController {
    weak var delegate: SettingsWindowControllerDelegate?

    private var currentConfig: HotkeyConfig
    private var hotkeyRecorder: HotkeyRecorderView!
    private var previewLabel: NSTextField!

    private static var shared: SettingsWindowController?

    static func show(currentConfig: HotkeyConfig, delegate: SettingsWindowControllerDelegate) {
        if shared == nil {
            shared = SettingsWindowController(config: currentConfig)
        }
        shared?.currentConfig = currentConfig
        shared?.delegate = delegate
        shared?.refreshUI()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    init(config: HotkeyConfig) {
        self.currentConfig = config

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
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
        guard let contentView = window?.contentView else { return }

        // Section label
        let sectionLabel = NSTextField(labelWithString: "Keyboard Shortcut")
        sectionLabel.font = .boldSystemFont(ofSize: 13)
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sectionLabel)

        let descLabel = NSTextField(labelWithString: "Click the field below and press your desired shortcut.")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descLabel)

        // Hotkey recorder
        hotkeyRecorder = HotkeyRecorderView(config: currentConfig)
        hotkeyRecorder.translatesAutoresizingMaskIntoConstraints = false
        hotkeyRecorder.onConfigChanged = { [weak self] newConfig in
            self?.currentConfig = newConfig
            self?.refreshPreview()
        }
        contentView.addSubview(hotkeyRecorder)

        // Preview label
        previewLabel = NSTextField(labelWithString: "")
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewLabel)

        // Buttons
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(saveButton)

        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            sectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            descLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            hotkeyRecorder.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 12),
            hotkeyRecorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hotkeyRecorder.widthAnchor.constraint(equalToConstant: 160),
            hotkeyRecorder.heightAnchor.constraint(equalToConstant: 28),

            previewLabel.centerYAnchor.constraint(equalTo: hotkeyRecorder.centerYAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: hotkeyRecorder.trailingAnchor, constant: 12),

            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),

            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])

        refreshPreview()
    }

    private func refreshUI() {
        hotkeyRecorder?.setConfig(currentConfig)
        refreshPreview()
    }

    private func refreshPreview() {
        previewLabel?.stringValue = currentConfig.displayString
    }

    // MARK: - Actions

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        delegate?.settingsDidUpdateHotkey(currentConfig)
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

    // MARK: Mouse / focus

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        updateLabel()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handleKeyEvent(event)
            return nil  // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        updateLabel()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Escape cancels recording without changing the shortcut
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let carbonMods = carbonModifiers(from: event.modifierFlags)

        // Require at least one modifier (other than Shift alone)
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

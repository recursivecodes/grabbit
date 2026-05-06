import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey configuration

struct HotkeyConfig: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon modifier flags

    // Default: Opt+Shift+P  (editor capture)
    static let defaultConfig = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(optionKey | shiftKey)
    )

    // Default: Opt+P  (quick copy-to-clipboard capture)
    static let defaultQuickConfig = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(optionKey)
    )

    // UserDefaults keys
    private static let keyCodeKey   = "grabbit.hotkeyKeyCode"
    private static let modifiersKey = "grabbit.hotkeyModifiers"
    private static let quickKeyCodeKey   = "grabbit.quickHotkeyKeyCode"
    private static let quickModifiersKey = "grabbit.quickHotkeyModifiers"

    static func load() -> HotkeyConfig {
        let ud = UserDefaults.standard
        guard ud.object(forKey: keyCodeKey) != nil else { return .defaultConfig }
        return HotkeyConfig(
            keyCode:   UInt32(ud.integer(forKey: keyCodeKey)),
            modifiers: UInt32(ud.integer(forKey: modifiersKey))
        )
    }

    static func loadQuick() -> HotkeyConfig {
        let ud = UserDefaults.standard
        guard ud.object(forKey: quickKeyCodeKey) != nil else { return .defaultQuickConfig }
        return HotkeyConfig(
            keyCode:   UInt32(ud.integer(forKey: quickKeyCodeKey)),
            modifiers: UInt32(ud.integer(forKey: quickModifiersKey))
        )
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(Int(keyCode),   forKey: HotkeyConfig.keyCodeKey)
        ud.set(Int(modifiers), forKey: HotkeyConfig.modifiersKey)
    }

    func saveQuick() {
        let ud = UserDefaults.standard
        ud.set(Int(keyCode),   forKey: HotkeyConfig.quickKeyCodeKey)
        ud.set(Int(modifiers), forKey: HotkeyConfig.quickModifiersKey)
    }

    /// Single character used as NSMenuItem.keyEquivalent (lowercase letter or symbol).
    var menuKeyEquivalent: String { keyName(for: keyCode).lowercased() }

    /// NSEvent.ModifierFlags matching this config's modifier set, for NSMenuItem.
    var menuModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// Human-readable string, e.g. "⌥⇧P"
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    private func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:      return "?"
        }
    }
}

// MARK: - Global C callback
// Routes by hotkey ID: 1 = editor capture, 2 = quick clipboard capture.

private var _hotkeyCallbacks: [UInt32: () -> Void] = [:]

private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let id = hotKeyID.id
    DispatchQueue.main.async { _hotkeyCallbacks[id]?() }
    return noErr
}

// MARK: - HotkeyManager

class HotkeyManager {
    private var hotKeyRef:      EventHotKeyRef?
    private var quickHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private(set) var config:      HotkeyConfig
    private(set) var quickConfig: HotkeyConfig

    init(config: HotkeyConfig = .load(),
         quickConfig: HotkeyConfig = .loadQuick(),
         onCapture: @escaping () -> Void,
         onQuickCapture: @escaping () -> Void) {
        self.config      = config
        self.quickConfig = quickConfig
        _hotkeyCallbacks[1] = onCapture
        _hotkeyCallbacks[2] = onQuickCapture
        installHandler()
        register(config: config,      ref: &hotKeyRef,      id: 1)
        register(config: quickConfig, ref: &quickHotKeyRef, id: 2)
    }

    /// Update the editor-capture hotkey.
    func update(config: HotkeyConfig) {
        unregister(&hotKeyRef)
        self.config = config
        config.save()
        register(config: config, ref: &hotKeyRef, id: 1)
    }

    /// Update the quick-capture hotkey.
    func updateQuick(config: HotkeyConfig) {
        unregister(&quickHotKeyRef)
        self.quickConfig = config
        config.saveQuick()
        register(config: config, ref: &quickHotKeyRef, id: 2)
    }

    // MARK: Private

    private func installHandler() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler,
                            1, &spec, nil, &eventHandlerRef)
    }

    private func register(config: HotkeyConfig, ref: inout EventHotKeyRef?, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: 0x67726162, id: id)
        RegisterEventHotKey(config.keyCode, config.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    private func unregister(_ ref: inout EventHotKeyRef?) {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }
}

// MARK: - Tool shortcut configuration

struct ToolShortcutsConfig {
    var crop:      HotkeyConfig
    var resize:    HotkeyConfig
    var ocr:       HotkeyConfig
    var arrow:     HotkeyConfig
    var text:      HotkeyConfig
    var shape:     HotkeyConfig
    var blur:      HotkeyConfig
    var highlight: HotkeyConfig
    var spotlight: HotkeyConfig
    var step:      HotkeyConfig

    static let `default` = ToolShortcutsConfig(
        crop:      HotkeyConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | shiftKey)),
        resize:    HotkeyConfig(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey)),
        ocr:       HotkeyConfig(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(optionKey | shiftKey)),
        arrow:     HotkeyConfig(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | shiftKey)),
        text:      HotkeyConfig(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey | shiftKey)),
        shape:     HotkeyConfig(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey)),
        blur:      HotkeyConfig(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey | shiftKey)),
        highlight: HotkeyConfig(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(optionKey | shiftKey)),
        spotlight: HotkeyConfig(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey | shiftKey)),
        step:      HotkeyConfig(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey))
    )

    private static let prefix = "grabbit.toolShortcut."

    static func load() -> ToolShortcutsConfig {
        let ud = UserDefaults.standard
        let d  = Self.default
        func loadTool(_ name: String, fallback: HotkeyConfig) -> HotkeyConfig {
            let kcKey = "\(prefix)\(name).keyCode"
            let mKey  = "\(prefix)\(name).modifiers"
            guard ud.object(forKey: kcKey) != nil else { return fallback }
            return HotkeyConfig(keyCode:   UInt32(ud.integer(forKey: kcKey)),
                                modifiers: UInt32(ud.integer(forKey: mKey)))
        }
        return ToolShortcutsConfig(
            crop:      loadTool("crop",      fallback: d.crop),
            resize:    loadTool("resize",    fallback: d.resize),
            ocr:       loadTool("ocr",       fallback: d.ocr),
            arrow:     loadTool("arrow",     fallback: d.arrow),
            text:      loadTool("text",      fallback: d.text),
            shape:     loadTool("shape",     fallback: d.shape),
            blur:      loadTool("blur",      fallback: d.blur),
            highlight: loadTool("highlight", fallback: d.highlight),
            spotlight: loadTool("spotlight", fallback: d.spotlight),
            step:      loadTool("step",      fallback: d.step)
        )
    }

    func save() {
        let ud = UserDefaults.standard
        func saveTool(_ name: String, _ cfg: HotkeyConfig) {
            ud.set(Int(cfg.keyCode),   forKey: "\(ToolShortcutsConfig.prefix)\(name).keyCode")
            ud.set(Int(cfg.modifiers), forKey: "\(ToolShortcutsConfig.prefix)\(name).modifiers")
        }
        saveTool("crop",      crop)
        saveTool("resize",    resize)
        saveTool("ocr",       ocr)
        saveTool("arrow",     arrow)
        saveTool("text",      text)
        saveTool("shape",     shape)
        saveTool("blur",      blur)
        saveTool("highlight", highlight)
        saveTool("spotlight", spotlight)
        saveTool("step",      step)
    }
}

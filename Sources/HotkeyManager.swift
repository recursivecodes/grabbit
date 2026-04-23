import Carbon.HIToolbox

// Must be a global (non-capturing) function to serve as a C function pointer.
private var _hotkeyCallback: (() -> Void)?

private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { _hotkeyCallback?() }
    return noErr
}

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?

    init(callback: @escaping () -> Void) {
        _hotkeyCallback = callback

        // 'grab' as a FourCharCode
        let hotKeyID = EventHotKeyID(signature: 0x67726162, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, nil)
    }
}

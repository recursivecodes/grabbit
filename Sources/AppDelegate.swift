import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, SettingsWindowControllerDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var captureMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusBar()
        hotkeyManager = HotkeyManager(callback: startCapture)
        updateCaptureMenuTitle()
        requestScreenRecordingPermission()
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Grabbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save As…", action: Selector(("saveAs:")), keyEquivalent: "S")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status item

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hare.fill",
                                           accessibilityDescription: "Grabbit")

        let menu = NSMenu()

        captureMenuItem = NSMenuItem(title: "", action: #selector(startCapture), keyEquivalent: "")
        menu.addItem(captureMenuItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Grabbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        statusItem.menu = menu
    }

    /// Keeps the menu item title in sync with the current hotkey config.
    private func updateCaptureMenuTitle() {
        let shortcut = hotkeyManager.config.displayString
        captureMenuItem.title = "Capture  \(shortcut)"
        statusItem.button?.toolTip = "Grabbit (\(shortcut))"
    }

    // MARK: - Capture

    private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc func startCapture() {
        CaptureSession.start()
    }

    // MARK: - Settings

    @objc private func openSettings() {
        SettingsWindowController.show(currentConfig: hotkeyManager.config, delegate: self)
    }

    // MARK: - SettingsWindowControllerDelegate

    func settingsDidUpdateHotkey(_ config: HotkeyConfig) {
        hotkeyManager.update(config: config)
        updateCaptureMenuTitle()
    }
}

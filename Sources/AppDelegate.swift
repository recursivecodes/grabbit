import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, SettingsWindowControllerDelegate,
                   UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var captureMenuItem: NSMenuItem!
    private var quickCaptureMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Become the notification delegate so banners appear on screen.
        UNUserNotificationCenter.current().delegate = self
        setupMainMenu()
        setupStatusBar()
        hotkeyManager = HotkeyManager(
            onCapture:      startCapture,
            onQuickCapture: startQuickCapture
        )
        updateCaptureMenuTitles()
        requestScreenRecordingPermission()
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        // Cmd+Q closes the front editor window but keeps Grabbit running in
        // the menu bar. To fully quit, use "Quit Grabbit" in the status bar menu.
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save As…", action: Selector(("saveAs:")), keyEquivalent: "S")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Edit menu — required for Cmd+Z/Shift+Cmd+Z to flow through the responder chain
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

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

        quickCaptureMenuItem = NSMenuItem(title: "", action: #selector(startQuickCapture), keyEquivalent: "")
        menu.addItem(quickCaptureMenuItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Grabbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        statusItem.menu = menu
    }

    private func updateCaptureMenuTitles() {
        let shortcut      = hotkeyManager.config.displayString
        let quickShortcut = hotkeyManager.quickConfig.displayString
        captureMenuItem.title      = "Capture  \(shortcut)"
        quickCaptureMenuItem.title = "Quick Capture  \(quickShortcut)"
        statusItem.button?.toolTip = "Grabbit (\(shortcut))"
    }

    // MARK: - Capture

    private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc func startCapture()      { CaptureSession.start() }
    @objc func startQuickCapture() { CaptureSession.startQuick() }

    // MARK: - Settings

    @objc private func openSettings() {
        SettingsWindowController.show(
            currentConfig: hotkeyManager.config,
            quickConfig:   hotkeyManager.quickConfig,
            delegate:      self
        )
    }

    // MARK: - NSApplicationDelegate

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - SettingsWindowControllerDelegate

    func settingsDidUpdateHotkey(_ config: HotkeyConfig) {
        hotkeyManager.update(config: config)
        updateCaptureMenuTitles()
    }

    func settingsDidUpdateQuickHotkey(_ config: HotkeyConfig) {
        hotkeyManager.updateQuick(config: config)
        updateCaptureMenuTitles()
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Show banners even when the app is active.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    // Notification clicked — no action needed, just call the handler.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

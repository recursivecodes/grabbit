import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusBar()
        hotkeyManager = HotkeyManager(callback: startCapture)
        requestScreenRecordingPermission()
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (first item is always the application menu)
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Grabbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        // Uppercase "S" → Cmd+Shift+S per AppKit convention
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
        menu.addItem(withTitle: "Capture  ⌘⇧P", action: #selector(startCapture), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Grabbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
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
}

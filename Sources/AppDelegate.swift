import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, SettingsWindowControllerDelegate,
                   UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var captureMenuItem: NSMenuItem!
    private var quickCaptureMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem?
    private var latestReleaseURL: String?
    // Ordered: crop, resize, ocr, arrow, text, shape, blur, highlight
    private var toolMenuItems: [NSMenuItem] = []

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
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            self.checkForUpdates()
        }
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Grabbit", action: #selector(openAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…",     action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window",  action: #selector(closeCurrentWindow), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openFile), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "New from Clipboard", action: #selector(newFromClipboard), keyEquivalent: "n")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Image", action: Selector(("closeImage:")), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: Selector(("save:")), keyEquivalent: "s")
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

        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsItem.submenu = buildToolsMenu()
        mainMenu.addItem(toolsItem)

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
        menu.addItem(withTitle: "Open Editor", action: #selector(openEditor), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Grabbit", action: #selector(openAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Grabbit", action: #selector(quitGrabbit), keyEquivalent: "")

        statusItem.menu = menu
    }

    // MARK: - Update check

    private func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/recursivecodes/grabbit/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let releaseURL = json["html_url"] as? String else { return }

            let latest  = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

            guard self.isVersion(latest, newerThan: current) else { return }

            DispatchQueue.main.async {
                self.latestReleaseURL = releaseURL
                self.showUpdateMenuItem(version: latest)
            }
        }.resume()
    }

    /// Compares two dot-separated version strings numerically, segment by segment.
    /// Returns true if `a` is strictly greater than `b`.
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let segmentsA = a.split(separator: ".").map { Int($0) ?? 0 }
        let segmentsB = b.split(separator: ".").map { Int($0) ?? 0 }
        let length = max(segmentsA.count, segmentsB.count)
        for i in 0..<length {
            let va = i < segmentsA.count ? segmentsA[i] : 0
            let vb = i < segmentsB.count ? segmentsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }

    private func showUpdateMenuItem(version: String) {
        guard let menu = statusItem.menu else { return }

        // Remove any existing update item first (e.g. if called again somehow)
        if let existing = updateMenuItem {
            menu.removeItem(existing)
        }

        let item = NSMenuItem(
            title: "⬆ Update Available (\(version))",
            action: #selector(openReleasePage),
            keyEquivalent: ""
        )
        // Insert at the top of the menu, before the capture items
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        updateMenuItem = item
    }

    @objc private func openReleasePage() {
        guard let urlString = latestReleaseURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
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

    @objc private func closeCurrentWindow() {
        guard let editor = NSApp.keyWindow?.windowController as? EditorWindowController else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        guard editor.grabbitDocument.isDirty else {
            editor.window?.close()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "Your unsaved changes will be lost if you close without saving."
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            editor.saveAs(nil)
        case .alertSecondButtonReturn:
            editor.window?.close()
        default:
            break
        }
    }

    @objc private func quitGrabbit() {
        let dirtyEditors = NSApp.windows
            .compactMap { $0.windowController as? EditorWindowController }
            .filter { $0.grabbitDocument.isDirty }

        guard !dirtyEditors.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        let count = dirtyEditors.count
        let alert = NSAlert()
        alert.messageText = count == 1
            ? "You have unsaved changes. Quit anyway?"
            : "You have \(count) images with unsaved changes. Quit anyway?"
        alert.informativeText = "Your unsaved changes will be lost."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Editor / Clipboard

    @objc func openEditor() {
        EditorWindowController.showEmpty()
    }

    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Image"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }

        if let editor = NSApp.keyWindow?.windowController as? EditorWindowController {
            editor.replaceImage(image)
        } else {
            EditorWindowController.show(image: image)
        }
    }

    @objc func newFromClipboard() {
        let pb = NSPasteboard.general

        guard let image = NSImage(pasteboard: pb) else {
            let alert = NSAlert()
            alert.messageText = "No Image on Clipboard"
            alert.informativeText = "Copy an image to the clipboard first, then choose New from Clipboard."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        if let editor = NSApp.keyWindow?.windowController as? EditorWindowController {
            editor.replaceImage(image)
        } else {
            EditorWindowController.show(image: image)
        }
    }

    // MARK: - About

    @objc private func openAbout() {
        AboutWindowController.show()
    }

    // MARK: - Tools menu

    private func buildToolsMenu() -> NSMenu {
        let menu = NSMenu(title: "Tools")
        let sc = ToolShortcutsConfig.load()

        func addTool(_ title: String, action: Selector, config: HotkeyConfig) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: config.menuKeyEquivalent)
            item.keyEquivalentModifierMask = config.menuModifierMask
            menu.addItem(item)
            return item
        }

        toolMenuItems = [
            addTool("Crop",         action: #selector(EditorWindowController.activateCropTool(_:)),      config: sc.crop),
            addTool("Resize",       action: #selector(EditorWindowController.activateResizeTool(_:)),    config: sc.resize),
            addTool("Extract Text", action: #selector(EditorWindowController.activateOCRTool(_:)),       config: sc.ocr),
        ]
        menu.addItem(.separator())
        toolMenuItems += [
            addTool("Arrow",        action: #selector(EditorWindowController.activateArrowTool(_:)),     config: sc.arrow),
            addTool("Text",         action: #selector(EditorWindowController.activateTextTool(_:)),      config: sc.text),
            addTool("Shape",        action: #selector(EditorWindowController.activateShapeTool(_:)),     config: sc.shape),
            addTool("Blur",         action: #selector(EditorWindowController.activateBlurTool(_:)),      config: sc.blur),
            addTool("Highlight",    action: #selector(EditorWindowController.activateHighlightTool(_:)), config: sc.highlight),
        ]

        return menu
    }

    private func updateToolMenuKeyEquivalents(_ shortcuts: ToolShortcutsConfig) {
        let configs: [HotkeyConfig] = [
            shortcuts.crop, shortcuts.resize, shortcuts.ocr,
            shortcuts.arrow, shortcuts.text, shortcuts.shape,
            shortcuts.blur, shortcuts.highlight,
        ]
        for (item, config) in zip(toolMenuItems, configs) {
            item.keyEquivalent = config.menuKeyEquivalent
            item.keyEquivalentModifierMask = config.menuModifierMask
        }
    }

    // MARK: - Settings

    @objc private func openSettings() {
        SettingsWindowController.show(
            currentConfig:  hotkeyManager.config,
            quickConfig:    hotkeyManager.quickConfig,
            toolShortcuts:  ToolShortcutsConfig.load(),
            delegate:       self
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

    func settingsDidUpdateToolShortcuts(_ shortcuts: ToolShortcutsConfig) {
        shortcuts.save()
        updateToolMenuKeyEquivalents(shortcuts)
        NSApp.windows
            .compactMap { $0.windowController as? EditorWindowController }
            .forEach { $0.updateToolShortcuts(shortcuts) }
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

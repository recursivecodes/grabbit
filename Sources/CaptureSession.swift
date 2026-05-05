import AppKit
import CoreGraphics
import ScreenCaptureKit
import UserNotifications

class CaptureSession {

    // Prevents re-entrant captures (hotkey fired while overlay is already up,
    // or while the async SCK capture is still in flight).
    private static var isCapturing = false

    // Mode for the current capture.
    private enum Mode { case editor, quickClipboard }
    private static var mode: Mode = .editor

    static func start() {
        beginCapture(mode: .editor)
    }

    static func startQuick() {
        beginCapture(mode: .quickClipboard)
    }

    private static func beginCapture(mode: Mode) {
        guard !isCapturing else {
            NSLog("Grabbit: capture already in progress, ignoring hotkey")
            return
        }

        guard CGPreflightScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "Grant access in System Settings › Privacy & Security › Screen Recording, then relaunch Grabbit."
            alert.runModal()
            return
        }

        // Use the screen the cursor is currently on, not necessarily the primary.
        // Fall back to the main screen if the cursor position can't be matched.
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                  ?? NSScreen.main
                  ?? NSScreen.screens[0]

        isCapturing = true
        Self.mode = mode

        if #available(macOS 14.0, *) {
            captureWithSCK(screen: screen)
        } else {
            fallbackCapture(screen: screen)
        }
    }

    // Called by OverlayWindowController when the overlay is fully dismissed,
    // whether by a successful selection, a cancel, or an error.
    static func captureDidEnd() {
        isCapturing = false
    }

    // Called by OverlayWindowController with the cropped image once the user
    // makes a selection. Routes to editor or clipboard depending on mode.
    static func captureDidFinish(image: NSImage) {
        switch mode {
        case .editor:
            let doc = GrabbitDocument(image: image)
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            EditorWindowController.activateApp()
        case .quickClipboard:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
            sendClipboardNotification()
        }
    }

    private static func sendClipboardNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Grabbit"
            content.body  = "Screenshot copied to clipboard."
            let request = UNNotificationRequest(
                identifier: "grabbit.quickcapture.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    // MARK: - ScreenCaptureKit path (macOS 14+)

    @available(macOS 14.0, *)
    private static func captureWithSCK(screen: NSScreen) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)

                // Match the SCDisplay to the target screen by display ID.
                // NSScreen.deviceDescription carries the CGDirectDisplayID.
                let targetDisplayID = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    ?? CGMainDisplayID()

                guard let display = content.displays.first(where: { $0.displayID == targetDisplayID })
                else {
                    await MainActor.run { fallbackCapture(screen: screen) }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                // Use the target screen's own backing scale factor, not the main screen's.
                let scale = screen.backingScaleFactor
                config.width  = Int(Double(display.width)  * scale)
                config.height = Int(Double(display.height) * scale)
                config.scalesToFit = false
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config)
                // Set NSImage.size to the actual pixel dimensions (not screen.frame.size
                // which is in points). This keeps size == pixels throughout the pipeline.
                let pixelSize = NSSize(width: cgImage.width, height: cgImage.height)
                let screenshot = NSImage(cgImage: cgImage, size: pixelSize)

                await MainActor.run {
                    OverlayWindowController.show(screenshot: screenshot, screen: screen)
                }
            } catch {
                NSLog("Grabbit: SCK capture failed: \(error)")
                await MainActor.run { fallbackCapture(screen: screen) }
            }
        }
    }

    // MARK: - Fallback for macOS < 14

    private static func fallbackCapture(screen: NSScreen) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grabbit_cap.png")
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-x", "-t", "png", tmp.path]
        task.launch()
        task.waitUntilExit()

        guard let img = NSImage(contentsOf: tmp) else {
            NSLog("Grabbit: fallback screencapture failed")
            captureDidEnd()   // unblock so the hotkey works next time
            return
        }
        try? FileManager.default.removeItem(at: tmp)
        OverlayWindowController.show(screenshot: img, screen: screen)
    }
}

import AppKit
import CoreGraphics
import ScreenCaptureKit

class CaptureSession {
    static func start() {
        guard CGPreflightScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "Grant access in System Settings › Privacy & Security › Screen Recording, then relaunch Grabbit."
            alert.runModal()
            return
        }

        guard let screen = NSScreen.main else { return }

        // Use ScreenCaptureKit on macOS 14+. The capture is async internally
        // but we dispatch back to the main queue for the overlay presentation.
        if #available(macOS 14.0, *) {
            captureWithSCK(screen: screen)
        } else {
            fallbackCapture(screen: screen)
        }
    }

    // MARK: - ScreenCaptureKit path (macOS 14+)

    @available(macOS 14.0, *)
    private static func captureWithSCK(screen: NSScreen) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                    await MainActor.run { fallbackCapture(screen: screen) }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                // Use pixel dimensions (points × backing scale) so the CGImage
                // is full-resolution and matches what finishCapture expects when
                // it multiplies the selection rect by backingScaleFactor.
                let scale = screen.backingScaleFactor
                config.width  = Int(Double(display.width)  * scale)
                config.height = Int(Double(display.height) * scale)
                config.scalesToFit = false
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let screenshot = NSImage(cgImage: cgImage, size: screen.frame.size)

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
        // CGDisplayCreateImage is available pre-macOS 15.
        let displayID = CGMainDisplayID()
        let selector = NSSelectorFromString("CGDisplayCreateImage:")
        _ = selector  // suppress unused warning

        // Use a temporary file via screencapture as the universal fallback.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("grabbit_cap.png")
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-x", "-t", "png", tmp.path]
        task.launch()
        task.waitUntilExit()

        guard let img = NSImage(contentsOf: tmp) else {
            NSLog("Grabbit: fallback screencapture failed")
            return
        }
        try? FileManager.default.removeItem(at: tmp)
        OverlayWindowController.show(screenshot: img, screen: screen)
    }
}

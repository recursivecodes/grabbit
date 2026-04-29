import AppKit
import CoreGraphics

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

        // CGWindowListCreateImage captures the full display contents and is
        // available on all supported macOS versions without deprecation.
        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        guard let cgImage = CGWindowListCreateImage(
            displayBounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            NSLog("Grabbit: CGWindowListCreateImage returned nil")
            return
        }

        let screenshot = NSImage(cgImage: cgImage, size: screen.frame.size)
        OverlayWindowController.show(screenshot: screenshot, screen: screen)
    }
}

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

        // CGDisplayCreateImage is deprecated in macOS 14 but remains functional.
        // Replace with ScreenCaptureKit when adding async capture support.
        let displayID = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            NSLog("Grabbit: CGDisplayCreateImage returned nil")
            return
        }

        let screenshot = NSImage(cgImage: cgImage, size: screen.frame.size)
        OverlayWindowController.show(screenshot: screenshot, screen: screen)
    }
}

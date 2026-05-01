import AppKit

// Subclass so the borderless window can become key (required for keyboard events).
private class OverlayWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }

    // Last-resort Escape handler at the window level, in case the overlay view
    // somehow loses first responder and can't receive keyDown events.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            (contentView as? OverlayView)?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}

class OverlayWindowController: NSWindowController {
    // Strong reference keeps the controller alive until capture is done.
    private static var current: OverlayWindowController?

    static func show(screenshot: NSImage, screen: NSScreen) {
        // Defensive: if a stale overlay somehow survived, tear it down first.
        if let existing = current {
            NSLog("Grabbit: tearing down stale overlay before showing new one")
            existing.forceClose()
        }
        let controller = OverlayWindowController(screenshot: screenshot, screen: screen)
        current = controller
        controller.showWindow(nil)
    }

    private let overlayView: OverlayView

    init(screenshot: NSImage, screen: NSScreen) {
        let win = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isOpaque = true
        win.backgroundColor = .black
        win.acceptsMouseMovedEvents = true

        overlayView = OverlayView(screenshot: screenshot, frame: screen.frame)
        win.contentView = overlayView

        super.init(window: win)

        overlayView.onSelection = { [weak self] viewRect in
            self?.finishCapture(viewRect: viewRect, screenshot: screenshot, screen: screen)
        }
        overlayView.onCancel = { [weak self] in
            self?.dismiss()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(overlayView)
    }

    // Normal dismiss: cancel or post-capture.
    private func dismiss() {
        // Restore the default arrow cursor before closing.
        NSCursor.arrow.set()
        close()
        Self.current = nil
        CaptureSession.captureDidEnd()
    }

    // Force-close used when tearing down a stale overlay.
    private func forceClose() {
        close()
        Self.current = nil
        // Don't call captureDidEnd here — the caller manages that.
    }

    private func finishCapture(viewRect: NSRect, screenshot: NSImage, screen: NSScreen) {
        let scale = screen.backingScaleFactor
        let pixelRect = CGRect(
            x: viewRect.origin.x * scale,
            y: viewRect.origin.y * scale,
            width: viewRect.size.width * scale,
            height: viewRect.size.height * scale
        )

        guard
            let cgFull    = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let cgCropped = cgFull.cropping(to: pixelRect)
        else {
            // Crop failed — dismiss cleanly so the app isn't stuck.
            NSLog("Grabbit: crop failed, dismissing overlay")
            dismiss()
            return
        }

        let cropped = NSImage(cgImage: cgCropped, size: viewRect.size)

        // Dismiss the overlay first so it's fully gone before the editor
        // activates — having a screenSaver-level window close during activation
        // can interfere with the menu bar appearing.
        dismiss()
        EditorWindowController.show(image: cropped)
    }
}

// MARK: - Overlay view

private class OverlayView: NSView {
    private let screenshot: NSImage
    private var startPoint:   NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    var onSelection: ((NSRect) -> Void)?
    var onCancel:    (() -> Void)?

    // Flipped so y=0 is at the top, matching CGImage's coordinate layout.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(screenshot: NSImage, frame: NSRect) {
        self.screenshot = screenshot
        super.init(frame: frame)
        // Track mouse-entered/exited so we can set the cursor as soon as
        // the pointer enters the overlay, before any click or drag.
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved,
                                            .cursorUpdate, .activeAlways]
        addTrackingArea(NSTrackingArea(rect: frame, options: opts, owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Cursor — set it on every entry point so it's always a crosshair.

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // Called by both keyDown and the window-level fallback.
    func cancel() {
        isDragging = false
        onCancel?()
    }

    private var selectionRect: NSRect {
        NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width:  abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        screenshot.draw(in: bounds)

        guard isDragging else { return }

        // Darken everything outside the selection using even-odd fill.
        let overlay = NSBezierPath(rect: bounds)
        let sel = selectionRect
        if sel.width > 0 && sel.height > 0 {
            overlay.append(NSBezierPath(rect: sel))
        }
        overlay.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        overlay.fill()

        // Selection border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()

        // Dimension label
        let label = String(format: "%.0f × %.0f", sel.width, sel.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let labelRect = NSRect(
            x: sel.maxX - labelSize.width - 6,
            y: sel.maxY + 4,
            width: labelSize.width + 6,
            height: labelSize.height + 2
        )
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        (label as NSString).draw(
            at: NSPoint(x: labelRect.origin.x + 3, y: labelRect.origin.y + 1),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        startPoint   = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging   = false
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging   = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let rect = selectionRect
        if rect.width > 5 && rect.height > 5 {
            onSelection?(rect)
        } else {
            // Selection too small — reset silently, don't dismiss.
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancel()
        }
    }
}

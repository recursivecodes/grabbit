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
        CaptureSession.captureDidFinish(image: cropped)
    }
}

// MARK: - Overlay view

private class OverlayView: NSView {
    private let screenshot: NSImage
    private var startPoint:   NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    // Window-snap state: the highlighted window rect in view coordinates,
    // or nil when the cursor isn't hovering over a detectable window.
    private var highlightedWindowRect: NSRect? = nil

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
        // Only do window detection when not in a drag.
        guard !isDragging else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        updateWindowHighlight(at: viewPoint)
    }

    // Called by both keyDown and the window-level fallback.
    func cancel() {
        isDragging = false
        highlightedWindowRect = nil
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

    // MARK: - Window detection

    /// Queries the window list and updates `highlightedWindowRect` for the
    /// topmost on-screen window under `viewPoint` (in view/flipped coordinates).
    private func updateWindowHighlight(at viewPoint: NSPoint) {
        guard let screen = window?.screen ?? NSScreen.main else {
            highlightedWindowRect = nil
            needsDisplay = true
            return
        }

        // CGWindowBounds uses Quartz screen coordinates:
        //   • origin is the top-left of the primary display
        //   • y increases downward
        //   • multi-monitor: secondary screens have negative or large positive X/Y
        //
        // viewPoint is in flipped NSView coordinates (y=0 at top of THIS screen).
        // Convert to Quartz screen space:
        //   quartzX = screen.frame.origin.x + viewPoint.x
        //   quartzY = (primaryScreenHeight - screen.frame.maxY) + viewPoint.y
        //
        // NSScreen.frame uses AppKit coords (y=0 at bottom of primary display),
        // so primaryScreenHeight - screen.frame.maxY gives the Quartz Y of the
        // top edge of this screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let quartzPoint = CGPoint(
            x: screen.frame.origin.x + viewPoint.x,
            y: (primaryHeight - screen.frame.maxY) + viewPoint.y
        )

        let newRect = windowRect(atQuartzPoint: quartzPoint, screen: screen, primaryHeight: primaryHeight)
        if newRect != highlightedWindowRect {
            highlightedWindowRect = newRect
            needsDisplay = true
        }
    }

    /// Returns the view-space rect of the topmost on-screen window at the
    /// given Quartz screen point (y=0 at top of primary display), or nil if none.
    private func windowRect(atQuartzPoint quartzPoint: CGPoint,
                            screen: NSScreen,
                            primaryHeight: CGFloat) -> NSRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        // Our own overlay window ID — skip it so we see through to windows below.
        let ownID = window.map { CGWindowID($0.windowNumber) }

        // Windows are returned front-to-back; find the first non-overlay window
        // that contains the cursor point.
        for info in windowList {
            // Skip our own overlay.
            if let wid = info[kCGWindowNumber as String] as? Int,
               let oid = ownID, CGWindowID(wid) == oid { continue }

            // Skip windows at the screenSaver level or above (other overlays, etc.)
            // and below 0 (desktop/wallpaper).
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= 0, layer < 25
            else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            // CGWindowBounds is already in Quartz screen coordinates.
            let quartzRect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width:  boundsDict["Width"]  ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Skip tiny or invisible windows.
            guard quartzRect.width > 10, quartzRect.height > 10 else { continue }

            guard quartzRect.contains(quartzPoint) else { continue }

            // Convert Quartz rect → view (flipped) coordinates on this screen.
            // Quartz Y of this screen's top edge = primaryHeight - screen.frame.maxY
            let screenQuartzTop = primaryHeight - screen.frame.maxY
            let viewRect = NSRect(
                x: quartzRect.origin.x - screen.frame.origin.x,
                y: quartzRect.origin.y - screenQuartzTop,
                width:  quartzRect.width,
                height: quartzRect.height
            )

            // Clamp to the visible screen area.
            let clipped = viewRect.intersection(bounds)
            guard !clipped.isNull, clipped.width > 10, clipped.height > 10 else { continue }

            return clipped
        }
        return nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        screenshot.draw(in: bounds)

        if isDragging {
            drawFreehandSelection()
        } else if let winRect = highlightedWindowRect {
            drawWindowHighlight(winRect)
        }
    }

    private func drawFreehandSelection() {
        let sel = selectionRect
        guard sel.width > 0, sel.height > 0 else { return }

        // Darken everything outside the selection using even-odd fill.
        let overlay = NSBezierPath(rect: bounds)
        overlay.append(NSBezierPath(rect: sel))
        overlay.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        overlay.fill()

        // Selection border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()

        drawDimensionLabel(for: sel)
    }

    private func drawWindowHighlight(_ rect: NSRect) {
        // Dim everything outside the highlighted window.
        let overlay = NSBezierPath(rect: bounds)
        overlay.append(NSBezierPath(rect: rect))
        overlay.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        overlay.fill()

        // Bright blue border to signal window-snap mode.
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2.0
        NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        border.stroke()

        // Subtle inner glow.
        let innerRect = rect.insetBy(dx: 1, dy: 1)
        let inner = NSBezierPath(rect: innerRect)
        inner.lineWidth = 1.0
        NSColor.white.withAlphaComponent(0.25).setStroke()
        inner.stroke()

        drawDimensionLabel(for: rect)
    }

    private func drawDimensionLabel(for rect: NSRect) {
        let label = String(format: "%.0f × %.0f", rect.width, rect.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = (label as NSString).size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.maxX - labelSize.width - 6,
            y: rect.maxY + 4,
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

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        startPoint   = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging   = false
        // Don't clear highlightedWindowRect yet — mouseUp may use it for a click-to-capture.
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging   = true
        // Entering drag mode: leave window-snap and go freehand.
        highlightedWindowRect = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // Freehand selection completed.
            isDragging = false
            let rect = selectionRect
            if rect.width > 5 && rect.height > 5 {
                onSelection?(rect)
            } else {
                // Selection too small — reset silently, don't dismiss.
                needsDisplay = true
            }
        } else if let winRect = highlightedWindowRect {
            // Click without drag while a window is highlighted → capture that window.
            highlightedWindowRect = nil
            onSelection?(winRect)
        }
        // Plain click with no window highlight and no drag: do nothing.
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancel()
        }
    }
}

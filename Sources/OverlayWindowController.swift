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

        overlayView.onSelection = { [weak self] viewRect, windowID in
            self?.finishCapture(viewRect: viewRect, windowID: windowID, screenshot: screenshot, screen: screen)
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

    private func finishCapture(viewRect: NSRect, windowID: CGWindowID?,
                               screenshot: NSImage, screen: NSScreen) {
        // ── Window-snap path: re-capture the specific window directly from the
        //    compositor, bypassing any windows drawn on top of it. ───────────────
        if let wid = windowID {
            let imageOptions: CGWindowImageOption = [
                .boundsIgnoreFraming,
                .bestResolution
            ]
            if let cgWindow = CGWindowListCreateImage(
                .null, .optionIncludingWindow, wid, imageOptions),
               cgWindow.width > 0, cgWindow.height > 0 {
                // CGWindowListCreateImage fills rounded-corner areas with opaque black.
                // Clip to a rounded rect so those corners are transparent in the output.
                let finalCG = transparentCorners(cgWindow, scale: screen.backingScaleFactor)
                let pixelSize = NSSize(width: finalCG.width, height: finalCG.height)
                let captured = NSImage(cgImage: finalCG, size: pixelSize)
                dismiss()
                CaptureSession.captureDidFinish(image: captured)
                return
            }
            // Fall through to crop path if CGWindowListCreateImage fails.
            NSLog("Grabbit: CGWindowListCreateImage failed for window \(wid), falling back to crop")
        }

        // ── Freehand crop path ───────────────────────────────────────────────────
        // screenshot.size is now in pixels (set at capture time), so viewRect
        // (in points) must be scaled to pixel coordinates.
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
            NSLog("Grabbit: crop failed, dismissing overlay")
            dismiss()
            return
        }

        let cropped = NSImage(cgImage: cgCropped, size: NSSize(width: cgCropped.width, height: cgCropped.height))
        dismiss()
        CaptureSession.captureDidFinish(image: cropped)
    }

    /// Redraws a window image into an alpha context clipped to a rounded rect,
    /// removing the opaque black fill CGWindowListCreateImage produces for
    /// windows with rounded corners (Finder, Safari, etc.).
    /// Returns the original image unchanged if no black corners are detected.
    private func transparentCorners(_ cgImage: CGImage, scale: CGFloat) -> CGImage {
        let r = detectedCornerRadius(in: cgImage)
        guard r > 0 else { return cgImage }

        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return cgImage }
        ctx.addPath(CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
            cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return ctx.makeImage() ?? cgImage
    }

    /// Samples a corner of the image to measure the black fill CGWindowListCreateImage
    /// places in rounded-corner areas. Returns the detected radius in pixels, or 0 if
    /// no meaningful black fill is found (window has no rounded corners, or is rectangular).
    private func detectedCornerRadius(in cgImage: CGImage) -> CGFloat {
        let maxScan = min(80, cgImage.width / 4, cgImage.height / 4)
        guard maxScan > 4 else { return 0 }

        // Crop the corner at CG (x=0, y=0). macOS windows have rounded corners on all
        // four sides with the same radius, so any corner works regardless of Y orientation.
        guard let corner = cgImage.cropping(to: CGRect(x: 0, y: 0, width: maxScan, height: maxScan))
        else { return 0 }

        // Render into a known RGBA8 layout for straightforward byte access.
        guard let ctx = CGContext(
            data: nil, width: maxScan, height: maxScan,
            bitsPerComponent: 8, bytesPerRow: maxScan * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        ctx.draw(corner, in: CGRect(x: 0, y: 0, width: maxScan, height: maxScan))

        guard let ptr = ctx.data?.bindMemory(to: UInt8.self, capacity: maxScan * maxScan * 4)
        else { return 0 }

        // Scan the bottom row (memory row 0, RGBA). Black pixels are corner fill.
        var edge = 0
        for x in 0..<maxScan {
            let off = x * 4
            if Int(ptr[off]) + Int(ptr[off + 1]) + Int(ptr[off + 2]) > 30 { edge = x; break }
            if x == maxScan - 1 { return 0 }   // whole row is black — unexpected, bail
        }
        guard edge > 2 else { return 0 }        // no meaningful corner fill
        return CGFloat(edge) + 4                // +4 px margin to cover the arc fully
    }
}

// MARK: - Overlay view

private class OverlayView: NSView {
    private let screenshot: NSImage
    private var startPoint:   NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    // Window-snap state: the highlighted window rect in view coordinates plus
    // its CGWindowID, or nil when no window is under the cursor.
    private var highlightedWindowRect: NSRect? = nil
    private var highlightedWindowID:   CGWindowID? = nil

    // onSelection carries the view rect and an optional window ID.
    // windowID is non-nil only for window-snap clicks (not freehand drags).
    var onSelection: ((NSRect, CGWindowID?) -> Void)?
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
        highlightedWindowID   = nil
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

    /// Queries the window list and updates `highlightedWindowRect` / `highlightedWindowID`
    /// for the topmost on-screen window under `viewPoint` (in view/flipped coordinates).
    private func updateWindowHighlight(at viewPoint: NSPoint) {
        guard let screen = window?.screen ?? NSScreen.main else {
            highlightedWindowRect = nil
            highlightedWindowID   = nil
            needsDisplay = true
            return
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let quartzPoint = CGPoint(
            x: screen.frame.origin.x + viewPoint.x,
            y: (primaryHeight - screen.frame.maxY) + viewPoint.y
        )

        let result = windowInfo(atQuartzPoint: quartzPoint, screen: screen, primaryHeight: primaryHeight)
        let newRect = result?.rect
        if newRect != highlightedWindowRect {
            highlightedWindowRect = newRect
            highlightedWindowID   = result?.windowID
            needsDisplay = true
        }
    }

    /// Returns the view-space rect and CGWindowID of the topmost on-screen window at the
    /// given Quartz screen point (y=0 at top of primary display), or nil if none.
    private func windowInfo(atQuartzPoint quartzPoint: CGPoint,
                            screen: NSScreen,
                            primaryHeight: CGFloat) -> (rect: NSRect, windowID: CGWindowID)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }

        let ownID = window.map { CGWindowID($0.windowNumber) }

        for info in windowList {
            // Skip our own overlay.
            if let wid = info[kCGWindowNumber as String] as? Int,
               let oid = ownID, CGWindowID(wid) == oid { continue }

            // Only normal app-level windows (layer 0).
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }

            // Skip Dock-owned windows (desktop, Mission Control backgrounds, etc.).
            if let owner = info[kCGWindowOwnerName as String] as? String,
               owner == "Dock" { continue }

            // Skip fully transparent or invisible windows.
            if let alpha = info[kCGWindowAlpha as String] as? CGFloat,
               alpha <= 0 { continue }

            // Must actually be on-screen.
            guard let onScreen = info[kCGWindowIsOnscreen as String] as? Bool,
                  onScreen else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let wid = info[kCGWindowNumber as String] as? Int
            else { continue }

            let quartzRect = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width:  boundsDict["Width"]  ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            guard quartzRect.width > 50, quartzRect.height > 50 else { continue }
            guard quartzRect.contains(quartzPoint) else { continue }

            let screenQuartzTop = primaryHeight - screen.frame.maxY
            let viewRect = NSRect(
                x: quartzRect.origin.x - screen.frame.origin.x,
                y: quartzRect.origin.y - screenQuartzTop,
                width:  quartzRect.width,
                height: quartzRect.height
            )

            let clipped = viewRect.intersection(bounds)
            guard !clipped.isNull, clipped.width > 50, clipped.height > 50 else { continue }

            return (rect: clipped, windowID: CGWindowID(wid))
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
        highlightedWindowID   = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // Freehand selection completed — no window ID.
            isDragging = false
            let rect = selectionRect
            if rect.width > 5 && rect.height > 5 {
                onSelection?(rect, nil)
            } else {
                needsDisplay = true
            }
        } else if let winRect = highlightedWindowRect {
            // Click without drag while a window is highlighted → capture that window.
            let wid = highlightedWindowID
            highlightedWindowRect = nil
            highlightedWindowID   = nil
            onSelection?(winRect, wid)
        }
        // Plain click with no window highlight and no drag: do nothing.
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancel()
        }
    }
}

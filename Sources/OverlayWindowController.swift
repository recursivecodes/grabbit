import AppKit

// Subclass so the borderless window can become key (required for keyboard events).
private class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class OverlayWindowController: NSWindowController {
    // Strong reference keeps the controller alive until capture is done.
    private static var current: OverlayWindowController?

    static func show(screenshot: NSImage, screen: NSScreen) {
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

    private func dismiss() {
        NSCursor.pop()
        close()
        Self.current = nil
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
            let cgFull = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let cgCropped = cgFull.cropping(to: pixelRect)
        else { dismiss(); return }

        let cropped = NSImage(cgImage: cgCropped, size: viewRect.size)

        // Show the editor BEFORE closing the overlay so focus never transfers
        // to another app — that's what causes the menu bar to show the wrong app.
        EditorWindowController.show(image: cropped)
        dismiss()
    }
}

// MARK: - Overlay view

private class OverlayView: NSView {
    private let screenshot: NSImage
    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    var onSelection: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    // Flipped so y=0 is at the top, matching CGImage's coordinate layout.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(screenshot: NSImage, frame: NSRect) {
        self.screenshot = screenshot
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selectionRect: NSRect {
        NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
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
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        let rect = selectionRect
        if rect.width > 5 && rect.height > 5 {
            onSelection?(rect)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }
}

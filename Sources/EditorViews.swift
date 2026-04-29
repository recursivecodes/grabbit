import AppKit

// MARK: - ZoomableScrollView

class ZoomableScrollView: NSScrollView {
    var onMagnificationChanged: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event); return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let factor: CGFloat = delta > 0 ? 1.08 : 1 / 1.08
        let newMag = (magnification * factor).clamped(to: minMagnification...maxMagnification)
        let center = convert(event.locationInWindow, from: nil)
        setMagnification(newMag, centeredAt: center)
        onMagnificationChanged?()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

// MARK: - FlippedClipView

class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - CanvasView

class CanvasView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.93, alpha: 1).setFill()
        dirtyRect.fill()
    }
}

// MARK: - CGPoint clamp helper

extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: max(rect.minX, min(rect.maxX, x)),
            y: max(rect.minY, min(rect.maxY, y))
        )
    }
}

// MARK: - UI builder helpers

func makeToolButton(_ title: String) -> NSButton {
    let b = NSButton()
    b.title = title
    b.setButtonType(.toggle)
    b.bezelStyle = .rounded
    b.translatesAutoresizingMaskIntoConstraints = false
    return b
}

func sld(_ min: Double, _ max: Double, _ val: Double) -> NSSlider {
    let s = NSSlider(value: val, minValue: min, maxValue: max, target: nil, action: nil)
    s.controlSize = .small; return s
}

func well(_ color: NSColor) -> NSColorWell {
    let w = NSColorWell(); w.color = color; return w
}

func vlbl(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    f.alignment = .right
    f.translatesAutoresizingMaskIntoConstraints = false
    f.widthAnchor.constraint(equalToConstant: 36).isActive = true
    f.setContentHuggingPriority(.required, for: .horizontal)
    return f
}

func fmt(_ v: CGFloat) -> String { "\(Int(v))" }
func fmtPct(_ v: CGFloat) -> String { "\(Int(v * 100))%" }

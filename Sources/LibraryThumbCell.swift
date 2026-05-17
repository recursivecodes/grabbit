import AppKit

// MARK: - LibraryThumbCell

/// A thumbnail cell in the library strip. Dynamically sized from the footer height.
/// Tapping selects the corresponding library entry.
class LibraryThumbCell: NSView {

    private static let aspectRatio: CGFloat = 120.0 / 98.0

    static func cellSize(forFooterHeight h: CGFloat) -> CGSize {
        let cellH = max(32, h - 12)
        return CGSize(width: (cellH * aspectRatio).rounded(), height: cellH)
    }

    var index: Int = 0

    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    var onSelect: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?
    var onRevealInFinder: (() -> Void)?

    var thumbnail: NSImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }

    private let imageView  = NSImageView()
    private var widthConstraint:  NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!

    // MARK: - Init

    init(index: Int, entry: LibraryEntry, footerHeight: CGFloat) {
        self.index = index
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = entry.thumbnailImage
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true

        addSubview(imageView)

        let sz = Self.cellSize(forFooterHeight: footerHeight)
        widthConstraint  = widthAnchor.constraint(equalToConstant: sz.width)
        heightConstraint = heightAnchor.constraint(equalToConstant: sz.height)

        NSLayoutConstraint.activate([
            widthConstraint, heightConstraint,

            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func updateSize(footerHeight: CGFloat) {
        let sz = Self.cellSize(forFooterHeight: footerHeight)
        widthConstraint.constant  = sz.width
        heightConstraint.constant = sz.height
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset: CGFloat = 1.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)

        if isSelected {
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(2)
            ctx.addPath(path); ctx.strokePath()
        } else {
            ctx.setFillColor(NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor)
            ctx.addPath(path); ctx.fillPath()
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let dup = NSMenuItem(title: "Duplicate", action: #selector(handleDuplicate), keyEquivalent: "")
        dup.target = self
        m.addItem(dup)
        let del = NSMenuItem(title: "Delete", action: #selector(handleDelete), keyEquivalent: "")
        del.target = self
        m.addItem(del)
        m.addItem(.separator())
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(handleReveal), keyEquivalent: "")
        reveal.target = self
        m.addItem(reveal)
        return m
    }

    @objc private func handleDuplicate()    { onDuplicate?() }
    @objc private func handleDelete()       { onDelete?() }
    @objc private func handleReveal()       { onRevealInFinder?() }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        needsDisplay = true
    }
}
